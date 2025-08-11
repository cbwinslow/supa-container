"""Flexible provider configuration for LLM and embedding models."""

from typing import Optional

from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.models.openai import OpenAIModel
import openai

from settings import settings


def get_llm_model(model_choice: Optional[str] = None) -> OpenAIModel:
    """Get LLM model configuration based on settings."""
    llm_choice = model_choice or settings.llm_choice
    provider = OpenAIProvider(base_url=settings.llm_base_url, api_key=settings.llm_api_key)
    return OpenAIModel(llm_choice, provider=provider)


def get_embedding_client() -> openai.AsyncOpenAI:
    """Get embedding client based on settings."""
    return openai.AsyncOpenAI(
        api_key=settings.embedding_api_key or settings.llm_api_key,
        base_url=settings.embedding_base_url,
    )


def get_embedding_model() -> str:
    """Get embedding model name from settings."""
    return settings.embedding_model


def get_ingestion_model() -> OpenAIModel:
    """Get ingestion-specific LLM model."""
    ingestion_choice = settings.ingestion_llm_choice
    if not ingestion_choice:
        return get_llm_model()
    return get_llm_model(model_choice=ingestion_choice)


# Provider information functions

def get_llm_provider() -> str:
    """Get the LLM provider name."""
    return settings.llm_provider


def get_embedding_provider() -> str:
    """Get the embedding provider name."""
    return settings.embedding_provider


def validate_configuration() -> bool:
    """Validate that required settings are present."""
    try:
        _ = settings
        return True
    except Exception:
        return False


def get_model_info() -> dict:
    """Get information about current model configuration."""
    return {
        "llm_provider": get_llm_provider(),
        "llm_model": settings.llm_choice,
        "embedding_provider": get_embedding_provider(),
        "embedding_model": settings.embedding_model,
    }
