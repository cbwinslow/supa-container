import pytest
from ingestion.chunker import ChunkingConfig, create_chunker
from ingestion.embedder import create_embedder
from unittest.mock import AsyncMock, patch


def test_simple_chunker_basic():
    """Ensure the simple chunker splits text correctly."""
    text = "Paragraph one.\n\nParagraph two that is a bit longer than the first." \
    text = """Paragraph one.

Paragraph two that is a bit longer than the first.

Third paragraph to force another chunk."""
    config = ChunkingConfig(chunk_size=50, chunk_overlap=10, use_semantic_splitting=False)
    chunker = create_chunker(config)
    chunks = chunker.chunk_document(text, title="Test", source="unit")
    assert len(chunks) >= 2
    assert all(c.metadata["title"] == "Test" for c in chunks)


@pytest.mark.asyncio
async def test_embedder_caches_embeddings():
    """Verify that the embedder caches repeated requests."""
    mock_client = AsyncMock()
    mock_client.embeddings.create.return_value = AsyncMock(
        data=[AsyncMock(embedding=[0.1, 0.2, 0.3])]
    )
    with patch("ingestion.embedder.embedding_client", mock_client):
        embedder = create_embedder()
        text = "test text"
        emb1 = await embedder.generate_embedding(text)
        emb2 = await embedder.generate_embedding(text)
        assert emb1 == emb2
        mock_client.embeddings.create.assert_called_once()
