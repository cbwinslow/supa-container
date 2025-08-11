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
    monkeypatch.setenv("EMBEDDING_API_KEY", "dummy")
    import fastapi_app.api as api_module
    importlib.reload(api_module)
    return api_module


def _get_cors_origins(app):
    for m in app.user_middleware:
        if m.cls.__name__ == "CORSMiddleware":
            return m.kwargs.get("allow_origins")
    return None


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
def test_cors_default_blocks(api_module_fixture):
    api_module = api_module_fixture
    assert _get_cors_origins(api_module.app) == []


@pytest.mark.parametrize("api_module_fixture", ["https://example.com, https://foo.com"], indirect=True)
def test_cors_env_allows_list(api_module_fixture):
    api_module = api_module_fixture
    assert _get_cors_origins(api_module.app) == [
        "https://example.com",
        "https://foo.com",
    ]
