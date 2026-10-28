import tempfile
import unittest
from pathlib import Path

import httpx

from app.agent import LLMGeneration, RiceDiseaseAgent, SessionStore
from app.knowledge.embedding import OpenAIEmbeddings
from app.knowledge.ingest import build_seed_documents, chunk_text
from app.knowledge.retriever import PostgresKnowledgeRetriever


class FakeResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code
        self.headers = {}
        self.request = httpx.Request("POST", "https://example.test/embeddings")

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                "failed", request=self.request, response=httpx.Response(self.status_code)
            )

    def json(self):
        return self._payload


class FakeHttpClient:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def post(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return self.response


class FakeVectorStore:
    backend_name = "postgresql_pgvector"

    def __init__(self):
        self.calls = []

    def status(self):
        return {"ready": True, "embedded_chunks": 12}

    def search(self, **kwargs):
        self.calls.append(kwargs)
        return [
            {
                "content": "Giữ mực nước phù hợp với giai đoạn sinh trưởng.",
                "topic": "water_management",
                "title": "FAO - Sustainable Rice Systems",
                "source_url": "https://www.fao.org/example",
                "combined_score": 0.88,
            }
        ]


class FakeLLM:
    def __init__(self):
        self.user_prompt = ""

    def status(self):
        return {"ready": True, "external_api": False, "model": "fake"}

    def generate(self, *, system_prompt, user_prompt, history=None):
        self.user_prompt = user_prompt
        return LLMGeneration(text="Câu trả lời từ RAG.", model="fake")


class KnowledgeTests(unittest.TestCase):
    def test_embedding_response_order_and_dimensions(self):
        response = FakeResponse(
            {"data": [{"index": 1, "embedding": [0.3, 0.4]}, {"index": 0, "embedding": [0.1, 0.2]}]}
        )
        client = FakeHttpClient(response)
        embeddings = OpenAIEmbeddings(
            api_key="test-key", dimensions=2, client=client
        )
        self.assertEqual([[0.1, 0.2], [0.3, 0.4]], embeddings.embed_texts(["a", "b"]))
        self.assertEqual(2, client.calls[0][1]["json"]["dimensions"])

    def test_curated_json_becomes_searchable_chunks(self):
        documents = build_seed_documents()
        self.assertEqual(9, len(documents))
        self.assertGreater(sum(len(item["chunks"]) for item in documents), 45)
        self.assertTrue(all(item["checksum"] for item in documents))

    def test_chunker_splits_long_content(self):
        text = "Đoạn dữ liệu thử nghiệm. " * 200
        chunks = chunk_text(text, max_chars=300, overlap_chars=30)
        self.assertGreater(len(chunks), 2)
        self.assertTrue(all(len(item) <= 340 for item in chunks))

    def test_retriever_embeds_query_and_filters_by_class(self):
        embedder = OpenAIEmbeddings(
            api_key="test-key",
            dimensions=2,
            client=FakeHttpClient(FakeResponse({"data": [{"index": 0, "embedding": [0.1, 0.2]}]})),
        )
        store = FakeVectorStore()
        retriever = PostgresKnowledgeRetriever("ignored", embedder=embedder, store=store)
        rows = retriever.retrieve("cách tưới", class_id="Rice__LeafBlast", top_k=4)
        self.assertEqual(1, len(rows))
        self.assertEqual("Rice__LeafBlast", store.calls[0]["class_id"])

    def test_agent_includes_vector_evidence_in_rag_prompt(self):
        temp_dir = tempfile.TemporaryDirectory()
        try:
            llm = FakeLLM()
            store = FakeVectorStore()
            embedder = OpenAIEmbeddings(
                api_key="test-key",
                dimensions=2,
                client=FakeHttpClient(FakeResponse({"data": [{"index": 0, "embedding": [0.1, 0.2]}]})),
            )
            retriever = PostgresKnowledgeRetriever("ignored", embedder=embedder, store=store)
            agent = RiceDiseaseAgent(
                session_store=SessionStore(Path(temp_dir.name) / "sessions.sqlite3"),
                llm=llm,
                retriever=retriever,
            )
            agent.start_diagnosis("Rice__LeafBlast", 0.8)
            self.assertIn("semantic_evidence", llm.user_prompt)
            self.assertIn("FAO - Sustainable Rice Systems", llm.user_prompt)
            self.assertIn("https://www.fao.org/example", llm.user_prompt)
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
