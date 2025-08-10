import pytest
from pydantic import ValidationError
from fastapi_app.models import ChatRequest, SearchRequest, IngestionConfig, SearchType

def test_chat_request_model():
    """Tests the ChatRequest model for valid and invalid data."""
    # Valid data
    data = {"message": "Hello", "session_id": "123", "search_type": "vector"}
    req = ChatRequest(**data)
    assert req.message == "Hello"
    assert req.search_type == SearchType.VECTOR

    # Invalid search_type
    with pytest.raises(ValidationError):
        ChatRequest(message="Hello", search_type="invalid_type")

    # Missing message
    with pytest.raises(ValidationError):
        ChatRequest(session_id="123")

def test_search_request_model_limits():
    """Tests the validation on the limit field of the SearchRequest model."""
    # Valid limit
    req = SearchRequest(query="test", limit=10)
    assert req.limit == 10

    # Limit too low
    with pytest.raises(ValidationError):
        SearchRequest(query="test", limit=0)

    # Limit too high
    with pytest.raises(ValidationError):
        SearchRequest(query="test", limit=51)

def test_ingestion_config_validation():
    """Tests the validation logic in the IngestionConfig model."""
    # Valid config
    config = IngestionConfig(chunk_size=1000, chunk_overlap=200)
    assert config.chunk_overlap == 200

    # Invalid overlap (equal to chunk_size)
    with pytest.raises(ValidationError):
        IngestionConfig(chunk_size=1000, chunk_overlap=1000)

    # Invalid overlap (greater than chunk_size)
    with pytest.raises(ValidationError):
        IngestionConfig(chunk_size=1000, chunk_overlap=1200)
