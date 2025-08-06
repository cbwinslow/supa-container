import pytest
from unittest.mock import patch, AsyncMock
from ingestion.embedder import EmbeddingGenerator
from ingestion.chunker import DocumentChunk

pytestmark = pytest.mark.asyncio

@pytest.fixture
def mock_openai_client():
    with patch('ingestion.embedder.embedding_client', new_callable=AsyncMock) as mock_client:
        # Mock the response structure from OpenAI's library
        mock_embedding = AsyncMock()
        mock_embedding.embedding = [0.1] * 1536
        mock_response = AsyncMock()
        mock_response.data = [mock_embedding]
        mock_client.embeddings.create.return_value = mock_response
        yield mock_client

async def test_embedding_generator_single_text(mock_openai_client):
    embedder = EmbeddingGenerator()
    embedding = await embedder.generate_embedding("test text")
    
    mock_openai_client.embeddings.create.assert_called_once()
    assert len(embedding) == 1536
    assert embedding[0] == 0.1

async def test_embedding_generator_batch(mock_openai_client):
    embedder = EmbeddingGenerator()
    texts = ["text 1", "text 2"]
    embeddings = await embedder.generate_embeddings_batch(texts)
    
    mock_openai_client.embeddings.create.assert_called_once()
    assert len(embeddings) == 2
    assert len(embeddings[0]) == 1536

async def test_embed_chunks(mock_openai_client):
    embedder = EmbeddingGenerator()
    chunks = [
        DocumentChunk(content="chunk 1", index=0, start_char=0, end_char=7, metadata={}),
        DocumentChunk(content="chunk 2", index=1, start_char=8, end_char=15, metadata={})
    ]
    
    embedded_chunks = await embedder.embed_chunks(chunks)
    
    assert len(embedded_chunks) == 2
    assert hasattr(embedded_chunks[0], 'embedding')
    assert len(embedded_chunks[0].embedding) == 1536
    assert "embedding_model" in embedded_chunks[0].metadata

async def test_embedding_generator_api_error_fallback(mock_openai_client):
    # Simulate an API error
    mock_openai_client.embeddings.create.side_effect = Exception("API Error")
    
    embedder = EmbeddingGenerator(max_retries=1) # Don't wait long for retries in tests
    
    # For a single text, it should raise the exception
    with pytest.raises(Exception, match="API Error"):
        await embedder.generate_embedding("test text")

    # For a batch, it should fall back to individual processing and return zero vectors
    texts = ["text 1", "text 2"]
    embeddings = await embedder.generate_embeddings_batch(texts)
    assert len(embeddings) == 2
    assert embeddings[0] == [0.0] * 1536 # Check for fallback zero vector
