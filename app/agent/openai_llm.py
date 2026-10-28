"""OpenAI Responses API provider for the rice advisory agent."""

from __future__ import annotations

import os
import time
from typing import Any

import httpx

from .local_llm import LLMGeneration, LLMUnavailableError


class OpenAIResponsesLLM:
    """Small, testable client for OpenAI's Responses API.

    The API key is read only on the backend from ``OPENAI_API_KEY`` and is
    never returned to the mobile application or written to the database.
    """

    def __init__(
        self,
        model: str | None = None,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout_seconds: float = 120.0,
        client: httpx.Client | None = None,
    ) -> None:
        self.model = model or os.getenv("OPENAI_MODEL", "gpt-6.1-sol")
        self.api_key = os.getenv("OPENAI_API_KEY") if api_key is None else api_key
        self.base_url = (
            base_url or os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
        ).rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.client = client or httpx.Client(timeout=timeout_seconds)

    def status(self) -> dict[str, Any]:
        configured = bool(self.api_key and self.api_key.strip())
        return {
            "ready": configured,
            "provider": "openai_responses_api",
            "model": self.model,
            "external_api": True,
            "base_url": self.base_url,
            "api_key_configured": configured,
            "error": None if configured else "Chưa cấu hình OPENAI_API_KEY ở backend",
        }

    def generate(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        history: list[dict[str, str]] | None = None,
    ) -> LLMGeneration:
        status = self.status()
        if not status["ready"]:
            raise LLMUnavailableError(status["error"])

        input_messages: list[dict[str, str]] = []
        for item in (history or [])[-4:]:
            role = item.get("role")
            content = item.get("message") or item.get("content")
            if role in {"user", "assistant"} and content:
                input_messages.append(
                    {"role": role, "content": str(content)[:1200]}
                )
        input_messages.append({"role": "user", "content": user_prompt})

        payload = {
            "model": self.model,
            "instructions": system_prompt,
            "input": input_messages,
            "reasoning": {"effort": "low"},
            "max_output_tokens": 500,
            "store": False,
        }
        started = time.perf_counter()
        try:
            response = self.client.post(
                f"{self.base_url}/responses",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            data = response.json()
        except httpx.HTTPStatusError as exc:
            request_id = exc.response.headers.get("x-request-id")
            suffix = f" (request_id={request_id})" if request_id else ""
            raise LLMUnavailableError(
                f"OpenAI API trả mã {exc.response.status_code}{suffix}"
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise LLMUnavailableError(f"Không gọi được OpenAI API: {exc}") from exc

        text = self._extract_output_text(data)
        if not text:
            raise LLMUnavailableError("OpenAI API không trả về nội dung văn bản")

        elapsed = time.perf_counter() - started
        usage = data.get("usage") or {}
        output_tokens = usage.get("output_tokens")
        tokens_per_second = None
        if output_tokens and elapsed > 0:
            tokens_per_second = round(float(output_tokens) / elapsed, 2)
        return LLMGeneration(
            text=text,
            model=str(data.get("model") or self.model),
            mode="openai_api",
            latency_seconds=round(elapsed, 3),
            prompt_tokens=usage.get("input_tokens"),
            output_tokens=output_tokens,
            tokens_per_second=tokens_per_second,
        )

    @staticmethod
    def _extract_output_text(data: dict[str, Any]) -> str:
        # Some compatible gateways expose the convenience field directly.
        direct = data.get("output_text")
        if isinstance(direct, str) and direct.strip():
            return direct.strip()

        parts: list[str] = []
        for item in data.get("output") or []:
            if not isinstance(item, dict) or item.get("type") != "message":
                continue
            for content in item.get("content") or []:
                if not isinstance(content, dict):
                    continue
                if content.get("type") == "output_text" and content.get("text"):
                    parts.append(str(content["text"]))
        return "\n".join(parts).strip()
