import unittest

import httpx

from app.agent import LLMUnavailableError, OpenAIResponsesLLM


class OpenAIResponsesLLMTests(unittest.TestCase):
    def test_status_requires_backend_api_key(self):
        llm = OpenAIResponsesLLM(api_key="")
        status = llm.status()
        self.assertFalse(status["ready"])
        self.assertTrue(status["external_api"])
        self.assertFalse(status["api_key_configured"])

    def test_generate_uses_responses_api_without_exposing_key(self):
        captured = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured["url"] = str(request.url)
            captured["authorization"] = request.headers.get("authorization")
            captured["payload"] = request.read().decode("utf-8")
            return httpx.Response(
                200,
                json={
                    "model": "gpt-6.1-sol-2026-09-01",
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {
                                    "type": "output_text",
                                    "text": "Cần kiểm tra nước và tuổi lúa.",
                                }
                            ],
                        }
                    ],
                    "usage": {"input_tokens": 80, "output_tokens": 12},
                },
            )

        client = httpx.Client(transport=httpx.MockTransport(handler))
        llm = OpenAIResponsesLLM(
            api_key="test-secret",
            model="gpt-6.1-sol",
            client=client,
        )
        result = llm.generate(
            system_prompt="Chỉ dùng dữ liệu RAG.",
            user_prompt="Tưới thế nào?",
            history=[{"role": "user", "message": "Lúa 35 ngày"}],
        )

        self.assertEqual("openai_api", result.mode)
        self.assertEqual("Cần kiểm tra nước và tuổi lúa.", result.text)
        self.assertEqual(80, result.prompt_tokens)
        self.assertEqual(12, result.output_tokens)
        self.assertTrue(captured["url"].endswith("/v1/responses"))
        self.assertEqual("Bearer test-secret", captured["authorization"])
        self.assertIn('"store":false', captured["payload"].replace(" ", ""))

    def test_generate_fails_cleanly_without_key(self):
        llm = OpenAIResponsesLLM(api_key="")
        with self.assertRaises(LLMUnavailableError):
            llm.generate(system_prompt="x", user_prompt="y")


if __name__ == "__main__":
    unittest.main()
