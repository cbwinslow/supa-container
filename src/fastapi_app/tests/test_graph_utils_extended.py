import os
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

os.environ.setdefault("NEO4J_PASSWORD", "test")
os.environ.setdefault("LLM_API_KEY", "test")
os.environ.setdefault("EMBEDDING_API_KEY", "test")

from fastapi_app import graph_utils

GraphitiClient = graph_utils.GraphitiClient

pytestmark = pytest.mark.asyncio


async def test_clear_graph_uses_clear_data():
    client = GraphitiClient()
    client.graphiti = MagicMock()
    client.graphiti.driver = "driver"
    client._initialized = True

    with patch('fastapi_app.graph_utils.clear_data', new_callable=AsyncMock) as mock_clear_data:
        await client.clear_graph()
        mock_clear_data.assert_awaited_once_with("driver")


async def test_clear_graph_reinitializes_on_failure():
    client = GraphitiClient()
    original_graphiti = AsyncMock()
    original_graphiti.driver = "driver"
    client.graphiti = original_graphiti
    client._initialized = True

    with patch('fastapi_app.graph_utils.clear_data', new_callable=AsyncMock) as mock_clear_data, \
         patch('fastapi_app.graph_utils.Graphiti') as mock_graphiti, \
         patch('fastapi_app.graph_utils.OpenAIClient'), \
         patch('fastapi_app.graph_utils.OpenAIEmbedder'), \
         patch('fastapi_app.graph_utils.OpenAIRerankerClient'):
        mock_clear_data.side_effect = Exception("boom")
        new_instance = AsyncMock()
        mock_graphiti.return_value = new_instance

        await client.clear_graph()

        original_graphiti.close.assert_awaited_once()
        mock_graphiti.assert_called_once()
        new_instance.build_indices_and_constraints.assert_awaited_once()
        assert client.graphiti is new_instance


async def test_get_entity_timeline_sorted():
    client = GraphitiClient()
    client.graphiti = AsyncMock()
    client._initialized = True

    older = MagicMock(fact="Older", uuid="1", valid_at=datetime(2023, 1, 1))
    newer = MagicMock(fact="Newer", uuid="2", valid_at=datetime(2023, 1, 2))
    client.graphiti.search.return_value = [older, newer]

    timeline = await client.get_entity_timeline("entity")

    assert timeline[0]["fact"] == "Newer"
    assert timeline[1]["fact"] == "Older"


async def test_test_graph_connection_handles_failure():
    mock_client = MagicMock()
    mock_client.initialize = AsyncMock(side_effect=Exception("fail"))
    mock_client.get_graph_statistics = AsyncMock()

    with patch('fastapi_app.graph_utils.graph_client', mock_client):
        result = await graph_utils.test_graph_connection()

    assert result is False
    mock_client.get_graph_statistics.assert_not_called()
