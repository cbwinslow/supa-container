import importlib
import pytest


def _reload_api(monkeypatch, origins=None):
    if origins is None:
        monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    else:
        monkeypatch.setenv("ALLOWED_ORIGINS", origins)
    monkeypatch.setenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/db")
    monkeypatch.setenv("NEO4J_PASSWORD", "dummy")
    monkeypatch.setenv("LLM_API_KEY", "dummy")
# Test environment variable constants
DATABASE_URL = "postgresql://user:pass@localhost:5432/db"
NEO4J_PASSWORD = "dummy"
LLM_API_KEY = "dummy"
EMBEDDING_API_KEY = "dummy"

def _reload_api(monkeypatch, origins=None):
    if origins is None:
        monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    else:
        monkeypatch.setenv("ALLOWED_ORIGINS", origins)
    monkeypatch.setenv("DATABASE_URL", DATABASE_URL)
    monkeypatch.setenv("NEO4J_PASSWORD", NEO4J_PASSWORD)
    monkeypatch.setenv("LLM_API_KEY", LLM_API_KEY)
    monkeypatch.setenv("EMBEDDING_API_KEY", EMBEDDING_API_KEY)
    import fastapi_app.api as api_module
    importlib.reload(api_module)
    return api_module


def _get_cors_origins(app):
    return next(
        (
            m.kwargs.get("allow_origins")
            for m in app.user_middleware
            if m.cls.__name__ == "CORSMiddleware"
        ),
        None,
    )


def test_cors_default_blocks(monkeypatch):
    api_module = _reload_api(monkeypatch)
    assert _get_cors_origins(api_module.app) == []


def test_cors_env_allows_list(monkeypatch):
    api_module = _reload_api(monkeypatch, "https://example.com, https://foo.com")
    assert _get_cors_origins(api_module.app) == [
        "https://example.com",
        "https://foo.com",
    ]
    # Reset module to default state for other tests
    _reload_api(monkeypatch)
