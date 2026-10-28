"""Local language-model runtime backed by Ollama on localhost.

No request is sent to an Internet AI service.  Ollama loads the model weights
stored on the same computer and exposes a loopback HTTP interface.
"""

from __future__ import annotations

import os
import time
from dataclasses import asdict, dataclass
from typing import Any

import httpx


class LLMUnavailableError(RuntimeError):
    """Raised when the configured local language model cannot be used."""


@dataclass
class LLMGeneration:
    text: str
    model: str
    mode: str = "local_llm"
    latency_seconds: float | None = None
    prompt_tokens: int | None = None
    output_tokens: int | None = None
    tokens_per_second: float | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class OllamaLocalLLM:
    """Minimal Ollama client with an explicit, inspectable model contract."""

    def __init__(
        self,
        model: str | None = None,
        host: str | None = None,
        timeout_seconds: float = 300.0,
    ) -> None:
        self.model = model or os.getenv("OLLAMA_MODEL", "qwen2.5:3b")
        self.host = (host or os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")).rstrip(
            "/"
        )
        self.timeout_seconds = timeout_seconds

    def status(self) -> dict[str, Any]:
        try:
            response = httpx.get(f"{self.host}/api/tags", timeout=3.0)
            response.raise_for_status()
            available = {
                item.get("name")
                for item in response.json().get("models", [])
                if item.get("name")
            }
            # Ollama sometimes returns both a bare name and a :latest alias.
            aliases = {name.split(":")[0] for name in available}
            ready = self.model in available or self.model.split(":")[0] in aliases
            return {
                "ready": ready,
                "provider": "ollama_local",
                "model": self.model,
                "host": self.host,
                "external_api": False,
                "available_models": sorted(available),
                "error": None if ready else f"Model {self.model} chưa được tải trong Ollama",
            }
        except (httpx.HTTPError, ValueError) as exc:
            return {
                "ready": False,
                "provider": "ollama_local",
                "model": self.model,
                "host": self.host,
                "external_api": False,
                "available_models": [],
                "error": f"Không kết nối được Ollama cục bộ: {exc}",
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

        messages: list[dict[str, str]] = [
            {"role": "system", "content": system_prompt}
        ]
        for item in (history or [])[-4:]:
            role = item.get("role")
            content = item.get("message") or item.get("content")
            if role in {"user", "assistant"} and content:
                messages.append({"role": role, "content": str(content)[:800]})
        messages.append({"role": "user", "content": user_prompt})

        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "keep_alive": "10m",
            "options": {
                "temperature": 0.15,
                "top_p": 0.8,
                "repeat_penalty": 1.05,
                "num_ctx": 4096,
                "num_predict": 160,
            },
        }
        started = time.perf_counter()
        try:
            response = httpx.post(
                f"{self.host}/api/chat",
                json=payload,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise LLMUnavailableError(f"Ollama không sinh được câu trả lời: {exc}") from exc

        text = str(data.get("message", {}).get("content", "")).strip()
        if not text:
            raise LLMUnavailableError("Model ngôn ngữ trả về nội dung rỗng")
        eval_count = data.get("eval_count")
        eval_duration = data.get("eval_duration")
        tokens_per_second = None
        if eval_count and eval_duration:
            tokens_per_second = round(eval_count / (eval_duration / 1_000_000_000), 2)
        return LLMGeneration(
            text=text,
            model=str(data.get("model") or self.model),
            latency_seconds=round(time.perf_counter() - started, 3),
            prompt_tokens=data.get("prompt_eval_count"),
            output_tokens=eval_count,
            tokens_per_second=tokens_per_second,
        )
