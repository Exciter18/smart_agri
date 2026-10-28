"""Build the rice knowledge base and ingest it into PostgreSQL/pgvector.

Examples:
    python -m app.knowledge.ingest --initialize
    python -m app.knowledge.ingest --initialize --include-remote
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

import httpx

from .embedding import OpenAIEmbeddings
from .postgres_store import PGVectorKnowledgeStore


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_KNOWLEDGE = PROJECT_ROOT / "app" / "agent" / "data" / "rice_knowledge.json"
DEFAULT_MANIFEST = PROJECT_ROOT / "data" / "knowledge" / "sources.json"

FIELD_LABELS = {
    "cause": "Nguyên nhân",
    "overview": "Tổng quan",
    "symptoms": "Triệu chứng",
    "favorable_conditions": "Điều kiện thuận lợi",
    "management": "Quản lý và xử lý",
    "watering": "Quản lý nước",
    "fertilizer": "Dinh dưỡng và phân bón",
    "prevention": "Phòng ngừa",
    "lookalikes": "Chẩn đoán phân biệt",
}


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _join_value(value: Any) -> str:
    if isinstance(value, list):
        return "\n".join(f"- {item}" for item in value if str(item).strip())
    return str(value).strip()


def chunk_text(text: str, *, max_chars: int = 1600, overlap_chars: int = 220) -> list[str]:
    """Split prose at paragraph/sentence boundaries with a small overlap."""

    normalized = re.sub(r"[ \t]+", " ", text)
    normalized = re.sub(r"\n{3,}", "\n\n", normalized).strip()
    if not normalized:
        return []
    units = [
        unit.strip()
        for unit in re.split(r"(?<=[.!?])\s+|\n\s*\n", normalized)
        if unit.strip()
    ]
    chunks: list[str] = []
    current = ""
    for unit in units:
        if len(unit) > max_chars:
            pieces = [unit[i : i + max_chars] for i in range(0, len(unit), max_chars)]
        else:
            pieces = [unit]
        for piece in pieces:
            candidate = f"{current}\n{piece}".strip() if current else piece
            if current and len(candidate) > max_chars:
                chunks.append(current)
                current = (current[-overlap_chars:] + " " + piece).strip()
            else:
                current = candidate
    if current:
        chunks.append(current)
    return chunks


def build_seed_documents(path: str | Path = DEFAULT_KNOWLEDGE) -> list[dict[str, Any]]:
    """Convert the curated JSON into source-aware documents and chunks."""

    knowledge = json.loads(Path(path).read_text(encoding="utf-8"))
    documents: list[dict[str, Any]] = []
    for class_id, record in knowledge["classes"].items():
        title = f"Hồ sơ đã kiểm duyệt: {record['display_name']}"
        document_id = "curated-" + _sha256(class_id)[:20]
        source_rows = record.get("sources", [])
        chunk_rows: list[dict[str, Any]] = []
        all_content: list[str] = []
        for field, label in FIELD_LABELS.items():
            content = _join_value(record.get(field, ""))
            if not content:
                continue
            full_content = f"Bệnh/đối tượng: {record['display_name']}\n{label}:\n{content}"
            all_content.append(full_content)
            for index, piece in enumerate(chunk_text(full_content)):
                content_hash = _sha256(piece)
                chunk_rows.append(
                    {
                        "chunk_id": f"{document_id}-{field}-{index}-{content_hash[:10]}",
                        "topic": field,
                        "content": piece,
                        "content_hash": content_hash,
                        "metadata": {"field": field, "source_titles": [s["title"] for s in source_rows]},
                    }
                )
        documents.append(
            {
                "document_id": document_id,
                "class_id": class_id,
                "title": title,
                "source_url": source_rows[0]["url"] if source_rows else None,
                "source_type": "curated_json",
                "language": "vi",
                "checksum": _sha256("\n".join(all_content)),
                "metadata": {"sources": source_rows, "category": record.get("category")},
                "chunks": chunk_rows,
            }
        )
    return documents


def _extract_html(content: bytes) -> str:
    try:
        from bs4 import BeautifulSoup
    except ImportError as exc:
        raise RuntimeError("Thiếu beautifulsoup4 để đọc nguồn HTML") from exc
    soup = BeautifulSoup(content, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header", "noscript"]):
        tag.decompose()
    return "\n".join(
        line.strip() for line in soup.get_text("\n").splitlines() if line.strip()
    )


def _extract_pdf(content: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("Thiếu pypdf để đọc nguồn PDF") from exc
    reader = PdfReader(io.BytesIO(content))
    return "\n\n".join((page.extract_text() or "").strip() for page in reader.pages)


def download_manifest_documents(
    manifest_path: str | Path = DEFAULT_MANIFEST,
    *,
    timeout_seconds: float = 45.0,
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    """Download allow-listed official sources; failures are reported per URL."""

    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    documents: list[dict[str, Any]] = []
    failures: list[dict[str, str]] = []
    headers = {"User-Agent": "SmartAgricultureResearchBot/1.0 (educational project)"}
    with httpx.Client(timeout=timeout_seconds, follow_redirects=True, headers=headers) as client:
        for source in manifest["sources"]:
            try:
                response = client.get(source["url"])
                response.raise_for_status()
                content_type = response.headers.get("content-type", "").lower()
                if "pdf" in content_type or source["url"].lower().endswith(".pdf"):
                    text = _extract_pdf(response.content)
                else:
                    text = _extract_html(response.content)
                text = text.strip()
                if len(text) < 200:
                    raise RuntimeError("Nguồn tải về có quá ít nội dung văn bản")
                document_id = "remote-" + _sha256(source["url"])[:20]
                chunk_rows = []
                for index, piece in enumerate(chunk_text(text)):
                    content_hash = _sha256(piece)
                    chunk_rows.append(
                        {
                            "chunk_id": f"{document_id}-{index}-{content_hash[:10]}",
                            "topic": source.get("topic"),
                            "content": piece,
                            "content_hash": content_hash,
                            "metadata": {"source_url": source["url"]},
                        }
                    )
                documents.append(
                    {
                        "document_id": document_id,
                        "class_id": source.get("class_id"),
                        "title": source["title"],
                        "source_url": source["url"],
                        "source_type": "official_remote",
                        "language": source.get("language", "en"),
                        "checksum": _sha256(text),
                        "metadata": {
                            "publisher": source.get("publisher"),
                            "topic": source.get("topic"),
                            "retrieved_from_manifest": True,
                        },
                        "chunks": chunk_rows,
                    }
                )
            except Exception as exc:
                failures.append({"url": source["url"], "error": str(exc)})
    return documents, failures


def _batches(items: list[Any], size: int) -> Iterable[list[Any]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def ingest_documents(
    documents: list[dict[str, Any]],
    *,
    store: PGVectorKnowledgeStore,
    embedder: OpenAIEmbeddings,
    batch_size: int = 32,
) -> dict[str, int]:
    document_count = 0
    chunk_count = 0
    for document in documents:
        chunks = document["chunks"]
        document_payload = {
            key: value for key, value in document.items() if key != "chunks"
        }
        embeddings: list[list[float]] = []
        for batch in _batches(chunks, batch_size):
            embeddings.extend(embedder.embed_texts([item["content"] for item in batch]))
        store.replace_document(document_payload, chunks, embeddings)
        document_count += 1
        chunk_count += len(chunks)
    return {"documents": document_count, "chunks": chunk_count}


def main() -> int:
    # Windows terminals can default to cp1252 even when project files are UTF-8.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Nạp kiến thức bệnh lúa vào pgvector")
    parser.add_argument("--initialize", action="store_true", help="Tạo extension và bảng")
    parser.add_argument("--include-remote", action="store_true", help="Tải nguồn chính thống trong manifest")
    parser.add_argument("--knowledge", default=str(DEFAULT_KNOWLEDGE))
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    args = parser.parse_args()

    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        parser.error("Cần đặt biến DATABASE_URL")
    embedder = OpenAIEmbeddings()
    if not embedder.status()["ready"]:
        parser.error("Cần đặt OPENAI_API_KEY để tạo embeddings")
    store = PGVectorKnowledgeStore(database_url, dimensions=embedder.dimensions)
    if args.initialize:
        store.initialize()

    documents = build_seed_documents(args.knowledge)
    failures: list[dict[str, str]] = []
    if args.include_remote:
        remote_documents, failures = download_manifest_documents(args.manifest)
        documents.extend(remote_documents)
    result = ingest_documents(documents, store=store, embedder=embedder)
    print(json.dumps({**result, "download_failures": failures}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
