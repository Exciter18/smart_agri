"""High-level semantic retriever used by the rice agent."""

from __future__ import annotations

import os
from typing import Any

from .embedding import OpenAIEmbeddings
from .postgres_store import PGVectorKnowledgeStore


class PostgresKnowledgeRetriever:
    def __init__(
        self,
        database_url: str,
        *,
        embedder: OpenAIEmbeddings | None = None,
        store: PGVectorKnowledgeStore | None = None,
    ) -> None:
        self.embedder = embedder or OpenAIEmbeddings()
        self.store = store or PGVectorKnowledgeStore(
            database_url, dimensions=self.embedder.dimensions
        )

    @classmethod
    def from_environment(cls) -> "PostgresKnowledgeRetriever | None":
        database_url = os.getenv("DATABASE_URL", "").strip()
        if not database_url:
            return None
        return cls(database_url)

    def status(self) -> dict[str, Any]:
        embedding = self.embedder.status()
        database = self.store.status()
        return {
            "ready": bool(embedding["ready"] and database["ready"]),
            "backend": self.store.backend_name,
            "embedding": embedding,
            "database": database,
        }

    def retrieve(
        self, query: str, *, class_id: str, top_k: int = 6
    ) -> list[dict[str, Any]]:
        embedding = self.embedder.embed_query(query)
        return self.store.search(
            query=query,
            query_embedding=embedding,
            class_id=class_id,
            limit=top_k,
        )
