import io
import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Callable

from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from PIL import Image, UnidentifiedImageError

logger = logging.getLogger(__name__)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MAX_IMAGE_BYTES = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000


class PredictionResponse(BaseModel):
    disease: str
    confidence: float = Field(ge=0, le=100, description="Maximum class probability, as a percentage.")


class APIError(Exception):
    def __init__(self, code: str, message: str, status_code: int):
        self.code = code
        self.message = message
        self.status_code = status_code


def _validate_image(image_data: bytes) -> None:
    if not image_data:
        raise APIError("empty_image", "The uploaded image is empty.", 400)

    if len(image_data) > MAX_IMAGE_BYTES:
        raise APIError("image_too_large", "The image exceeds the 10 MB size limit.", 413)

    try:
        with Image.open(io.BytesIO(image_data)) as image:
            if image.width * image.height > MAX_IMAGE_PIXELS:
                raise APIError(
                    "image_dimensions_too_large",
                    "The image dimensions exceed the supported limit.",
                    413,
                )
            image.verify()
    except APIError:
        raise
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError) as error:
        raise APIError(
            "invalid_image",
            "The uploaded file is not a supported, valid image.",
            400,
        ) from error


@lru_cache(maxsize=1)
def _load_prediction_pipeline():
    import joblib
    import numpy as np
    import torch
    import torch.nn as nn
    from torchvision import models, transforms

    scaler = joblib.load(PROJECT_ROOT / "scaler.pkl")
    classes = joblib.load(PROJECT_ROOT / "classes.pkl")
    best_features = np.load(PROJECT_ROOT / "best_features.npy")
    svm_model = joblib.load(PROJECT_ROOT / "svm_model.pkl")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    backbone = models.resnet50(weights=None)
    backbone.fc = nn.Linear(backbone.fc.in_features, len(classes))
    backbone.load_state_dict(
        torch.load(PROJECT_ROOT / "fine_tuned_resnet.pth", map_location=device)
    )
    backbone = torch.nn.Sequential(*(list(backbone.children())[:-1]))
    backbone.eval().to(device)

    transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ]
    )
    return torch, scaler, classes, best_features, svm_model, backbone, transform, device


def _predict_image(image_data: bytes) -> PredictionResponse:
    import numpy as np

    torch, scaler, classes, best_features, svm_model, backbone, transform, device = (
        _load_prediction_pipeline()
    )

    with Image.open(io.BytesIO(image_data)) as source_image:
        image = source_image.convert("RGB")

    width, height = image.size
    max_dimension = max(width, height)
    padded_image = Image.new("RGB", (max_dimension, max_dimension), (0, 0, 0))
    padded_image.paste(
        image,
        ((max_dimension - width) // 2, (max_dimension - height) // 2),
    )
    image_tensor = transform(padded_image).unsqueeze(0).to(device)

    with torch.no_grad():
        features = backbone(image_tensor).view(1, -1).cpu().numpy()

    features_scaled = scaler.transform(features)
    features_optimized = features_scaled[:, best_features]
    probabilities = svm_model.predict_proba(features_optimized)[0]
    pred_idx = svm_model.predict(features_optimized)[0]

    disease_name = str(classes[pred_idx])
    clean_name = disease_name.replace("Rice__", "").replace("_", " ")
    display_name = re.sub(r"([a-z])([A-Z])", r"\g<1> \g<2>", clean_name)
    confidence = float(np.max(probabilities) * 100)
    return PredictionResponse(disease=display_name, confidence=round(confidence, 2))


def create_app(
    predictor: Callable[[bytes], PredictionResponse] = _predict_image,
) -> FastAPI:
    application = FastAPI(title="Smart Agriculture Vision API")
    application.state.predictor = predictor

    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.exception_handler(APIError)
    async def handle_api_error(_, error: APIError) -> JSONResponse:
        return JSONResponse(
            status_code=error.status_code,
            content={"error": {"code": error.code, "message": error.message}},
        )

    @application.post("/predict", response_model=PredictionResponse)
    async def predict_disease(file: UploadFile = File(...)) -> PredictionResponse:
        image_data = await file.read(MAX_IMAGE_BYTES + 1)
        _validate_image(image_data)

        try:
            prediction = application.state.predictor(image_data)
            return PredictionResponse.model_validate(prediction)
        except Exception:
            logger.exception("Image prediction failed")
            raise APIError(
                "prediction_failed",
                "The image could not be analyzed. Please try again later.",
                500,
            ) from None

    return application


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
