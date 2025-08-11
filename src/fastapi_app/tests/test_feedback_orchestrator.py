import pytest
from typing import Dict, Any, List

from fastapi_app.feedback_orchestrator import FeedbackOrchestrator, LLMProvider


class DummyProvider:
    """Simple provider used for testing."""

    async def analyse(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Async test stub that analyses input and always returns a fixed plan.
        
        Parameters:
            data (Dict[str, Any]): Arbitrary input data (ignored).
        
        Returns:
            Dict[str, Any]: A constant plan dict: {"plan": "ok"}.
        """
        return {"plan": "ok"}

    async def deploy_agents(self, plan: Dict[str, Any]) -> List[str]:
        """
        Validate the provided plan and return the IDs of deployed agents.
        
        Parameters:
            plan (Dict[str, Any]): Expected planning result. This function asserts that `plan == {"plan": "ok"}`.
        
        Returns:
            List[str]: A list of deployed agent identifiers (e.g. ["agent-1"]).
        
        Raises:
            AssertionError: If `plan` does not equal `{"plan": "ok"}`.
        """
        assert plan == {"plan": "ok"}
        return ["agent-1"]


@pytest.mark.asyncio
async def test_orchestrator_heal_flow():
    orchestrator = FeedbackOrchestrator(provider=DummyProvider())
    agents = await orchestrator.heal()
    assert agents == ["agent-1"]
