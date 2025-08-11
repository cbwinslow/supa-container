"""Flexible provider configuration for LLM and embedding models."""


from typing import Optional
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.models.openai import OpenAIModel
import openai





def get_llm_model(model_choice: Optional[str] = None) -> OpenAIModel:
    """
    Get LLM model configuration based on environment variables.

    Args:
        model_choice: Optional override for model choice

    Returns:
        Configured OpenAI-compatible model
    """

    provider = OpenAIProvider(base_url=base_url, api_key=api_key)
    return OpenAIModel(llm_choice, provider=provider)


def get_embedding_client() -> openai.AsyncOpenAI:
    """
    Get embedding client configuration based on environment variables.

    Returns:
        Configured OpenAI-compatible client for embeddings
    """



def get_embedding_model() -> str:
    """
    Get embedding model name from environment.

    Returns:
        Embedding model name
    """



def get_ingestion_model() -> OpenAIModel:
    """
    Get ingestion-specific LLM model (can be faster/cheaper than main model).

    Returns:
        Configured model for ingestion tasks
    """

    # If no specific ingestion model, use the main model
    if not ingestion_choice:
        return get_llm_model()

    return get_llm_model(model_choice=ingestion_choice)


# Provider information functions
def get_llm_provider() -> str:
    """Get the LLM provider name."""



def get_embedding_provider() -> str:
    """Get the embedding provider name."""



def validate_configuration() -> bool:
    """
    Validate that required environment variables are set.

    Returns:

    """



    return True

def get_model_info() -> dict:
    """
    Get information about current model configuration.

    Returns:
        Dictionary with model configuration info
    """
    return {
        "llm_provider": get_llm_provider(),


    }
