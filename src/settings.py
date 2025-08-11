from pydantic import BaseSettings, Field

class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    llm_api_key: str = Field(..., env="LLM_API_KEY")
    database_url: str = Field(..., env="DATABASE_URL")

    llm_choice: str = Field("gpt-4-turbo-preview", env="LLM_CHOICE")
    llm_base_url: str = Field("https://api.openai.com/v1", env="LLM_BASE_URL")
    llm_provider: str = Field("openai", env="LLM_PROVIDER")

    embedding_api_key: str | None = Field(None, env="EMBEDDING_API_KEY")
    embedding_base_url: str = Field("https://api.openai.com/v1", env="EMBEDDING_BASE_URL")
    embedding_model: str = Field("text-embedding-3-small", env="EMBEDDING_MODEL")
    embedding_provider: str = Field("openai", env="EMBEDDING_PROVIDER")

    ingestion_llm_choice: str | None = Field(None, env="INGESTION_LLM_CHOICE")

    app_env: str = Field("development", env="APP_ENV")
    app_host: str = Field("0.0.0.0", env="APP_HOST")
    app_port: int = Field(8000, env="APP_PORT")
    log_level: str = Field("INFO", env="LOG_LEVEL")

    neo4j_uri: str = Field("bolt://localhost:7687", env="NEO4J_URI")
    neo4j_user: str = Field("neo4j", env="NEO4J_USER")
    neo4j_password: str | None = Field(None, env="NEO4J_PASSWORD")

    vector_dimension: int = Field(1536, env="VECTOR_DIMENSION")

    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()
