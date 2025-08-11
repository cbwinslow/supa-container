import os


from fastapi_app.api import app
from fastapi_app.models import ChunkResult, GraphSearchResult, DocumentMetadata

# Use pytest-asyncio for async tests
pytestmark = pytest.mark.asyncio

client = TestClient(app)

# --- Mocks and Fixtures ---



@pytest.fixture
def mock_db_utils():
    """
    Pytest fixture that patches database-related functions used by the API and yields their mocks.
    
    Patches (as AsyncMock) initialize_database, close_database, create_session, get_session, add_message,
    get_session_messages, and test_connection in fastapi_app.api. Provides configured return values for
    create_session ("new-session-123"), get_session ({"id": "existing-session-456"}), get_session_messages ([]),
    and test_connection (True). Yields a dict with keys "create_session", "get_session", "add_message", and
    "get_session_messages" mapped to their respective AsyncMock objects for use in assertions.
    """
    with patch(
        "fastapi_app.api.initialize_database", new_callable=AsyncMock

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

        yield {
            "create_session": mock_create,
            "get_session": mock_get,
            "add_message": mock_add,
            "get_session_messages": mock_get_messages,
        }



        yield


@pytest.fixture
def mock_agent_execution():
    """
    Pytest fixture that patches fastapi_app.api.execute_agent with an AsyncMock.
    
    The mock is configured to return a two-element tuple: a string ("Mocked AI response")
    and a list of tool-usage dictionaries ([{"tool_name": "vector_search", "args": {"query": "Hello"}}]).
    Yields the AsyncMock so tests can assert calls and adjust return_value if needed.
    """
    with patch("fastapi_app.api.execute_agent", new_callable=AsyncMock) as mock_execute:
        mock_execute.return_value = (
            "Mocked AI response",
            [{"tool_name": "vector_search", "args": {"query": "Hello"}}],
        )
        yield mock_execute


@pytest.fixture
def mock_tools():
    """
    Pytest fixture that patches the three search tools (vector, graph, hybrid) and yields their mocks.
    
    Each patched tool is an AsyncMock returning deterministic results:
    - vector: a single ChunkResult with content "vector search result".
    - graph: a single GraphSearchResult with fact "graph search result".
    - hybrid: a single ChunkResult with content "hybrid search result".
    
    Yields:
        dict: {'vector': mock_vector, 'graph': mock_graph, 'hybrid': mock_hybrid} — the AsyncMock objects for assertions.
    """
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



    assert response.status_code == 200
    mock_db_utils["create_session"].assert_called_once()
    mock_agent_execution.assert_called_once()
    assert response.json()["session_id"] == "new-session-123"



    assert response.status_code == 200
    mock_db_utils["get_session"].assert_called_with("existing-session-456")
    mock_db_utils["create_session"].assert_not_called()
    mock_agent_execution.assert_called_once()
    assert response.json()["session_id"] == "existing-session-456"
    assert response.json()["tools_used"][0]["tool_name"] == "vector_search"


    # Mock the agent's streaming logic
    with patch("fastapi_app.api.rag_agent.iter") as mock_iter:

        async def mock_streamer(*args, **kwargs):
            """
            Async test streamer that yields a fixed sequence of Server-Sent Events (SSE)-formatted strings.
            
            Yields five SSE `data:` events (as strings), in order:
            1. A `session` event with session_id "stream-session-789".
            2. A `text` event with content "Hello ".
            3. A `text` event with content "World!".
            4. A `tools` event containing a tools list with one tool_name "test_tool".
            5. An `end` event.
            
            Each yielded value is a complete SSE data frame (JSON payload prefixed with "data: " and terminated by a double newline). Intended for use in tests that consume streaming responses.
            """
            yield f"data: {json.dumps({'type': 'session', 'session_id': 'stream-session-789'})}\n\n"
            yield f"data: {json.dumps({'type': 'text', 'content': 'Hello '})}\n\n"
            yield f"data: {json.dumps({'type': 'text', 'content': 'World!'})}\n\n"
            yield f"data: {json.dumps({'type': 'tools', 'tools': [{'tool_name': 'test_tool'}]})}\n\n"
            yield f"data: {json.dumps({'type': 'end'})}\n\n"

        assert response.status_code == 200
        # In a real test client, you would iterate over the streaming response
        # Here we just confirm the endpoint is reachable and returns a streaming content type
        assert "text/event-stream" in response.headers["content-type"]



        assert response.status_code == 200
        json_data = response.json()
        assert json_data["search_type"] == "vector"
        assert len(json_data["results"]) == 1
        assert json_data["results"][0]["content"] == "vector search result"
        mock_tools["vector"].assert_called_once()



    assert response.status_code == 200
    json_data = response.json()
    assert json_data["search_type"] == "graph"
    assert len(json_data["graph_results"]) == 1
    assert json_data["graph_results"][0]["fact"] == "graph search result"
    mock_tools["graph"].assert_called_once()



        assert response.status_code == 200
        json_data = response.json()
        assert json_data["search_type"] == "hybrid"
        assert len(json_data["results"]) == 1
        assert json_data["results"][0]["content"] == "hybrid search result"
        mock_tools["hybrid"].assert_called_once()



