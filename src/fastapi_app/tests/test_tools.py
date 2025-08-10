import pytest
from unittest.mock import patch, AsyncMock
from fastapi_app.tools import vector_search_tool, graph_search_tool, VectorSearchInput, GraphSearchInput

pytestmark = pytest.mark.asyncio

@pytest.fixture
def mock_db_calls():
    with patch('fastapi_app.tools.vector_search', new_callable=AsyncMock) as mock_vector,         patch('fastapi_app.tools.hybrid_search', new_callable=AsyncMock) as mock_hybrid:
        mock_vector.return_value = [{"chunk_id": "1", "document_id": "doc1", "content": "vec result", "similarity": 0.9, "metadata": {}, "document_title": "Doc 1", "document_source": "src1"}]
        yield {"vector": mock_vector, "hybrid": mock_hybrid}

@pytest.fixture
def mock_graph_calls():
    with patch('fastapi_app.tools.search_knowledge_graph', new_callable=AsyncMock) as mock_search:
        mock_search.return_value = [{"fact": "graph result", "uuid": "uuid1"}]
        yield mock_search

@pytest.fixture
def mock_embedding():
    with patch('fastapi_app.tools.generate_embedding', new_callable=AsyncMock) as mock_embed:
        mock_embed.return_value = [0.1] * 1536
        yield mock_embed

async def test_vector_search_tool_success(mock_db_calls, mock_embedding):
    input_data = VectorSearchInput(query="test query", limit=5)
    results = await vector_search_tool(input_data)
    
    mock_embedding.assert_called_once_with("test query")
    mock_db_calls["vector"].assert_called_once()
    assert len(results) == 1
    assert results[0].content == "vec result"
    assert results[0].score == 0.9

async def test_graph_search_tool_success(mock_graph_calls):
    input_data = GraphSearchInput(query="test query")
    results = await graph_search_tool(input_data)
    
    mock_graph_calls.assert_called_once_with(query="test query")
    assert len(results) == 1
    assert results[0].fact == "graph result"

async def test_vector_search_tool_handles_db_error(mock_db_calls, mock_embedding):
    mock_db_calls["vector"].side_effect = Exception("DB Error")
    input_data = VectorSearchInput(query="test query")
    results = await vector_search_tool(input_data)
    assert results == []

async def test_graph_search_tool_handles_graph_error(mock_graph_calls):
    mock_graph_calls.side_effect = Exception("Graph Error")
    input_data = GraphSearchInput(query="test query")
    results = await graph_search_tool(input_data)
    assert results == []
