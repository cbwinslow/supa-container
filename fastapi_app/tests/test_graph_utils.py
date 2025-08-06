import pytest
from unittest.mock import patch, AsyncMock
from agent.graph_utils import GraphitiClient, search_knowledge_graph

pytestmark = pytest.mark.asyncio

@pytest.fixture
def mock_graphiti_native():
    """Mocks the underlying Graphiti library."""
    with patch('agent.graph_utils.Graphiti') as mock_graphiti:
        instance = AsyncMock()
        instance.search.return_value = [
            MagicMock(fact="Test fact 1", uuid="uuid1"),
            MagicMock(fact="Test fact 2", uuid="uuid2")
        ]
        mock_graphiti.return_value = instance
        yield instance

async def test_graphiti_client_initialization(mock_graphiti_native):
    client = GraphitiClient()
    await client.initialize()
    assert client.graphiti is not None
    mock_graphiti_native.build_indices_and_constraints.assert_called_once()
    await client.close()

async def test_graphiti_client_search(mock_graphiti_native):
    client = GraphitiClient()
    await client.initialize()
    results = await client.search("test query")
    
    client.graphiti.search.assert_called_once_with("test query")
    assert len(results) == 2
    assert results[0]["fact"] == "Test fact 1"

async def test_search_knowledge_graph_wrapper(mock_graphiti_native):
    # This tests the convenience wrapper function
    with patch('agent.graph_utils.graph_client', new_callable=AsyncMock) as mock_client_instance:
        mock_client_instance.search.return_value = [{"fact": "wrapper result"}]
        
        results = await search_knowledge_graph("wrapper query")
        
        mock_client_instance.search.assert_called_once_with("wrapper query")
        assert len(results) == 1
        assert results[0]["fact"] == "wrapper result"
