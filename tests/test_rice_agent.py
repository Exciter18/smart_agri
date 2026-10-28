import tempfile
import unittest
from pathlib import Path

from app.agent import LLMGeneration, RiceDiseaseAgent, SessionStore
from app.agent.rice_agent import MODEL_CLASS_IDS


class FakeLocalLLM:
    def __init__(self):
        self.calls = []

    def status(self):
        return {
            "ready": True,
            "provider": "fake_local",
            "model": "fake-qwen",
            "external_api": False,
        }

    def generate(self, *, system_prompt, user_prompt, history=None):
        self.calls.append(
            {
                "system_prompt": system_prompt,
                "user_prompt": user_prompt,
                "history": history or [],
            }
        )
        text = "Phản hồi được model ngôn ngữ tạo từ dữ liệu RAG."
        if '"missing_context":"age_days"' in user_prompt:
            text += " Cây lúa được gieo hoặc cấy khoảng bao nhiêu ngày rồi?"
        if '"assessment":"uncertain"' in user_prompt:
            text += " Kết quả chưa đủ chắc; cần cân nhắc Đốm nâu hẹp."
        if "ngập" in user_prompt.lower():
            text += " Ưu tiên kiểm tra thoát nước và không tự tăng nước."
        return LLMGeneration(
            text=text,
            model="fake-qwen",
            latency_seconds=0.01,
            prompt_tokens=100,
            output_tokens=20,
            tokens_per_second=100.0,
        )


class MetaFollowUpLLM(FakeLocalLLM):
    def generate(self, *, system_prompt, user_prompt, history=None):
        return LLMGeneration(
            text=(
                "Model nghiêng về bệnh bạc lá. Đã thiếu thông tin về tuổi cây, "
                "nên hỏi người dùng cây đã gieo hoặc cấy bao nhiêu ngày rồi?"
            ),
            model="fake-qwen",
        )


class RiceDiseaseAgentTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        store = SessionStore(Path(self.temp_dir.name) / "sessions.sqlite3")
        self.llm = FakeLocalLLM()
        self.agent = RiceDiseaseAgent(session_store=store, llm=self.llm)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_knowledge_matches_every_model_class(self):
        self.assertEqual(set(MODEL_CLASS_IDS), set(self.agent.classes))
        self.assertEqual(9, len(self.agent.classes))

    def test_start_asks_context_not_visible_lesion_description(self):
        result = self.agent.start_diagnosis(
            "Rice__LeafBlast",
            confidence=0.82,
            top_predictions=[
                {"class_id": "Rice__LeafBlast", "confidence_score": 0.82},
                {"class_id": "Rice__BrownSpot", "confidence_score": 0.10},
            ],
        )
        message = result["message"].lower()
        self.assertIn("bao nhiêu ngày", message)
        self.assertNotIn("hình dạng vết", message)
        self.assertNotIn("vết có màu", message)
        self.assertEqual("age_days", result["pending_field"])
        self.assertEqual("local_llm", result["generation"]["mode"])

    def test_meta_follow_up_is_replaced_with_a_direct_question(self):
        self.agent.llm = MetaFollowUpLLM()
        result = self.agent.start_diagnosis(
            "Rice__BacterialLeafBlight", confidence=0.82
        )
        message = result["message"]
        self.assertNotIn("nên hỏi người dùng", message.lower())
        self.assertTrue(
            message.endswith("Cây lúa được gieo hoặc cấy khoảng bao nhiêu ngày rồi?")
        )

    def test_rag_prompt_contains_prediction_context_and_sources(self):
        self.agent.start_diagnosis("Rice__LeafBlast", confidence=0.82)
        prompt = self.llm.calls[-1]["user_prompt"]
        self.assertIn("RAG_CONTEXT", prompt)
        self.assertIn("Rice__LeafBlast", prompt)
        self.assertIn("IRRI Rice Knowledge Bank - Blast", prompt)
        self.assertIn("độ tin cậy phân loại", prompt)

    def test_context_is_extracted_and_conversation_advances(self):
        started = self.agent.start_diagnosis("Rice__LeafBlast", confidence=0.75)
        reply = self.agent.chat(
            started["session_id"],
            "Lúa gieo được 35 ngày, đang đẻ nhánh. Gần đây mưa nhiều và tôi vừa bón urê.",
        )
        self.assertEqual(35, reply["context"]["age_days"])
        self.assertEqual("đẻ nhánh", reply["context"]["growth_stage"])
        self.assertIn("recent_weather", reply["context"])
        self.assertIn("nitrogen_use", reply["context"])
        self.assertEqual("water_condition", reply["pending_field"])

    def test_age_can_supply_a_clearly_marked_stage_estimate(self):
        started = self.agent.start_diagnosis("Rice__BrownSpot", confidence=0.75)
        reply = self.agent.chat(started["session_id"], "Lúa gieo được 62 ngày")
        self.assertEqual("làm đòng", reply["context"]["growth_stage"])
        self.assertEqual(
            "estimated_from_age", reply["context"]["growth_stage_source"]
        )
        self.assertIn("tạm ước tính", reply["message"])

    def test_neck_blast_stage_contradiction_is_flagged(self):
        started = self.agent.start_diagnosis("Rice__NeckBlast", confidence=0.84)
        reply = self.agent.chat(
            started["session_id"], "Lúa 35 ngày tuổi và đang đẻ nhánh"
        )
        self.assertIn("không phù hợp", reply["message"])
        self.assertIn("kiểm tra lại", reply["message"])

    def test_close_top_predictions_are_marked_uncertain(self):
        result = self.agent.start_diagnosis(
            "Rice__BrownSpot",
            confidence=0.61,
            top_predictions=[
                {"class_id": "Rice__BrownSpot", "confidence_score": 0.61},
                {"class_id": "Rice__NarrowBrownLeafSpot", "confidence_score": 0.56},
            ],
        )
        self.assertEqual("uncertain", result["assessment"])
        self.assertIn("chưa đủ chắc", result["message"])
        self.assertIn("Đốm nâu hẹp", result["message"])

    def test_water_answer_uses_context_without_inventing_liters(self):
        started = self.agent.start_diagnosis("Rice__BacterialLeafBlight", 0.88)
        self.agent.chat(started["session_id"], "Cây lúa được 45 ngày")
        reply = self.agent.chat(
            started["session_id"],
            "Ruộng mẫu đang bị ngập và mấy ngày nay mưa nhiều, tưới thế nào?",
        )
        self.assertIn("thoát nước", reply["message"])
        self.assertNotIn("lít/ngày", reply["message"])

    def test_pesticide_question_returns_safety_guard_and_source(self):
        started = self.agent.start_diagnosis("Rice__Hispa", 0.9)
        reply = self.agent.chat(
            started["session_id"], "Dùng thuốc gì và pha liều bao nhiêu?"
        )
        self.assertIn("không tự pha", reply["message"].lower())
        self.assertIn("sansangxuatkhau.ppd.gov.vn", reply["message"])


if __name__ == "__main__":
    unittest.main()
