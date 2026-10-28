"""PostgreSQL session storage and pgvector knowledge search."""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _psycopg():
    try:
        import psycopg
    except ImportError as exc:  # pragma: no cover - exercised only without optional dep
        raise RuntimeError(
            "Thiếu psycopg. Hãy chạy: python -m pip install 'psycopg[binary]'"
        ) from exc
    return psycopg


def _vector_literal(values: list[float]) -> str:
    return "[" + ",".join(f"{float(value):.9g}" for value in values) + "]"


class PostgreSQLSessionStore:
    """Session store with the same interface as the SQLite fallback."""

    backend_name = "postgresql"

    def __init__(self, database_url: str, *, initialize: bool = True) -> None:
        if not database_url:
            raise ValueError("DATABASE_URL không được để trống")
        self.database_url = database_url
        if initialize:
            self._initialize()

    def _connect(self):
        return _psycopg().connect(self.database_url, connect_timeout=5)

    def _initialize(self) -> None:
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS diagnostic_sessions (
                    session_id UUID PRIMARY KEY,
                    state_json JSONB NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )

    def status(self) -> dict[str, Any]:
        try:
            with self._connect() as connection, connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            return {"ready": True, "backend": self.backend_name, "error": None}
        except Exception as exc:
            return {"ready": False, "backend": self.backend_name, "error": str(exc)}

    def create(self, state: dict[str, Any]) -> str:
        session_id = str(uuid.uuid4())
        timestamp = _now_iso()
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO diagnostic_sessions
                    (session_id, state_json, created_at, updated_at)
                VALUES (%s, %s::jsonb, %s, %s)
                """,
                (session_id, json.dumps(state, ensure_ascii=False), timestamp, timestamp),
            )
        return session_id

    def get(self, session_id: str) -> dict[str, Any] | None:
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                "SELECT state_json FROM diagnostic_sessions WHERE session_id = %s",
                (session_id,),
            )
            row = cursor.fetchone()
        if not row:
            return None
        return row[0] if isinstance(row[0], dict) else json.loads(row[0])

    def save(self, session_id: str, state: dict[str, Any]) -> bool:
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE diagnostic_sessions
                SET state_json = %s::jsonb, updated_at = %s
                WHERE session_id = %s
                """,
                (json.dumps(state, ensure_ascii=False), _now_iso(), session_id),
            )
            return cursor.rowcount > 0

    def delete(self, session_id: str) -> bool:
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                "DELETE FROM diagnostic_sessions WHERE session_id = %s",
                (session_id,),
            )
            return cursor.rowcount > 0


class PGVectorKnowledgeStore:
    """Persist source chunks and perform hybrid semantic/keyword retrieval."""

    backend_name = "postgresql_pgvector"

    def __init__(self, database_url: str, *, dimensions: int = 1024) -> None:
        if not database_url:
            raise ValueError("DATABASE_URL không được để trống")
        self.database_url = database_url
        self.dimensions = dimensions

    def _connect(self):
        return _psycopg().connect(self.database_url, connect_timeout=5)

    def initialize(self) -> None:
        schema_path = Path(__file__).resolve().parents[2] / "infra" / "postgres" / "schema.sql"
        schema = schema_path.read_text(encoding="utf-8")
        schema = schema.replace("vector(1024)", f"vector({self.dimensions})")
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(schema)

    def status(self) -> dict[str, Any]:
        try:
            with self._connect() as connection, connection.cursor() as cursor:
                cursor.execute(
                    "SELECT COUNT(*) FROM knowledge_chunks WHERE embedding IS NOT NULL"
                )
                count = int(cursor.fetchone()[0])
            return {
                "ready": count > 0,
                "backend": self.backend_name,
                "embedded_chunks": count,
                "dimensions": self.dimensions,
                "error": None if count > 0 else "Chưa nạp knowledge chunks",
            }
        except Exception as exc:
            return {
                "ready": False,
                "backend": self.backend_name,
                "embedded_chunks": 0,
                "dimensions": self.dimensions,
                "error": str(exc),
            }

    def replace_document(
        self,
        document: dict[str, Any],
        chunks: list[dict[str, Any]],
        embeddings: list[list[float]],
    ) -> None:
        if len(chunks) != len(embeddings):
            raise ValueError("Số knowledge chunks và embeddings không khớp")
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO knowledge_documents
                    (document_id, class_id, title, source_url, source_type,
                     language, checksum, metadata)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                ON CONFLICT (document_id) DO UPDATE SET
                    class_id = EXCLUDED.class_id,
                    title = EXCLUDED.title,
                    source_url = EXCLUDED.source_url,
                    source_type = EXCLUDED.source_type,
                    language = EXCLUDED.language,
                    checksum = EXCLUDED.checksum,
                    metadata = EXCLUDED.metadata,
                    updated_at = NOW()
                """,
                (
                    document["document_id"],
                    document.get("class_id"),
                    document["title"],
                    document.get("source_url"),
                    document.get("source_type", "curated"),
                    document.get("language", "vi"),
                    document["checksum"],
                    json.dumps(document.get("metadata", {}), ensure_ascii=False),
                ),
            )
            cursor.execute(
                "DELETE FROM knowledge_chunks WHERE document_id = %s",
                (document["document_id"],),
            )
            for chunk, embedding in zip(chunks, embeddings):
                cursor.execute(
                    """
                    INSERT INTO knowledge_chunks
                        (chunk_id, document_id, class_id, topic, content,
                         content_hash, metadata, embedding)
                    VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s::vector)
                    """,
                    (
                        chunk["chunk_id"],
                        document["document_id"],
                        document.get("class_id"),
                        chunk.get("topic"),
                        chunk["content"],
                        chunk["content_hash"],
                        json.dumps(chunk.get("metadata", {}), ensure_ascii=False),
                        _vector_literal(embedding),
                    ),
                )

    def search(
        self,
        *,
        query: str,
        query_embedding: list[float],
        class_id: str,
        limit: int = 6,
    ) -> list[dict[str, Any]]:
        vector = _vector_literal(query_embedding)
        with self._connect() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    c.chunk_id,
                    c.class_id,
                    c.topic,
                    c.content,
                    d.title,
                    d.source_url,
                    d.language,
                    1 - (c.embedding <=> %s::vector) AS semantic_score,
                    ts_rank_cd(
                        c.search_vector,
                        websearch_to_tsquery('simple', %s)
                    ) AS lexical_score,
                    (
                        0.85 * (1 - (c.embedding <=> %s::vector)) +
                        0.15 * ts_rank_cd(
                            c.search_vector,
                            websearch_to_tsquery('simple', %s)
                        )
                    ) AS combined_score
                FROM knowledge_chunks c
                JOIN knowledge_documents d ON d.document_id = c.document_id
                WHERE c.embedding IS NOT NULL
                  AND (c.class_id = %s OR c.class_id IS NULL OR c.class_id = 'general')
                ORDER BY combined_score DESC
                LIMIT %s
                """,
                (vector, query, vector, query, class_id, max(1, min(limit, 12))),
            )
            columns = [item.name for item in cursor.description]
            rows = cursor.fetchall()
        return [dict(zip(columns, row)) for row in rows]
