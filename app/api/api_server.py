"""FastAPI service joining the rice vision model with the local RAG agent."""

from __future__ import annotations

import io
import logging
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import torch
import torch.nn as nn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse, Response
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field
from dotenv import load_dotenv
from starlette.concurrency import run_in_threadpool
from torchvision import models, transforms

from app.agent import LLMUnavailableError, RiceDiseaseAgent
from app.agent.rice_agent import MODEL_CLASS_IDS


PROJECT_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(PROJECT_ROOT / ".env", override=False)
WEB_INDEX = PROJECT_ROOT / "app" / "api" / "web" / "index.html"
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000
MODEL_VERSION = "resnet50-svm-v1"
logger = logging.getLogger(__name__)
ARTIFACT_FILES = {
    "resnet": "fine_tuned_resnet.pth",
    "svm": "svm_model.pkl",
    "scaler": "scaler.pkl",
    "classes": "classes.pkl",
    "features": "best_features.npy",
}


class AgentStartRequest(BaseModel):
    class_id: str
    confidence_score: float | None = Field(default=None, ge=0, le=1)
    top_predictions: list[dict[str, Any]] = Field(default_factory=list)
    model_version: str | None = None
    image_quality: dict[str, Any] = Field(default_factory=dict)


class AgentChatRequest(BaseModel):
    session_id: str
    message: str = Field(min_length=1, max_length=2000)


class AgentResetRequest(BaseModel):
    session_id: str


def square_padding(image: Image.Image) -> Image.Image:
    """Match the deployed vision pipeline without stretching the input image."""

    width, height = image.size
    size = max(width, height)
    padded = Image.new("RGB", (size, size), (0, 0, 0))
    padded.paste(image, ((size - width) // 2, (size - height) // 2))
    return padded


class VisionRuntime:
    """Load the large vision artifacts lazily when prediction is first used."""

    def __init__(self, project_root: Path) -> None:
        self.project_root = project_root
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.loaded = False
        self.load_error: str | None = None
        self.classes: np.ndarray | None = None
        self.best_features: np.ndarray | None = None
        self.scaler: Any = None
        self.svm_model: Any = None
        self.backbone: nn.Module | None = None
        self.transform = transforms.Compose(
            [
                transforms.Resize((224, 224)),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225],
                ),
            ]
        )

    def artifact_paths(self) -> dict[str, Path]:
        return {
            key: self.project_root / filename
            for key, filename in ARTIFACT_FILES.items()
        }

    def missing_artifacts(self) -> list[str]:
        return [
            path.name for path in self.artifact_paths().values() if not path.is_file()
        ]

    def status(self) -> dict[str, Any]:
        missing = self.missing_artifacts()
        return {
            "ready": self.loaded or not missing,
            "loaded": self.loaded,
            "device": str(self.device),
            "model_version": MODEL_VERSION,
            "missing_artifacts": missing,
            "load_error": self.load_error,
            "supported_classes": list(MODEL_CLASS_IDS),
        }

    def load(self) -> None:
        if self.loaded:
            return
        missing = self.missing_artifacts()
        if missing:
            raise RuntimeError("Thiếu file model: " + ", ".join(missing))

        paths = self.artifact_paths()
        try:
            classes = np.asarray(joblib.load(paths["classes"]), dtype=str)
            if set(classes.tolist()) != set(MODEL_CLASS_IDS):
                raise ValueError("classes.pkl không khớp 9 nhãn agent hỗ trợ")

            best_features = np.asarray(np.load(paths["features"]), dtype=int)
            if best_features.size == 0 or np.any(best_features < 0):
                raise ValueError("best_features.npy không chứa chỉ số hợp lệ")

            backbone = models.resnet50(weights=None)
            backbone.fc = nn.Linear(backbone.fc.in_features, len(classes))
            try:
                weights = torch.load(
                    paths["resnet"], map_location=self.device, weights_only=True
                )
            except TypeError:  # PyTorch cũ chưa hỗ trợ weights_only.
                weights = torch.load(paths["resnet"], map_location=self.device)
            backbone.load_state_dict(weights)
            backbone = nn.Sequential(*(list(backbone.children())[:-1]))
            backbone.eval().to(self.device)

            scaler = joblib.load(paths["scaler"])
            svm_model = joblib.load(paths["svm"])
            if int(np.max(best_features)) >= int(scaler.n_features_in_):
                raise ValueError("Chỉ số đặc trưng vượt số chiều mà scaler hỗ trợ")

            self.classes = classes
            self.best_features = best_features
            self.scaler = scaler
            self.svm_model = svm_model
            self.backbone = backbone
            self.loaded = True
            self.load_error = None
        except Exception as exc:
            self.load_error = str(exc)
            raise

    def predict(self, image: Image.Image) -> list[dict[str, Any]]:
        self.load()
        assert self.backbone is not None
        assert self.classes is not None
        assert self.best_features is not None

        tensor = self.transform(square_padding(image)).unsqueeze(0).to(self.device)
        with torch.no_grad():
            features = self.backbone(tensor).view(1, -1).cpu().numpy()
        scaled = self.scaler.transform(features)
        selected = scaled[:, self.best_features]
        probabilities = np.asarray(self.svm_model.predict_proba(selected)[0])
        encoded_classes = np.asarray(self.svm_model.classes_)

        predictions: list[dict[str, Any]] = []
        for encoded, probability in zip(encoded_classes, probabilities):
            try:
                class_id = str(self.classes[int(encoded)])
            except (TypeError, ValueError, IndexError):
                class_id = str(encoded)
            predictions.append(
                {"class_id": class_id, "confidence_score": float(probability)}
            )
        return sorted(
            predictions, key=lambda item: item["confidence_score"], reverse=True
        )


