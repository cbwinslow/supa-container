"""Flexible provider configuration for LLM and embedding models."""


from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.models.openai import OpenAIModel


    return OpenAIModel(llm_choice, provider=provider)


def get_embedding_client() -> openai.AsyncOpenAI:

    if not ingestion_choice:
        return get_llm_model()
    return get_llm_model(model_choice=ingestion_choice)


# Provider information functions

def get_llm_provider() -> str:
    """Get the LLM provider name."""



def get_embedding_provider() -> str:
    """Get the embedding provider name."""


def get_model_info() -> dict:
    """Get information about current model configuration."""
    return {
        "llm_provider": get_llm_provider(),

    }
