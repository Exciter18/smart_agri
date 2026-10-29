"""Evidence-backed advisory agent for the rice vision model.

The agent does not attempt to replace the image classifier.  It accepts a
canonical class id from the classifier, remembers non-visual context supplied
by the grower, and answers from the curated knowledge base in ``data``.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import threading
import unicodedata
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .local_llm import LLMGeneration, OllamaLocalLLM
from .openai_llm import OpenAIResponsesLLM
from app.knowledge import PostgreSQLSessionStore, PostgresKnowledgeRetriever


MODEL_CLASS_IDS = (
    "Rice__BacterialLeafBlight",
    "Rice__BrownSpot",
    "Rice__Healthy",
    "Rice__Hispa",
    "Rice__LeafBlast",
    "Rice__LeafScald",
    "Rice__LeafSmut",
    "Rice__NarrowBrownLeafSpot",
    "Rice__NeckBlast",
)

MODEL_CLASS_ENGLISH_NAMES = {
    "Rice__BacterialLeafBlight": "Bacterial leaf blight",
    "Rice__BrownSpot": "Brown spot",
    "Rice__Healthy": "Healthy rice",
    "Rice__Hispa": "Rice hispa",
    "Rice__LeafBlast": "Rice blast (leaf blast)",
    "Rice__LeafScald": "Leaf scald",
    "Rice__LeafSmut": "Leaf smut",
    "Rice__NarrowBrownLeafSpot": "Narrow brown leaf spot",
    "Rice__NeckBlast": "Neck blast",
}

QUESTION_TEXT = {
    "age_days": "About how many days ago was the rice seeded or transplanted?",
    "growth_stage": (
        "What is the rice growth stage: seedling, tillering, panicle initiation, "
        "heading, or ripening?"
    ),
    "symptom_duration": "How long ago did you first notice these symptoms?",
    "recent_weather": (
        "Has there been prolonged rain, heavy dew, or high humidity in the last few days?"
    ),
    "water_condition": (
        "Is the root zone currently dry, adequately moist, or waterlogged for a long time?"
    ),
    "nitrogen_use": "Has the crop recently received urea or another nitrogen-heavy fertilizer?",
    "previous_action": "Have you applied fertilizer, sprayed anything, or tried another treatment?",
}

_INITIAL_CONTEXT_FIELDS = {
    "rice_variety",
    "age_days",
    "growth_stage",
    "recent_weather",
    "water_condition",
    "nitrogen_use",
    "previous_action",
}
_INITIAL_CONTEXT_CHOICES = {
    "growth_stage": {
        "seedling": "mạ",
        "tillering": "đẻ nhánh",
        "panicle_initiation": "làm đòng",
        "heading": "trổ",
        "ripening": "chín",
    },
    "recent_weather": {
        "rainy_humid": "mưa nhiều, độ ẩm cao",
        "normal": "thời tiết bình thường",
        "dry_hot": "khô nóng",
    },
    "water_condition": {
        "waterlogged": "ngập/ứ nước",
        "adequate": "đủ ẩm",
        "dry": "khô",
    },
    "nitrogen_use": {
        "recent_heavy": "bón nhiều đạm gần đây",
        "balanced": "bón phân theo kế hoạch",
        "none_recent": "chưa bón phân gần đây",
    },
}
_ENGLISH_CONTEXT_VALUES = {
    "growth_stage": {
        "mạ": "seedling",
        "đẻ nhánh": "tillering",
        "làm đòng": "panicle initiation",
        "trổ": "heading",
        "chín": "ripening",
    },
    "recent_weather": {
        "mưa nhiều, độ ẩm cao": "rainy or humid",
        "thời tiết bình thường": "mostly normal",
        "khô nóng": "dry or hot",
    },
    "water_condition": {
        "ngập/ứ nước": "waterlogged",
        "đủ ẩm": "adequately moist",
        "khô": "dry",
    },
    "nitrogen_use": {
        "bón nhiều đạm gần đây": "recently applied heavy nitrogen",
        "bón phân theo kế hoạch": "fertilized as planned",
        "chưa bón phân gần đây": "no recent fertilizer",
    },
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _plain_text(value: str) -> str:
    normalized = unicodedata.normalize("NFD", value.lower())
    without_marks = "".join(
        char for char in normalized if unicodedata.category(char) != "Mn"
    )
    return without_marks.replace("đ", "d")


def _as_score(value: Any) -> float | None:
    if value is None:
        return None
    try:
        score = float(value)
    except (TypeError, ValueError):
        return None
    if score > 1:
        score /= 100
    return max(0.0, min(1.0, score))


class SessionStore:
    """Small SQLite store so a diagnostic conversation survives app restarts."""

    def __init__(self, database_path: str | Path) -> None:
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    @contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS diagnostic_sessions (
                    session_id TEXT PRIMARY KEY,
                    state_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )

    def create(self, state: dict[str, Any]) -> str:
        session_id = str(uuid.uuid4())
        timestamp = _now_iso()
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO diagnostic_sessions
                    (session_id, state_json, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (session_id, json.dumps(state, ensure_ascii=False), timestamp, timestamp),
            )
        return session_id

    def get(self, session_id: str) -> dict[str, Any] | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT state_json FROM diagnostic_sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
        return json.loads(row["state_json"]) if row else None

    def save(self, session_id: str, state: dict[str, Any]) -> bool:
        with self._lock, self._connection() as connection:
            cursor = connection.execute(
                """
                UPDATE diagnostic_sessions
                SET state_json = ?, updated_at = ?
                WHERE session_id = ?
                """,
                (json.dumps(state, ensure_ascii=False), _now_iso(), session_id),
            )
        return cursor.rowcount > 0

    def delete(self, session_id: str) -> bool:
        with self._lock, self._connection() as connection:
            cursor = connection.execute(
                "DELETE FROM diagnostic_sessions WHERE session_id = ?",
                (session_id,),
            )
        return cursor.rowcount > 0


class RiceDiseaseAgent:
    """RAG agent whose responses are generated by a local language model."""

    def __init__(
        self,
        knowledge_path: str | Path | None = None,
        session_store: Any | None = None,
        llm: Any | None = None,
        retriever: Any | None = None,
    ) -> None:
        base_dir = Path(__file__).resolve().parent
        self.knowledge_path = Path(
            knowledge_path or base_dir / "data" / "rice_knowledge.json"
        )
        with self.knowledge_path.open("r", encoding="utf-8") as handle:
            self.knowledge = json.load(handle)
        self.classes: dict[str, dict[str, Any]] = self.knowledge["classes"]
        if set(self.classes) != set(MODEL_CLASS_IDS):
            missing = sorted(set(MODEL_CLASS_IDS) - set(self.classes))
            extra = sorted(set(self.classes) - set(MODEL_CLASS_IDS))
            raise ValueError(
                f"Knowledge/model class mismatch; missing={missing}, extra={extra}"
            )
        default_db = base_dir.parents[1] / "data" / "agent" / "diagnostic_sessions.sqlite3"
        self._storage_error: str | None = None
        self._retrieval_error: str | None = None
        if session_store is not None:
            self.store = session_store
        else:
            database_url = os.getenv("DATABASE_URL", "").strip()
            if database_url:
                try:
                    self.store = PostgreSQLSessionStore(database_url)
                except Exception as exc:
                    self._storage_error = str(exc)
                    self.store = SessionStore(default_db)
            else:
                self.store = SessionStore(default_db)
        self.retriever = (
            retriever
            if retriever is not None
            else PostgresKnowledgeRetriever.from_environment()
        )
        if llm is not None:
            self.llm = llm
        else:
            provider = os.getenv("LLM_PROVIDER", "openai").strip().lower()
            if provider == "ollama":
                self.llm = OllamaLocalLLM()
            elif provider == "openai":
                self.llm = OpenAIResponsesLLM()
            else:
                raise ValueError(
                    "LLM_PROVIDER chỉ hỗ trợ 'openai' hoặc 'ollama'"
                )

    def status(self) -> dict[str, Any]:
        llm_status = self.llm.status()
        if self.retriever is None:
            retrieval_status = {
                "ready": False,
                "backend": "json_fallback",
                "error": "Chưa cấu hình DATABASE_URL; đang dùng knowledge JSON",
            }
        else:
            retrieval_status = self.retriever.status()
            if self._retrieval_error:
                retrieval_status = {**retrieval_status, "last_error": self._retrieval_error}
        return {
            "ready": bool(llm_status.get("ready")),
            "mode": (
                "external_llm_rag"
                if llm_status.get("external_api")
                else "local_llm_rag"
            ),
            "knowledge_ready": True,
            "knowledge_classes": len(self.classes),
            "knowledge_backend": (
                "postgresql_pgvector" if self.retriever is not None else "json_fallback"
            ),
            "retrieval": retrieval_status,
            "session_storage": {
                "backend": getattr(self.store, "backend_name", "sqlite"),
                "fallback_error": self._storage_error,
            },
            "llm": llm_status,
        }

    def start_diagnosis(
        self,
        class_id: str,
        confidence: float | None = None,
        top_predictions: list[dict[str, Any]] | None = None,
        model_version: str | None = None,
        image_quality: dict[str, Any] | None = None,
        initial_context: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if class_id not in self.classes:
            raise ValueError(f"Unsupported model class: {class_id}")

        normalized_predictions = self._normalize_predictions(top_predictions or [])
        score = _as_score(confidence)
        if score is None and normalized_predictions:
            score = normalized_predictions[0]["confidence_score"]
        assessment = self._assessment(score, normalized_predictions)
        record = self.classes[class_id]
        required = list(record.get("required_context", []))
        context = self._normalize_initial_context(
            initial_context if initial_context is not None else {}
        )
        self._infer_growth_stage(context)
        state = {
            "class_id": class_id,
            "confidence_score": score,
            "top_predictions": normalized_predictions,
            "assessment": assessment,
            "model_version": model_version,
            "image_quality": image_quality or {},
            "context": context,
            "required_context": required,
            "pending_field": None,
            "history": [],
            "last_generation": None,
        }
        state["pending_field"] = self._next_missing_field(state)
        session_id = self.store.create(state)
        generation = self._generate_with_rag(
            state=state,
            user_message=(
                "Explain the image classification and give a safe immediate action. "
                "Ask the single suggested follow-up only if RAG_CONTEXT marks a missing "
                "context field; otherwise, do not ask for more information."
            ),
            intent="initial",
        )
        message = generation.text
        state["last_generation"] = generation.to_dict()
        state["history"].append({"role": "assistant", "message": message})
        self.store.save(session_id, state)
        return self._response(session_id, state, message)

    @staticmethod
    def _normalize_initial_context(value: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(value, dict):
            raise ValueError("Farm context must be a JSON object")
        unknown = set(value) - _INITIAL_CONTEXT_FIELDS
        if unknown:
            raise ValueError(f"Unsupported farm context fields: {', '.join(sorted(unknown))}")

        context: dict[str, Any] = {}
        if "rice_variety" in value:
            variety = value["rice_variety"]
            if not isinstance(variety, str) or len(variety.strip()) > 80:
                raise ValueError("Rice variety must be text of at most 80 characters")
            if variety.strip():
                context["rice_variety"] = variety.strip()

        if "age_days" in value:
            age = value["age_days"]
            if isinstance(age, bool) or not isinstance(age, int) or not 1 <= age <= 250:
                raise ValueError("Crop age must be a whole number from 1 to 250")
            context["age_days"] = age

        for field, choices in _INITIAL_CONTEXT_CHOICES.items():
            if field not in value:
                continue
            choice = value[field]
            if not isinstance(choice, str) or choice not in choices:
                raise ValueError(f"Unsupported value for farm context field: {field}")
            context[field] = choices[choice]

        if "previous_action" in value:
            action = value["previous_action"]
            if not isinstance(action, str) or len(action.strip()) > 240:
                raise ValueError(
                    "Previous actions must be text of at most 240 characters"
                )
            if action.strip():
                context["previous_action"] = action.strip()
        return context

    @staticmethod
    def validate_initial_context(value: dict[str, Any]) -> None:
        RiceDiseaseAgent._normalize_initial_context(value)

    def chat(self, session_id: str, message: str) -> dict[str, Any]:
        state = self.store.get(session_id)
        if state is None:
            raise KeyError("Diagnostic session not found")
        cleaned = message.strip()
        if not cleaned:
            raise ValueError("Message must not be empty")

        state["history"].append({"role": "user", "message": cleaned})
        extracted = self._extract_context(cleaned)
        pending = state.get("pending_field")
        if pending and pending not in extracted and self._looks_like_context_answer(cleaned):
            extracted[pending] = cleaned
        if "growth_stage" in extracted:
            state["context"].pop("growth_stage_source", None)
        state["context"].update(extracted)
        self._infer_growth_stage(state["context"])

        intent = self._detect_intent(cleaned)
        next_field = self._next_missing_field(state)
        state["pending_field"] = next_field
        generation = self._generate_with_rag(
            state=state,
            user_message=cleaned,
            intent=intent,
        )
        answer = generation.text
        state["last_generation"] = generation.to_dict()
        context_note = self._context_note(state)
        if context_note:
            answer = f"{answer}\n\n{context_note}"
        if intent == "pesticide":
            answer = (
                f"{answer}\n\nFor safety, do not choose or mix a pesticide based on "
                "a photo alone. Follow locally approved product labels and consult "
                "an agricultural specialist. Official lookup: "
                f"{self.knowledge['national_pesticide_lookup']}"
            )

        state["history"].append({"role": "assistant", "message": answer})
        self.store.save(session_id, state)
        return self._response(session_id, state, answer)

    def get_session(self, session_id: str) -> dict[str, Any]:
        state = self.store.get(session_id)
        if state is None:
            raise KeyError("Diagnostic session not found")
        return self._response(session_id, state, None)

    def reset(self, session_id: str) -> bool:
        return self.store.delete(session_id)

    @staticmethod
    def _normalize_predictions(
        predictions: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        normalized: list[dict[str, Any]] = []
        for prediction in predictions:
            class_id = prediction.get("class_id") or prediction.get("label")
            score = _as_score(
                prediction.get("confidence_score", prediction.get("confidence"))
            )
            if class_id and score is not None:
                normalized.append(
                    {"class_id": str(class_id), "confidence_score": score}
                )
        return sorted(normalized, key=lambda item: item["confidence_score"], reverse=True)

    @staticmethod
    def _assessment(
        score: float | None, predictions: list[dict[str, Any]]
    ) -> str:
        if score is None:
            return "unknown"
        close_runner_up = (
            len(predictions) > 1
            and predictions[0]["confidence_score"]
            - predictions[1]["confidence_score"]
            < 0.12
        )
        if score >= 0.80 and not close_runner_up:
            return "high_confidence"
        if score >= 0.55 and not close_runner_up:
            return "needs_context"
        return "uncertain"

    def _initial_message(
        self, record: dict[str, Any], state: dict[str, Any]
    ) -> str:
        score = state.get("confidence_score")
        confidence_text = (
            f" ({score * 100:.1f}% model confidence)" if score is not None else ""
        )
        display_name = record["display_name"]
        if state["class_id"] == "Rice__Healthy":
            lead = f"The model found no clear disease signs and classified the image as **{display_name}**{confidence_text}."
        elif state["assessment"] == "uncertain":
            lead = (
                f"The model leans toward **{display_name}**{confidence_text}, but the "
                "result is not certain enough to treat as a final diagnosis."
            )
        else:
            lead = f"The model classified the image as **{display_name}**{confidence_text}."

        quality = state.get("image_quality", {})
        quality_note = ""
        if quality and not quality.get("acceptable", True):
            quality_note = (
                " The image may not be clear enough; retake a focused, well-lit close-up "
                "of the leaf or panicle."
            )
        alternative = self._alternative_note(state)
        first_action = record.get("management", [record["overview"]])[0]
        pending = state.get("pending_field")
        question = f"\n\n{QUESTION_TEXT[pending]}" if pending else ""
        return (
            f"{lead}{quality_note}{alternative}\n\n{record['overview']}\n\n"
            f"Recommended immediate action: {first_action}{question}"
        )

    def _alternative_note(self, state: dict[str, Any]) -> str:
        predictions = state.get("top_predictions", [])
        if state.get("assessment") != "uncertain" or len(predictions) < 2:
            return ""
        runner_up = predictions[1]
        record = self.classes.get(runner_up["class_id"])
        if not record:
            return ""
        return (
            f" The closest alternative is **{record['display_name']}** "
            f"({runner_up['confidence_score'] * 100:.1f}%)."
        )

    @staticmethod
    def _looks_like_context_answer(message: str) -> bool:
        plain = _plain_text(message)
        question_words = ("tai sao", "la gi", "the nao", "bao nhieu", "co nen", "cach")
        return not any(word in plain for word in question_words) and len(message) <= 240

    def _extract_context(self, message: str) -> dict[str, Any]:
        plain = _plain_text(message)
        result: dict[str, Any] = {}

        age_patterns = (
            r"(?:cay|lua|gieo|sa|cay duoc)\D{0,18}(\d{1,3})\s*ngay",
            r"(\d{1,3})\s*ngay\s*(?:tuoi|sau gieo|sau sa|sau cay)",
        )
        for pattern in age_patterns:
            match = re.search(pattern, plain)
            if match and 1 <= int(match.group(1)) <= 250:
                result["age_days"] = int(match.group(1))
                break

        duration_match = re.search(
            r"(?:benh|vet|dau hieu|xuat hien)\D{0,18}(\d{1,3})\s*ngay", plain
        )
        if duration_match:
            result["symptom_duration"] = f"{duration_match.group(1)} ngày"

        stages = {
            "ma": "mạ",
            "de nhanh": "đẻ nhánh",
            "lam dong": "làm đòng",
            "dong tro": "đòng-trổ",
            "tro bong": "trổ",
            "tro": "trổ",
            "chin": "chín",
        }
        for keyword, value in stages.items():
            if keyword in plain:
                result["growth_stage"] = value
                break

        weather_words = ("mua", "am cao", "suong", "kho han", "nang gat", "gio manh")
        if any(word in plain for word in weather_words):
            result["recent_weather"] = message

        water_words = ("ngap", "u nuoc", "dong nuoc", "kho", "nut dat", "du am", "am vua")
        if any(word in plain for word in water_words):
            result["water_condition"] = message

        nitrogen_words = ("ure", "phan dam", "bon dam", "npk", "bon phan")
        if any(word in plain for word in nitrogen_words):
            result["nitrogen_use"] = message

        action_words = ("da phun", "vua phun", "da xu ly", "cat bo", "thuoc", "che pham")
        if any(word in plain for word in action_words):
            result["previous_action"] = message
        return result

    @staticmethod
    def _infer_growth_stage(context: dict[str, Any]) -> None:
        if "growth_stage" in context or not isinstance(context.get("age_days"), int):
            return
        age = context["age_days"]
        if age <= 20:
            stage = "mạ"
        elif age <= 55:
            stage = "đẻ nhánh"
        elif age <= 75:
            stage = "làm đòng"
        elif age <= 95:
            stage = "trổ hoặc chắc hạt"
        else:
            stage = "chín"
        context["growth_stage"] = stage
        context["growth_stage_source"] = "estimated_from_age"

    def _context_note(self, state: dict[str, Any]) -> str:
        context = state.get("context", {})
        notes: list[str] = []
        if context.get("growth_stage_source") == "estimated_from_age":
            stage = _ENGLISH_CONTEXT_VALUES["growth_stage"].get(
                context["growth_stage"], context["growth_stage"]
            )
            notes.append(
                f"Based on the crop age of {context['age_days']} days, the growth stage "
                f"is estimated as **{stage}**. This can vary by variety "
                "and planting method; share the actual stage if you know it."
            )
        if state.get("class_id") == "Rice__NeckBlast":
            stage = _plain_text(str(context.get("growth_stage", "")))
            if stage and any(value in stage for value in ("ma", "de nhanh")):
                notes.append(
                    "Note: neck blast is not consistent with the seedling/tillering stage. "
                    "Treat this result cautiously and recheck the image and disease label."
                )
        return "\n".join(notes)

    def _generate_with_rag(
        self,
        *,
        state: dict[str, Any],
        user_message: str,
        intent: str,
    ) -> LLMGeneration:
        """Retrieve trusted facts and ask the local LLM to compose the answer."""

        record = self.classes[state["class_id"]]
        intent_fields = {
            "initial": [
                "cause",
                "overview",
                "management",
            ],
            "overview": ["cause", "overview", "management"],
            "cause": ["cause", "favorable_conditions"],
            "symptoms": ["symptoms", "lookalikes"],
            "treatment": ["management", "watering", "fertilizer"],
            "watering": ["watering", "favorable_conditions"],
            "fertilizer": ["fertilizer", "favorable_conditions"],
            "prevention": ["prevention", "management"],
            "spread": ["cause", "favorable_conditions", "prevention"],
            "pesticide": ["cause", "management"],
            "sources": [
                "cause",
                "overview",
                "management",
                "watering",
                "fertilizer",
                "prevention",
            ],
        }
        selected_fields = intent_fields.get(intent, intent_fields["overview"])
        evidence: dict[str, Any] = {}
        for field in selected_fields:
            value = record.get(field)
            if value in (None, [], ""):
                continue
            if isinstance(value, list):
                value = value[:2] if intent == "initial" else value[:4]
            evidence[field] = value

        alternatives: list[dict[str, Any]] = []
        if state.get("assessment") == "uncertain":
            for prediction in state.get("top_predictions", [])[1:3]:
                alternative = self.classes.get(prediction.get("class_id"))
                if alternative:
                    alternatives.append(
                        {
                            "display_name": MODEL_CLASS_ENGLISH_NAMES[
                                prediction["class_id"]
                            ],
                            "confidence_score": prediction.get("confidence_score"),
                            "overview": alternative.get("overview"),
                            "symptoms": alternative.get("symptoms", [])[:2],
                        }
                    )

        semantic_evidence: list[dict[str, Any]] = []
        if self.retriever is not None:
            context_text = json.dumps(
                state.get("context", {}), ensure_ascii=False, separators=(",", ":")
            )
            retrieval_query = (
                f"Cây lúa; {record['display_name']}; ý định {intent}; "
                f"bối cảnh {context_text}; câu hỏi {user_message}"
            )
            try:
                retrieved = self.retriever.retrieve(
                    retrieval_query,
                    class_id=state["class_id"],
                    top_k=6,
                )
                for item in retrieved:
                    semantic_evidence.append(
                        {
                            "topic": item.get("topic"),
                            "content": item.get("content"),
                            "source_title": item.get("title"),
                            "source_url": item.get("source_url"),
                            "relevance_score": round(
                                float(item.get("combined_score") or 0.0), 4
                            ),
                        }
                    )
                self._retrieval_error = None
            except Exception as exc:
                # The curated JSON remains usable if PostgreSQL or embeddings
                # are temporarily unavailable.
                self._retrieval_error = str(exc)

        pending = state.get("pending_field")
        source_titles = [item["title"] for item in record.get("sources", [])]
        source_titles.extend(
            item["source_title"]
            for item in semantic_evidence
            if item.get("source_title") and item["source_title"] not in source_titles
        )
        rag_payload = {
            "scope": "Advice for one rice sample only; do not infer whole-field rates or yield.",
            "vision_result": {
                "disease_name": MODEL_CLASS_ENGLISH_NAMES[state["class_id"]],
                "confidence_score": state.get("confidence_score"),
                "confidence_meaning": (
                    "Classification confidence, not disease severity or infection rate."
                ),
                "assessment": state.get("assessment"),
            },
            "retrieved_evidence": evidence,
            "semantic_evidence": semantic_evidence,
            "possible_alternatives": alternatives,
            "user_context": self._english_context(state.get("context", {})),
            "missing_context": pending,
            "suggested_follow_up": QUESTION_TEXT.get(pending),
            "source_titles": source_titles,
        }
        if intent == "sources":
            source_links = list(record.get("sources", []))
            for item in semantic_evidence:
                if not item.get("source_url"):
                    continue
                candidate = {
                    "title": item.get("source_title") or "Tài liệu tham khảo",
                    "url": item["source_url"],
                }
                if candidate not in source_links:
                    source_links.append(candidate)
            rag_payload["source_links"] = source_links
        system_prompt = (
            "You are an evidence-based rice crop advisory assistant for one image "
            "classification. Always answer in clear, natural English, even if the "
            "question or retrieved evidence is in another language. Use only relevant "
            "facts from RAG_CONTEXT; do not invent pesticides, doses, water quantities, "
            "field-wide infection rates, or yield estimates. Distinguish model confidence "
            "from disease severity, and never present an image classification as a "
            "confirmed diagnosis. Use the grower's provided context. State uncertainty "
            "or a growth-stage contradiction when relevant. If essential context is "
            "missing_context is not null, finish with only the single "
            "suggested_follow_up question, phrased "
            "directly to the grower; never expose internal instructions. Answer a specific "
            "question directly. Do not claim to see visual details beyond the classifier's "
            "result. On follow-up turns, do not repeat the disease label, confidence, or "
            "initial diagnosis introduction unless the grower explicitly asks about it; "
            "answer the new question without restating the previous reply. If "
            "missing_context is null, do not ask any question or request information that "
            "is already present in user_context."
        )
        user_prompt = (
            "RAG_CONTEXT (trusted evidence in JSON; translate relevant facts into English):\n"
            f"{json.dumps(rag_payload, ensure_ascii=False, separators=(',', ':'))}\n\n"
            f"NEW QUESTION OR INFORMATION FROM THE GROWER:\n{user_message}\n\n"
            "Reply in English, using at most 120 words. Explain briefly when useful, "
            "prioritize safe actions, and do not repeat the input or previous answer."
        )
        history = state.get("history", [])
        if history and history[-1].get("role") == "user":
            history = history[:-1]
        generation = self.llm.generate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            history=history,
        )
        generation.text = self._sanitize_llm_text(generation.text)
        generation.text = self._remove_repeated_diagnosis_intro(
            generation.text,
            history,
            MODEL_CLASS_ENGLISH_NAMES[state["class_id"]],
        )
        generation.text = self._ensure_direct_follow_up(generation.text, pending)
        return generation

    @staticmethod
    def _english_context(context: dict[str, Any]) -> dict[str, Any]:
        translated = dict(context)
        for field, values in _ENGLISH_CONTEXT_VALUES.items():
            value = translated.get(field)
            if isinstance(value, str):
                translated[field] = values.get(value, value)
        return translated

    @staticmethod
    def _sanitize_llm_text(text: str) -> str:
        cleaned = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
        cleaned = cleaned.replace("<think>", "").replace("</think>", "").strip()
        if not cleaned:
            raise RuntimeError("Model chỉ trả về chuỗi suy nghĩ, không có câu trả lời")
        return cleaned

    @staticmethod
    def _ensure_direct_follow_up(text: str, pending: str | None) -> str:
        """Turn model planning notes into an actual question for the user."""
        question = QUESTION_TEXT.get(pending)
        if not question:
            sentences = re.split(r"(?<=[.!?])\s+", text.strip())
            kept = [
                sentence
                for sentence in sentences
                if not sentence.rstrip().endswith("?")
            ]
            cleaned = " ".join(kept).strip()
            return cleaned or "I can provide guidance based on the information available."

        kept_sentences: list[str] = []
        for sentence in re.split(r"(?<=[.!?])\s+", text.strip()):
            plain = _plain_text(sentence)
            is_meta_instruction = bool(
                re.search(r"\b(?:should|need to|must)\s+ask\b", plain)
                or "ask the grower" in plain
                or "ask the user" in plain
                or re.search(r"\b(?:nen|can|hay)\s+hoi\b", plain)
                or "hoi nguoi dung" in plain
            )
            if not is_meta_instruction:
                kept_sentences.append(sentence)

        cleaned = " ".join(kept_sentences).strip()
        if _plain_text(question) in _plain_text(cleaned):
            return cleaned
        return f"{cleaned}\n\n{question}" if cleaned else question

    @staticmethod
    def _remove_repeated_diagnosis_intro(
        text: str,
        history: list[dict[str, Any]],
        disease_name: str,
    ) -> str:
        if not any(item.get("role") == "assistant" for item in history):
            return text

        identification = re.compile(
            r"\b(?:the\s+)?(?:vision\s+)?model\s+"
            r"(?:has\s+)?(?:identified|recognised|recognized|classified|detected|"
            r"predicts?|is\s+leaning\s+toward|leans\s+toward|"
            r"nghieng\s+ve|nhan\s+dien|phan\s+loai|xep\s+anh)\b",
            re.IGNORECASE,
        )
        sentences = re.split(r"(?<=[.!?])\s+", text.strip())
        kept = [sentence for sentence in sentences if not identification.search(sentence)]
        if kept:
            repeated_label_lead = re.compile(
                rf"^\s*(?:during|for|regarding|about|as\s+for)\s+"
                rf"(?:the\s+)?{re.escape(disease_name)}"
                rf"(?:\s+disease)?(?:\s+stage)?\s*[,;:]\s*",
                re.IGNORECASE,
            )
            kept[0] = repeated_label_lead.sub("", kept[0], count=1)
            if not kept[0].strip():
                kept.pop(0)
        cleaned = " ".join(kept).strip()
        return cleaned or text

    @staticmethod
    def _detect_intent(message: str) -> str:
        plain = _plain_text(message)
        intent_keywords = (
            (
                "pesticide",
                ("thuoc", "phun gi", "lieu luong", "hoat chat", "pesticide", "spray", "dose"),
            ),
            ("sources", ("nguon", "tai lieu", "tham khao", "bang chung", "source", "reference", "evidence")),
            (
                "watering",
                ("tuoi", "nuoc", "ngap", "kho han", "do am", "water", "irrigat", "flood"),
            ),
            ("fertilizer", ("phan", "ure", "dam", "npk", "bon", "fertilizer", "fertiliser", "nitrogen")),
            ("prevention", ("phong", "ngua", "tai phat", "prevent", "prevention", "recurrence")),
            ("cause", ("nguyen nhan", "tai sao", "do dau", "tac nhan", "cause", "why")),
            ("symptoms", ("trieu chung", "dau hieu", "bieu hien", "symptom", "sign")),
            ("spread", ("lay", "lan", "truyen", "spread", "transmit")),
            (
                "treatment",
                ("xu ly", "khac phuc", "lam gi", "chua", "dieu tri", "treat", "treatment", "control"),
            ),
        )
        for intent, keywords in intent_keywords:
            if any(keyword in plain for keyword in keywords):
                return intent
        return "overview"

    def _answer_for_intent(
        self, intent: str, record: dict[str, Any], state: dict[str, Any]
    ) -> str:
        if intent == "cause":
            return record["cause"]
        if intent == "symptoms":
            return self._format_list("Dấu hiệu tham khảo", record.get("symptoms", []))
        if intent == "treatment":
            return self._format_list("Hướng xử lý an toàn", record.get("management", []))
        if intent == "watering":
            return self._contextual_watering(record, state)
        if intent == "fertilizer":
            return self._format_list("Khuyến nghị về phân bón", record.get("fertilizer", []))
        if intent == "prevention":
            return self._format_list("Cách phòng ngừa", record.get("prevention", []))
        if intent == "spread":
            conditions = self._format_list(
                "Điều kiện làm vấn đề phát triển", record.get("favorable_conditions", [])
            )
            return f"{record['cause']}\n\n{conditions}"
        if intent == "pesticide":
            return (
                f"{self.knowledge['pesticide_notice']} Mình không đưa tên thuốc hoặc "
                "liều pha chỉ từ một ảnh. Bạn có thể tra danh mục hiện hành tại: "
                f"{self.knowledge['national_pesticide_lookup']}"
            )
        if intent == "sources":
            lines = [f"- {source['title']}: {source['url']}" for source in record["sources"]]
            return "Nguồn kiến thức đang dùng:\n" + "\n".join(lines)
        return (
            f"**{record['display_name']}**: {record['overview']}\n\n"
            + self._format_list("Việc nên làm", record.get("management", [])[:3])
        )

    def _contextual_watering(
        self, record: dict[str, Any], state: dict[str, Any]
    ) -> str:
        base = self._format_list("Khuyến nghị về nước", record.get("watering", []))
        context = state.get("context", {})
        water = _plain_text(str(context.get("water_condition", "")))
        weather = _plain_text(str(context.get("recent_weather", "")))
        notes: list[str] = []
        if "ngap" in water or "u nuoc" in water:
            notes.append(
                "Bạn cho biết vùng rễ đang ngập/ứ: ưu tiên kiểm tra thoát nước, "
                "không tự tăng thêm nước."
            )
        if "kho" in water or "nut" in water:
            notes.append(
                "Bạn cho biết vùng rễ đang khô: bổ sung nước từ từ để giảm stress, "
                "không suy ra số lít cụ thể khi chưa biết chậu/diện tích và loại đất."
            )
        if "mua" in weather or "am cao" in weather:
            notes.append(
                "Do gần đây có mưa/ẩm cao, tránh làm lá ướt thêm và theo dõi thoát nước."
            )
        return base + ("\n\nTheo thông tin bạn cung cấp:\n- " + "\n- ".join(notes) if notes else "")

    @staticmethod
    def _format_list(title: str, items: list[str]) -> str:
        if not items:
            return f"{title}: chưa có dữ liệu phù hợp."
        return f"{title}:\n" + "\n".join(f"- {item}" for item in items)

    @staticmethod
    def _next_missing_field(state: dict[str, Any]) -> str | None:
        context = state.get("context", {})
        for field in state.get("required_context", []):
            if field not in context:
                return field
        return None

    def _response(
        self, session_id: str, state: dict[str, Any], message: str | None
    ) -> dict[str, Any]:
        record = self.classes[state["class_id"]]
        pending = state.get("pending_field")
        return {
            "session_id": session_id,
            "message": message,
            "assessment": state.get("assessment"),
            "class_id": state["class_id"],
            "display_name": record["display_name"],
            "confidence_score": state.get("confidence_score"),
            "context": state.get("context", {}),
            "pending_field": pending,
            "next_question": QUESTION_TEXT.get(pending),
            "model_version": state.get("model_version"),
            "image_quality": state.get("image_quality", {}),
            "sources": record.get("sources", []),
            "history": state.get("history", []),
            "scope_notice": self.knowledge["scope_notice"],
            "generation": state.get("last_generation"),
        }
