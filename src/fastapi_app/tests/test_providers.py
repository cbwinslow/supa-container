import pytest
import os
from unittest.mock import patch
from fastapi_app.providers import get_llm_model, get_embedding_client, get_embedding_model, validate_configuration

def test_get_llm_model_default():
    """Tests that the default LLM model is configured correctly."""
    with patch.dict(os.environ, {"LLM_CHOICE": "gpt-test", "LLM_BASE_URL": "http://test.local", "LLM_API_KEY": "test-key"}):
        model = get_llm_model()
        assert model.model == "gpt-test"
        assert model.client.base_url == "http://test.local"

def test_get_llm_model_override():
    """Tests that the model choice can be overridden."""
    with patch.dict(os.environ, {"LLM_CHOICE": "gpt-default", "LLM_BASE_URL": "http://test.local", "LLM_API_KEY": "test-key"}):
        model = get_llm_model(model_choice="gpt-override")
        assert model.model == "gpt-override"

def test_get_embedding_client():
    """Tests that the embedding client is configured correctly from env vars."""
    with patch.dict(os.environ, {"EMBEDDING_BASE_URL": "http://embed.local", "EMBEDDING_API_KEY": "embed-key"}):
        client = get_embedding_client()
        assert client.base_url == "http://embed.local"
        assert client.api_key == "embed-key"

def test_get_embedding_model():
    """Tests that the embedding model name is retrieved correctly."""
    with patch.dict(os.environ, {"EMBEDDING_MODEL": "embed-test-model"}):
        model_name = get_embedding_model()
        assert model_name == "embed-test-model"

def test_validate_configuration_success():
    """Tests that validation passes when all required env vars are set."""
    with patch.dict(os.environ, {
        "LLM_API_KEY": "key1",
        "LLM_CHOICE": "model1",
        "EMBEDDING_API_KEY": "key2",
        "EMBEDDING_MODEL": "model2"
    }):
        assert validate_configuration() is True

def test_validate_configuration_failure():
    """Tests that validation fails when env vars are missing."""
    with patch.dict(os.environ, {}, clear=True):
        assert validate_configuration() is False
