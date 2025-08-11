import os
import tests.conftest  # noqa: F401

import json
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi_app.api import app
from fastapi_app.models import ChunkResult, GraphSearchResult

# Use pytest-asyncio for async tests
pytestmark = pytest.mark.asyncio

client = TestClient(app)

# --- Mocks and Fixtures ---


@pytest.fixture(autouse=True)
def mock_auth():
    """Mock authentication dependency to always succeed."""
    with patch(
        "fastapi_app.api.verify_auth_token", new_callable=AsyncMock, return_value=True
    ):
        yield


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer testtoken"}


@pytest.fixture
def mock_db_utils():
    """Mocks all functions in the db_utils module."""
    with patch(
        "fastapi_app.api.initialize_database", new_callable=AsyncMock
    ) as _, patch("fastapi_app.api.close_database", new_callable=AsyncMock) as _, patch(
        "fastapi_app.api.create_session",
        new_callable=AsyncMock,
        return_value="new-session-123",
    ) as mock_create, patch(
        "fastapi_app.api.get_session",
        new_callable=AsyncMock,
        return_value={"id": "existing-session-456"},
    ) as mock_get, patch(
        "fastapi_app.api.add_message", new_callable=AsyncMock
    ) as mock_add, patch(
        "fastapi_app.api.get_session_messages", new_callable=AsyncMock, return_value=[]
    ) as mock_get_messages, patch(
        "fastapi_app.api.test_connection", new_callable=AsyncMock, return_value=True
    ) as _:
        yield {
            "create_session": mock_create,
            "get_session": mock_get,
            "add_message": mock_add,
            "get_session_messages": mock_get_messages,
        }


@pytest.fixture
def mock_graph_utils():
    """Mocks all functions in the graph_utils module."""
    with patch("fastapi_app.api.initialize_graph", new_callable=AsyncMock) as _, patch(
        "fastapi_app.api.close_graph", new_callable=AsyncMock
    ) as _, patch(
        "fastapi_app.api.test_graph_connection",
        new_callable=AsyncMock,
        return_value=True,
    ) as _:
        yield


@pytest.fixture
def mock_agent_execution():
    """Mocks the core agent execution logic."""
    with patch("fastapi_app.api.execute_agent", new_callable=AsyncMock) as mock_execute:
        mock_execute.return_value = (
            "Mocked AI response",
            [{"tool_name": "vector_search", "args": {"query": "Hello"}}],
        )
        yield mock_execute


@pytest.fixture
def mock_tools():
    """Mocks the individual search tools."""
    with patch(
        "fastapi_app.api.vector_search_tool",
        new_callable=AsyncMock,
        return_value=[
            ChunkResult(
                chunk_id="1",
                document_id="doc1",
                content="vector search result",
                score=0.9,
                document_title="Doc 1",
                document_source="src1",
            )
        ],
    ) as mock_vector, patch(
        "fastapi_app.api.graph_search_tool",
        new_callable=AsyncMock,
        return_value=[GraphSearchResult(fact="graph search result", uuid="uuid1")],
    ) as mock_graph, patch(
        "fastapi_app.api.hybrid_search_tool",
        new_callable=AsyncMock,
        return_value=[
            ChunkResult(
                chunk_id="1",
                document_id="doc1",
                content="hybrid search result",
                score=0.9,
                document_title="Doc 1",
                document_source="src1",
            )
        ],
    ) as mock_hybrid:
        yield {"vector": mock_vector, "graph": mock_graph, "hybrid": mock_hybrid}


# --- API Tests ---


async def test_health_check(mock_db_utils, mock_graph_utils):
    response = client.get("/health")
    assert response.status_code == 200
    json_data = response.json()
    assert json_data["status"] == "healthy"
    assert json_data["database"] is True
    assert json_data["graph_database"] is True


async def test_chat_endpoint_creates_session(
    mock_db_utils, mock_agent_execution, auth_headers
):
    mock_db_utils["get_session"].return_value = None  # Simulate no existing session
    response = client.post("/chat", headers=auth_headers, json={"message": "Hello"})
    assert response.status_code == 200
    mock_db_utils["create_session"].assert_called_once()
    mock_agent_execution.assert_called_once()
    assert response.json()["session_id"] == "new-session-123"


async def test_chat_endpoint_uses_existing_session(
    mock_db_utils, mock_agent_execution, auth_headers
):
    response = client.post(
        "/chat",
        headers=auth_headers,
        json={"message": "Hello again", "session_id": "existing-session-456"},
    )
    assert response.status_code == 200
    mock_db_utils["get_session"].assert_called_with("existing-session-456")
    mock_db_utils["create_session"].assert_not_called()
    mock_agent_execution.assert_called_once()
    assert response.json()["session_id"] == "existing-session-456"
    assert response.json()["tools_used"][0]["tool_name"] == "vector_search"


async def test_chat_stream_endpoint(mock_db_utils, auth_headers):
    # Mock the agent's streaming logic
    with patch("fastapi_app.api.rag_agent.iter") as mock_iter:

        async def mock_streamer(*args, **kwargs):
            yield f"data: {json.dumps({'type': 'session', 'session_id': 'stream-session-789'})}\n\n"
            yield f"data: {json.dumps({'type': 'text', 'content': 'Hello '})}\n\n"
            yield f"data: {json.dumps({'type': 'text', 'content': 'World!'})}\n\n"
            yield f"data: {json.dumps({'type': 'tools', 'tools': [{'tool_name': 'test_tool'}]})}\n\n"
            yield f"data: {json.dumps({'type': 'end'})}\n\n"

        mock_iter.return_value.__aenter__.return_value = mock_streamer()  # type: ignore

        response = client.post(
            "/chat/stream", headers=auth_headers, json={"message": "stream test"}
        )
        assert response.status_code == 200
        # In a real test client, you would iterate over the streaming response
        # Here we just confirm the endpoint is reachable and returns a streaming content type
        assert "text/event-stream" in response.headers["content-type"]


async def test_vector_search_endpoint(mock_tools, auth_headers):
    with patch(
        "fastapi_app.tools.generate_embedding",
        new_callable=AsyncMock,
        return_value=[0.1] * 1536,
    ):
        response = client.post(
            "/search/vector", headers=auth_headers, json={"query": "test"}
        )
        assert response.status_code == 200
        json_data = response.json()
        assert json_data["search_type"] == "vector"
        assert len(json_data["results"]) == 1
        assert json_data["results"][0]["content"] == "vector search result"
        mock_tools["vector"].assert_called_once()


async def test_graph_search_endpoint(mock_tools, auth_headers):
    response = client.post(
        "/search/graph", headers=auth_headers, json={"query": "test"}
    )
    assert response.status_code == 200
    json_data = response.json()
    assert json_data["search_type"] == "graph"
    assert len(json_data["graph_results"]) == 1
    assert json_data["graph_results"][0]["fact"] == "graph search result"
    mock_tools["graph"].assert_called_once()


async def test_hybrid_search_endpoint(mock_tools, auth_headers):
    with patch(
        "fastapi_app.tools.generate_embedding",
        new_callable=AsyncMock,
        return_value=[0.1] * 1536,
    ):
        response = client.post(
            "/search/hybrid", headers=auth_headers, json={"query": "test"}
        )
        assert response.status_code == 200
        json_data = response.json()
        assert json_data["search_type"] == "hybrid"
        assert len(json_data["results"]) == 1
        assert json_data["results"][0]["content"] == "hybrid search result"
        mock_tools["hybrid"].assert_called_once()
