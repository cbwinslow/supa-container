import pytest
from typing import Dict, Any, List

from fastapi_app.feedback_orchestrator import FeedbackOrchestrator, LLMProvider


class DummyProvider:
    """Simple provider used for testing."""

    async def analyse(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return {"plan": "ok"}

    async def deploy_agents(self, plan: Dict[str, Any]) -> List[str]:
        assert plan == {"plan": "ok"}
        return ["agent-1"]


@pytest.mark.asyncio
async def test_orchestrator_heal_flow():
    orchestrator = FeedbackOrchestrator(provider=DummyProvider())
    agents = await orchestrator.heal()
    assert agents == ["agent-1"]
