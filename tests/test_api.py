import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from PIL import Image

from app.agent import LLMGeneration, RiceDiseaseAgent, SessionStore
import app.api.api_server as api_server


class FakeLocalLLM:
    def status(self):
        return {
            "ready": True,
            "provider": "fake_local",
            "model": "fake-qwen",
            "external_api": False,
        }

    def generate(self, *, system_prompt, user_prompt, history=None):
        return LLMGeneration(
            text="Phản hồi từ model ngôn ngữ local.", model="fake-qwen"
        )


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.TemporaryDirectory()
        api_server.rice_agent = RiceDiseaseAgent(
            session_store=SessionStore(
                Path(cls.temp_dir.name) / "api_sessions.sqlite3"
            ),
            llm=FakeLocalLLM(),
        )
        cls.client = TestClient(api_server.app)

    @classmethod
    def tearDownClass(cls):
        cls.temp_dir.cleanup()

    def test_health_keeps_agent_available_without_vision_artifacts(self):
        response = self.client.get("/health")
        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertTrue(payload["agent_ready"])
        self.assertIn("vision_ready", payload)
        self.assertEqual("local_llm_rag", payload["agent"]["mode"])

    def test_root_serves_the_vietnamese_demo_interface(self):
        response = self.client.get("/")
        self.assertEqual(200, response.status_code)
        self.assertIn("Trợ lý sức khỏe cây lúa", response.text)
        self.assertIn("/agent/start", response.text)

    def test_old_docs_url_redirects_to_vietnamese_interface(self):
        response = self.client.get("/docs", follow_redirects=False)
        self.assertEqual(307, response.status_code)
        self.assertEqual("/", response.headers["location"])
        technical_docs = self.client.get("/api-docs")
        self.assertEqual(200, technical_docs.status_code)

    def test_agent_start_chat_and_reset_contract(self):
        started = self.client.post(
            "/agent/start",
            json={"class_id": "Rice__LeafScald", "confidence_score": 0.78},
        )
        self.assertEqual(200, started.status_code)
        self.assertEqual("local_llm", started.json()["generation"]["mode"])
        session_id = started.json()["session_id"]
        chatted = self.client.post(
            "/agent/chat",
            json={"session_id": session_id, "message": "Cây lúa được 50 ngày"},
        )
        self.assertEqual(200, chatted.status_code)
        self.assertEqual(50, chatted.json()["context"]["age_days"])
        deleted = self.client.post("/agent/reset", json={"session_id": session_id})
        self.assertEqual(200, deleted.status_code)

    def test_predict_reports_missing_artifacts_as_service_unavailable(self):
        image = Image.new("RGB", (300, 300), "green")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG")
        response = self.client.post(
            "/predict",
            files={"file": ("rice.jpg", buffer.getvalue(), "image/jpeg")},
        )
        if response.status_code == 503:
            self.assertIn("Thiếu file model", response.json()["detail"])
        else:
            # This branch permits the same tests after model artifacts are restored.
            self.assertEqual(200, response.status_code)
            self.assertIn("agent", response.json())
            self.assertIsNone(response.json()["severity"])
            self.assertIn("không phải mức độ nặng", response.json()["severity_note"])

    def test_predict_accepts_image_with_generic_multipart_content_type(self):
        image = Image.new("RGB", (300, 300), "green")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG")

        with patch.object(
            api_server.vision_runtime,
            "predict",
            return_value=[
                {
                    "class_id": "Rice__LeafBlast",
                    "confidence_score": 0.78,
                }
            ],
        ):
            response = self.client.post(
                "/predict",
                files={
                    "file": (
                        "upload.jpg",
                        buffer.getvalue(),
                        "application/octet-stream",
                    )
                },
                data={
                    "farm_context": json.dumps(
                        {
                            "age_days": 42,
                            "growth_stage": "tillering",
                            "recent_weather": "normal",
                            "water_condition": "adequate",
                            "nitrogen_use": "balanced",
                        }
                    )
                },
            )

        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual("Rice__LeafBlast", response.json()["class_id"])
        self.assertIsNotNone(response.json()["agent"])
        self.assertEqual(42, response.json()["agent"]["context"]["age_days"])
        self.assertEqual("đẻ nhánh", response.json()["agent"]["context"]["growth_stage"])
        self.assertIsNone(response.json()["agent"]["pending_field"])
        self.assertIsNone(response.json()["agent"]["next_question"])

    def test_predict_rejects_invalid_farm_context_before_model_inference(self):
        image = Image.new("RGB", (300, 300), "green")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG")

        with patch.object(api_server.vision_runtime, "predict") as predict:
            response = self.client.post(
                "/predict",
                files={"file": ("leaf.jpg", buffer.getvalue(), "image/jpeg")},
                data={"farm_context": json.dumps({"age_days": 300})},
            )

        self.assertEqual(422, response.status_code)
        predict.assert_not_called()

    def test_predict_rejects_non_image_bytes(self):
        response = self.client.post(
            "/predict",
            files={"file": ("upload.jpg", b"not an image", "image/jpeg")},
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual("Không đọc được nội dung ảnh", response.json()["detail"])

    def test_predict_rejects_uploads_over_ten_megabytes(self):
        response = self.client.post(
            "/predict",
            files={
                "file": (
                    "large.jpg",
                    b"x" * (10 * 1024 * 1024 + 1),
                    "image/jpeg",
                )
            },
        )

        self.assertEqual(413, response.status_code)

    def test_predict_rejects_images_exceeding_pixel_limit(self):
        image = Image.new("RGB", (5001, 5000), "green")
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")

        with patch.object(api_server.vision_runtime, "predict") as predict:
            response = self.client.post(
                "/predict",
                files={"file": ("large.png", buffer.getvalue(), "image/png")},
            )

        self.assertEqual(413, response.status_code)
        predict.assert_not_called()

    def test_predict_does_not_expose_unexpected_model_errors(self):
        image = Image.new("RGB", (300, 300), "green")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG")

        with patch.object(
            api_server.vision_runtime,
            "predict",
            side_effect=ValueError("private model details"),
        ):
            with self.assertLogs("app.api.api_server", level="ERROR"):
                response = self.client.post(
                    "/predict",
                    files={"file": ("leaf.jpg", buffer.getvalue(), "image/jpeg")},
                )

        self.assertEqual(500, response.status_code)
        self.assertNotIn("private model details", response.text)


if __name__ == "__main__":
    unittest.main()
