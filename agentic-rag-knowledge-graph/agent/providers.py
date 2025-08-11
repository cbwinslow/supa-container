"""Flexible provider configuration for LLM and embedding models."""

from typing import Optional
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.models.openai import OpenAIModel
import openai

from ..settings import settings


def get_llm_model(model_choice: Optional[str] = None) -> OpenAIModel:
    """
    Get LLM model configuration based on environment variables.
    
    Args:
        model_choice: Optional override for model choice
    
    Returns:
        Configured OpenAI-compatible model
    """
    llm_choice = model_choice or settings.llm_choice
    base_url = settings.llm_base_url
    api_key = settings.llm_api_key
    
    provider = OpenAIProvider(base_url=base_url, api_key=api_key)
    return OpenAIModel(llm_choice, provider=provider)


def get_embedding_client() -> openai.AsyncOpenAI:
    """
    Get embedding client configuration based on environment variables.
    
    Returns:
        Configured OpenAI-compatible client for embeddings
    """
    base_url = settings.embedding_base_url
    api_key = settings.embedding_api_key or settings.llm_api_key
    
    return openai.AsyncOpenAI(
        base_url=base_url,
        api_key=api_key
    )


def get_embedding_model() -> str:
    """
    Get embedding model name from environment.
    
    Returns:
        Embedding model name
    """
    return settings.embedding_model


def get_ingestion_model() -> OpenAIModel:
    """
    Get ingestion-specific LLM model (can be faster/cheaper than main model).
    
    Returns:
        Configured model for ingestion tasks
    """
    ingestion_choice = settings.ingestion_llm_choice
    
    # If no specific ingestion model, use the main model
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
    """
    Validate that required environment variables are set.
    
    Returns:
        True if configuration is valid
    """
    required_vars = {
        'LLM_API_KEY': settings.llm_api_key,
        'LLM_CHOICE': settings.llm_choice,
        'EMBEDDING_API_KEY': settings.embedding_api_key or settings.llm_api_key,
        'EMBEDDING_MODEL': settings.embedding_model,
    }

    missing_vars = [name for name, value in required_vars.items() if not value]
    
    if missing_vars:
        print(f"Missing required environment variables: {', '.join(missing_vars)}")
        return False
    
    return True


def get_model_info() -> dict:
    """
    Get information about current model configuration.
    
    Returns:
        Dictionary with model configuration info
    """
    return {
        "llm_provider": get_llm_provider(),
        "llm_model": settings.llm_choice,
        "llm_base_url": settings.llm_base_url,
        "embedding_provider": get_embedding_provider(),
        "embedding_model": get_embedding_model(),
        "embedding_base_url": settings.embedding_base_url,
        "ingestion_model": settings.ingestion_llm_choice or 'same as main',
    }