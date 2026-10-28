import io
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
