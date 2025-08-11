"""Flexible provider configuration for LLM and embedding models."""

import os
import openai
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.models.openai import OpenAIModel


def get_llm_model(model_choice: str = None):
    """Get the LLM model."""
    llm_choice = model_choice or os.getenv("LLM_CHOICE", "gpt-4-turbo-preview")
    provider = OpenAIProvider(
        api_key=os.getenv("LLM_API_KEY"),
        base_url=os.getenv("LLM_BASE_URL", "https://api.openai.com/v1"),
    )
    return OpenAIModel(llm_choice, provider=provider)


def get_embedding_client():
    """Get the embedding client."""
    return openai.AsyncOpenAI(
        api_key=os.getenv("EMBEDDING_API_KEY", os.getenv("LLM_API_KEY")),
        base_url=os.getenv("EMBEDDING_BASE_URL", "https://api.openai.com/v1"),
    )


def get_embedding_model():
    """Get the embedding model name."""
    return os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")


def get_ingestion_model():
    """Get the ingestion model."""
    ingestion_choice = os.getenv("INGESTION_LLM_CHOICE")
    if not ingestion_choice:
        return get_llm_model()
    return get_llm_model(model_choice=ingestion_choice)


# Provider information functions

def get_llm_provider() -> str:
    """Get the LLM provider name."""
    return os.getenv("LLM_PROVIDER", "openai")


def get_embedding_provider() -> str:
    """Get the embedding provider name."""
    return os.getenv("EMBEDDING_PROVIDER", "openai")


def get_model_info() -> dict:
    """Get information about current model configuration."""
    return {
        "llm_provider": get_llm_provider(),
        "embedding_provider": get_embedding_provider(),
        "llm_model": os.getenv("LLM_CHOICE", "gpt-4-turbo-preview"),
        "embedding_model": os.getenv("EMBEDDING_MODEL", "text-embedding-3-small"),
    }
