"""OpenAI embedding client used by the pgvector knowledge store."""

from __future__ import annotations

import os
from typing import Any

import httpx


class EmbeddingUnavailableError(RuntimeError):
    """Raised when the embedding provider cannot serve a request."""


class OpenAIEmbeddings:
    """Small HTTP client for the OpenAI Embeddings API.

    Keeping this client independent from the OpenAI SDK makes it easy to mock
    in tests and keeps the backend dependency surface small.
    """

    def __init__(
        self,
        *,
        model: str | None = None,
        dimensions: int | None = None,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout_seconds: float = 120.0,
        client: httpx.Client | None = None,
    ) -> None:
        self.model = model or os.getenv(
            "OPENAI_EMBEDDING_MODEL", "text-embedding-3-large"
        )
        configured_dimensions = os.getenv("OPENAI_EMBEDDING_DIMENSIONS", "1024")
        self.dimensions = dimensions or int(configured_dimensions)
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
            "provider": "openai_embeddings_api",
            "model": self.model,
            "dimensions": self.dimensions,
            "api_key_configured": configured,
            "error": None if configured else "Chưa cấu hình OPENAI_API_KEY ở backend",
        }

    def embed_texts(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        status = self.status()
        if not status["ready"]:
            raise EmbeddingUnavailableError(str(status["error"]))

        payload: dict[str, Any] = {
            "model": self.model,
            "input": texts,
            "encoding_format": "float",
        }
        if self.dimensions:
            payload["dimensions"] = self.dimensions
        try:
            response = self.client.post(
                f"{self.base_url}/embeddings",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            body = response.json()
        except httpx.HTTPStatusError as exc:
            request_id = exc.response.headers.get("x-request-id")
            suffix = f" (request_id={request_id})" if request_id else ""
            raise EmbeddingUnavailableError(
                f"OpenAI Embeddings API trả mã {exc.response.status_code}{suffix}"
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise EmbeddingUnavailableError(
                f"Không gọi được OpenAI Embeddings API: {exc}"
            ) from exc

        rows = sorted(body.get("data") or [], key=lambda item: item.get("index", 0))
        embeddings = [row.get("embedding") for row in rows]
        if len(embeddings) != len(texts) or any(not row for row in embeddings):
            raise EmbeddingUnavailableError(
                "OpenAI Embeddings API trả về số vector không khớp dữ liệu đầu vào"
            )
        for vector in embeddings:
            if len(vector) != self.dimensions:
                raise EmbeddingUnavailableError(
                    f"Vector có {len(vector)} chiều, yêu cầu {self.dimensions} chiều"
                )
        return embeddings

    def embed_query(self, text: str) -> list[float]:
        vectors = self.embed_texts([text])
        return vectors[0]
