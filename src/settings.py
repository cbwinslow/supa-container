from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    llm_api_key: str
    database_url: str

    llm_choice: str = "gpt-4-turbo-preview"
    llm_base_url: str = "https://api.openai.com/v1"
    llm_provider: str = "openai"

    embedding_api_key: str | None = None
    embedding_base_url: str = "https://api.openai.com/v1"
    embedding_model: str = "text-embedding-3-small"
    embedding_provider: str = "openai"

    ingestion_llm_choice: str | None = None

    app_env: str = "development"
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    log_level: str = "INFO"
    api_auth_token: str
    allowed_origins: list[str] = Field(default_factory=list)

    neo4j_uri: str = "bolt://localhost:7687"
    neo4j_user: str = "neo4j"
    neo4j_password: str | None = None

    vector_dimension: int = 1536

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def split_origins(cls, v: str | list[str]) -> list[str]:
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)

settings = Settings()
