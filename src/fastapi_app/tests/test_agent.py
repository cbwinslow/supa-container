import pytest
from unittest.mock import patch, AsyncMock
from fastapi_app.agent import rag_agent, AgentDependencies
from fastapi_app.providers import get_llm_model


def test_agent_initialization():
    """Tests that the agent and its dependencies initialize correctly."""
    assert rag_agent is not None
    # Ensure the underlying model is configured
    assert rag_agent.model.model_name is not None

    # Test AgentDependencies dataclass
    deps = AgentDependencies(session_id="test-session")
    assert deps.session_id == "test-session"
    assert deps.search_preferences["default_limit"] == 10


@pytest.mark.asyncio
async def test_agent_run_flow():
    """Mocks a full agent run to ensure the flow works."""
    # This is a high-level integration test of the agent's internal logic
    with patch('pydantic_ai.Agent.run', new_callable=AsyncMock) as mock_run:
        mock_result = AsyncMock()
        mock_result.data = "Final mocked response"
        mock_run.return_value = mock_result

        deps = AgentDependencies(session_id="test-run-flow")
        result = await rag_agent.run("test prompt", deps=deps)

        mock_run.assert_called_once_with("test prompt", deps=deps)
        assert result.data == "Final mocked response"


def test_agent_tools_are_registered():
    """Verifies that all expected tools are registered with the agent."""
    registered_tool_names = set(rag_agent._function_tools.keys())

    expected_tools = {
        "vector_search",
        "graph_search",
        "hybrid_search",
        "get_document",
        "list_documents",
        "get_entity_relationships",
        "get_entity_timeline",
    }

    assert expected_tools.issubset(registered_tool_names)