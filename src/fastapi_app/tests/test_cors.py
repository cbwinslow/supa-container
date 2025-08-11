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

    import fastapi_app.api as api_module
    importlib.reload(api_module)
    return api_module


def _get_cors_origins(app):



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