def assess_image_quality(image: Image.Image) -> dict[str, Any]:
    width, height = image.size
    gray = np.asarray(image.convert("L").resize((224, 224)), dtype=np.float32)
    edge_energy = float(
        (np.abs(np.diff(gray, axis=0)).mean() + np.abs(np.diff(gray, axis=1)).mean())
        / 2
    )
    issues: list[str] = []
    if min(width, height) < 224:
        issues.append("Ảnh có độ phân giải thấp")
    if edge_energy < 3.0:
        issues.append("Ảnh có thể bị mờ hoặc thiếu chi tiết")
    return {
        "acceptable": not issues,
        "width": width,
        "height": height,
        "edge_energy": round(edge_energy, 2),
        "issues": issues,
    }


app = FastAPI(
    title="Smart Agriculture Rice API",
    version="3.0.0",
    description="Nhận diện bệnh lúa và tư vấn bằng RAG với model ngôn ngữ.",
    docs_url="/api-docs",
    redoc_url=None,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

vision_runtime = VisionRuntime(PROJECT_ROOT)
rice_agent = RiceDiseaseAgent()


@app.get("/", include_in_schema=False)
def web_interface() -> FileResponse:
    return FileResponse(WEB_INDEX, media_type="text/html; charset=utf-8")


@app.get("/docs", include_in_schema=False)
def legacy_docs_redirect() -> RedirectResponse:
    return RedirectResponse(url="/", status_code=307)


@app.get("/favicon.ico", include_in_schema=False)
def favicon() -> Response:
    return Response(status_code=204)


@app.get("/health")
def health() -> dict[str, Any]:
    vision = vision_runtime.status()
    agent = rice_agent.status()
    return {
        "status": "ok" if vision["ready"] and agent["ready"] else "degraded",
        "vision_ready": vision["ready"],
        "agent_ready": agent["ready"],
        "vision": vision,
        "agent": agent,
    }


@app.get("/model-info")
def model_info() -> dict[str, Any]:
    return vision_runtime.status()


@app.get("/agent/model-info")
def agent_model_info() -> dict[str, Any]:
    return rice_agent.status()


@app.post("/predict")
async def predict_disease(file: UploadFile = File(...)) -> dict[str, Any]:
    image_data = await file.read(MAX_UPLOAD_BYTES + 1)
    if not image_data:
        raise HTTPException(status_code=400, detail="Tệp ảnh rỗng")
    if len(image_data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Ảnh vượt quá giới hạn 10 MB")

    try:
        with Image.open(io.BytesIO(image_data)) as uploaded_image:
            if uploaded_image.width * uploaded_image.height > MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=413,
                    detail="Kích thước ảnh vượt quá giới hạn hỗ trợ.",
                )
            uploaded_image.verify()
        with Image.open(io.BytesIO(image_data)) as uploaded_image:
            image = uploaded_image.convert("RGB")
            image.load()
    except HTTPException:
        raise
    except (
        Image.DecompressionBombError,
        UnidentifiedImageError,
        OSError,
        ValueError,
    ) as exc:
        raise HTTPException(
            status_code=400, detail="Không đọc được nội dung ảnh"
        ) from exc

    image_quality = assess_image_quality(image)
    try:
        top_predictions = await run_in_threadpool(vision_runtime.predict, image)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Rice vision model failed to process an image")
        raise HTTPException(
            status_code=500,
            detail="Model không thể xử lý ảnh. Vui lòng thử lại sau.",
        ) from exc

    if not top_predictions:
        raise HTTPException(status_code=500, detail="Model không trả về dự đoán")

    best = top_predictions[0]
    class_id = best["class_id"]
    record = rice_agent.classes[class_id]
    agent_error = None
    try:
        agent_result = await run_in_threadpool(
            rice_agent.start_diagnosis,
            class_id,
            best["confidence_score"],
            top_predictions[:3],
            MODEL_VERSION,
            image_quality,
        )
    except LLMUnavailableError as exc:
        # Không làm mất kết quả model ảnh nếu Ollama đang tắt.
        agent_result = None
        agent_error = str(exc)

    return {
        "class_id": class_id,
        "disease": record["display_name"],
        "confidence": round(best["confidence_score"] * 100, 2),
        "confidence_score": best["confidence_score"],
        "top_predictions": top_predictions[:3],
        "image_quality": image_quality,
        "severity": None,
        "severity_note": (
            "Độ tin cậy phân loại không phải mức độ nặng của bệnh; "
            "một ảnh đơn lẻ chưa đủ để đo mức độ bệnh."
        ),
        "agent": agent_result,
        "agent_error": agent_error,
    }


@app.post("/agent/start")
def agent_start(request: AgentStartRequest) -> dict[str, Any]:
    try:
        return rice_agent.start_diagnosis(
            class_id=request.class_id,
            confidence=request.confidence_score,
            top_predictions=request.top_predictions,
            model_version=request.model_version,
            image_quality=request.image_quality,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/agent/chat")
def agent_chat(request: AgentChatRequest) -> dict[str, Any]:
    try:
        return rice_agent.chat(request.session_id, request.message)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/agent/session/{session_id}")
def agent_session(session_id: str) -> dict[str, Any]:
    try:
        return rice_agent.get_session(session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.post("/agent/reset")
def agent_reset(request: AgentResetRequest) -> dict[str, Any]:
    if not rice_agent.reset(request.session_id):
        raise HTTPException(status_code=404, detail="Không tìm thấy phiên tư vấn")
    return {"deleted": True, "session_id": request.session_id}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.api.api_server:app", host="0.0.0.0", port=8000, reload=False)
