import os
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timezone

os.environ.setdefault("NEO4J_PASSWORD", "x")
os.environ.setdefault("LLM_API_KEY", "x")
os.environ.setdefault("EMBEDDING_API_KEY", "x")

from fastapi_app.graph_utils import GraphitiClient, test_graph_connection

pytestmark = pytest.mark.asyncio


async def create_client_with_mock_graphiti():
    client = GraphitiClient()
    client._initialized = True
    client.graphiti = AsyncMock()
    client.graphiti.driver = "driver"
    return client


async def test_clear_graph_success():
    client = await create_client_with_mock_graphiti()
    with patch("fastapi_app.graph_utils.clear_data", new_callable=AsyncMock) as mock_clear, \
         patch("fastapi_app.graph_utils.Graphiti") as mock_graphiti_cls:
        await client.clear_graph()
        mock_clear.assert_awaited_once_with("driver")
        mock_graphiti_cls.assert_not_called()


async def test_clear_graph_reinitializes_on_failure():
    client = await create_client_with_mock_graphiti()
    old_graphiti = client.graphiti
    new_graphiti = AsyncMock()
    with patch("fastapi_app.graph_utils.clear_data", new_callable=AsyncMock, side_effect=Exception("boom")), \
         patch("fastapi_app.graph_utils.Graphiti", return_value=new_graphiti) as mock_graphiti_cls, \
         patch("fastapi_app.graph_utils.OpenAIClient"), \
         patch("fastapi_app.graph_utils.OpenAIEmbedder"), \
         patch("fastapi_app.graph_utils.OpenAIRerankerClient"):
        await client.clear_graph()
        old_graphiti.close.assert_awaited_once()
        mock_graphiti_cls.assert_called_once()
        new_graphiti.build_indices_and_constraints.assert_awaited_once()


async def test_get_entity_timeline_sorted():
    client = await create_client_with_mock_graphiti()
    first = MagicMock(fact="older", uuid="1", valid_at=datetime(2021, 1, 1, tzinfo=timezone.utc))
    second = MagicMock(fact="newer", uuid="2", valid_at=datetime(2022, 1, 1, tzinfo=timezone.utc))
    third = MagicMock(fact="nodate", uuid="3", valid_at=None)
    client.graphiti.search.return_value = [first, third, second]

    timeline = await client.get_entity_timeline("entity")

    assert [item["fact"] for item in timeline] == ["newer", "older", "nodate"]


async def test_graph_connection_failure():
    mock_client = AsyncMock()
    mock_client.initialize.side_effect = Exception("fail")
    with patch("fastapi_app.graph_utils.graph_client", mock_client):
        result = await test_graph_connection()
        assert result is False
        mock_client.get_graph_statistics.assert_not_called()
