import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock
from agent.api import app

client = TestClient(app)

@pytest.fixture
def mock_agent_execution():
    with patch('agent.api.execute_agent', new_callable=AsyncMock) as mock_execute:
        mock_execute.return_value = ("Mocked AI response", [])
        yield mock_execute

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_chat_endpoint(mock_agent_execution):
    response = client.post("/chat", json={"message": "Hello"})
    assert response.status_code == 200
    json_response = response.json()
    assert json_response["message"] == "Mocked AI response"
    assert "session_id" in json_response
    mock_agent_execution.assert_called_once()

# Add more tests for streaming, search endpoints, etc.
