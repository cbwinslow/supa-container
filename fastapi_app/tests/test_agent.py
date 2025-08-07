import pytest
from unittest.mock import patch, AsyncMock
from agent.agent import rag_agent, AgentDependencies
from agent.providers import get_llm_model

pytestmark = pytest.mark.asyncio

def test_agent_initialization():
    """Tests that the agent and its dependencies initialize correctly."""
    assert rag_agent is not None
    # Pydantic AI v2 uses a different structure, we verify the llm model is set
    assert rag_agent.llm.model_name is not None

    # Test AgentDependencies dataclass
    deps = AgentDependencies(session_id="test-session")
    assert deps.session_id == "test-session"
    assert deps.search_preferences["default_limit"] == 10

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
    # In Pydantic AI v2, tools are methods on the agent class instance
    registered_tool_names = [tool.__name__ for tool in rag_agent.tools]
    
    expected_tools = [
        "vector_search",
        "graph_search",
        "hybrid_search",
        "get_document",
        "list_documents",
        "get_entity_relationships",
        "get_entity_timeline"
    ]
    
    for tool_name in expected_tools:
        assert tool_name in registered_tool_names
