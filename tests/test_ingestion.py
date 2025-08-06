import pytest
from unittest.mock import patch, AsyncMock
from ingestion.ingest import DocumentIngestionPipeline
from ingestion.chunker import ChunkingConfig
from agent.models import IngestionConfig

pytestmark = pytest.mark.asyncio

@pytest.fixture
def mock_db_utils_ingestion():
    with patch('ingestion.ingest.db_pool.acquire') as mock_acquire:
        mock_conn = AsyncMock()
        mock_acquire.return_value.__aenter__.return_value = mock_conn
        mock_conn.fetchrow.return_value = {'id': 'new-doc-id'}
        yield mock_conn

@pytest.fixture
def mock_graph_builder():
    with patch('ingestion.ingest.create_graph_builder') as mock_create:
        mock_builder = AsyncMock()
        mock_builder.add_document_to_graph.return_value = {"episodes_created": 5, "errors": []}
        mock_create.return_value = mock_builder
        yield mock_builder

@pytest.fixture
def mock_embedder():
    with patch('ingestion.ingest.create_embedder') as mock_create:
        mock_embed = AsyncMock()
        # Simulate embed_chunks adding an 'embedding' attribute to each chunk
        async def fake_embed_chunks(chunks, **kwargs):
            for chunk in chunks:
                chunk.embedding = [0.1] * 1536
            return chunks
        mock_embed.embed_chunks = fake_embed_chunks
        mock_create.return_value = mock_embed
        yield mock_embed

async def test_ingestion_pipeline(tmp_path, mock_db_utils_ingestion, mock_graph_builder, mock_embedder):
    # Create a dummy document
    doc_path = tmp_path / "test_doc.md"
    doc_path.write_text("# Test Document\n\nThis is test content.")

    ingest_config = IngestionConfig(chunk_size=50, chunk_overlap=10)
    
    pipeline = DocumentIngestionPipeline(config=ingest_config, documents_folder=str(tmp_path))
    
    # Mock the initialization of external services within the pipeline instance
    pipeline.graph_builder = mock_graph_builder
    
    results = await pipeline.ingest_documents()
    
    assert len(results) == 1
    assert results[0].title == "Test Document"
    assert results[0].chunks_created > 0
    assert results[0].relationships_created == 5
    
    # Verify that the save to postgres function was called
    mock_db_utils_ingestion.fetchrow.assert_called()
    # Verify that the graph builder was called
    mock_graph_builder.add_document_to_graph.assert_called_once()
