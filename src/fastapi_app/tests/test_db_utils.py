import sys
import types
import json
import importlib
from datetime import datetime, timedelta, timezone

import os
import pytest

# Note: Testing library/framework in use: Pytest with pytest-asyncio for async test support.

# Utilities to create a fake asyncpg pool and connection
class FakeConnection:
    def __init__(self):
        # allow tests to program the next results
        self._fetchrow_result = None
        self._fetch_results = None
        self._execute_result = "UPDATE 1"
        self._fetchval_result = 1
        self._queries = []

    def program_fetchrow(self, result):
        self._fetchrow_result = result

    def program_fetch(self, results):
        self._fetch_results = results

    def program_execute(self, result):
        self._execute_result = result

    def program_fetchval(self, result):
        self._fetchval_result = result

    @property
    def queries(self):
        return list(self._queries)

    async def fetchrow(self, query, *params):
        self._queries.append(("fetchrow", query, params))
        return self._fetchrow_result

    async def fetch(self, query, *params):
        self._queries.append(("fetch", query, params))
        # Support the vector_search/hybrid_search where query may be plain SQL with params supplied to fetch
        return self._fetch_results or []

    async def execute(self, query, *params):
        self._queries.append(("execute", query, params))
        return self._execute_result

    async def fetchval(self, query, *params):
        self._queries.append(("fetchval", query, params))
        return self._fetchval_result


class _AcquireCM:
    def __init__(self, conn):
        self._conn = conn

    async def __aenter__(self):
        return self._conn

    async def __aexit__(self, exc_type, exc, tb):
        return False


class FakePool:
    def __init__(self, conn: FakeConnection):
        self._conn = conn
        self.closed = False
        self.acquire_calls = 0

    async def close(self):
        self.closed = True

    def acquire(self):
        self.acquire_calls += 1
        return _AcquireCM(self._conn)


@pytest.fixture
def set_env(monkeypatch):
    # Ensure module import succeeds; DatabasePool() requires DATABASE_URL to exist
    monkeypatch.setenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/testdb")
    monkeypatch.setenv("API_AUTH_TOKEN", "secret-token")


@pytest.fixture
def fake_pg(monkeypatch):
    """
    Patch asyncpg.create_pool to return a controllable FakePool instance.
    Returns (fake_pool, fake_conn).
    """
    conn = FakeConnection()
    pool = FakePool(conn)

    async def _create_pool(url, min_size=5, max_size=20, max_inactive_connection_lifetime=300, command_timeout=60):
        # Validate arguments passed
        assert isinstance(url, str) and url.startswith("postgresql://")
        return pool

    # If asyncpg module isn't installed in this environment, create a stub
    if "asyncpg" not in sys.modules:
        asyncpg_stub = types.SimpleNamespace()
        async def _dummy():  # pragma: no cover - guard
            pass
        asyncpg_stub.create_pool = _create_pool
        sys.modules["asyncpg"] = asyncpg_stub
    else:
        import asyncpg  # type: ignore
        monkeypatch.setattr(asyncpg, "create_pool", _create_pool)

    return pool, conn


@pytest.fixture
def db_utils_module(set_env, fake_pg, monkeypatch):
    """
    Import the module under test with environment and asyncpg patched.
    """
    # Determine import path heuristically: prefer fastapi_app.db_utils if available.
    module = None
    candidates = [
        "fastapi_app.db_utils",
        "src.fastapi_app.db_utils",
        "db_utils",
    ]
    last_err = None
    for name in candidates:
        try:
            if name in sys.modules:
                module = importlib.reload(sys.modules[name])
            else:
                module = importlib.import_module(name)
            break
        except Exception as e:  # capture and continue trying
            last_err = e
            continue
    if module is None:
        # As a fallback, attempt relative import by manipulating sys.path
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        if repo_root not in sys.path:
            sys.path.insert(0, repo_root)
        try:
            module = importlib.import_module("fastapi_app.db_utils")
        except Exception as e:
            raise AssertionError(f"Could not import db_utils module via known names; last error: {last_err}") from e

    return module


@pytest.mark.asyncio
async def test_verify_auth_token_matches(db_utils_module, monkeypatch):
    assert await db_utils_module.verify_auth_token("secret-token") is True


@pytest.mark.asyncio
async def test_verify_auth_token_missing_env(monkeypatch):
    # Remove API_AUTH_TOKEN to exercise warning path
    monkeypatch.delenv("API_AUTH_TOKEN", raising=False)
    # Re-import module to avoid cached env inside verify function (function reads os.getenv each call; reimport not required)
    # Just call directly:
    from fastapi_app import db_utils as m
    assert await m.verify_auth_token("anything") is False


@pytest.mark.asyncio
async def test_database_pool_initialize_and_close(db_utils_module, fake_pg):
    pool, conn = fake_pg
    db_pool = db_utils_module.DatabasePool(os.getenv("DATABASE_URL"))
    assert db_pool.pool is None
    await db_pool.initialize()
    assert db_pool.pool is pool
    await db_pool.close()
    assert db_pool.pool is None
    assert pool.closed is True


@pytest.mark.asyncio
async def test_acquire_context_manager_initializes_on_demand(db_utils_module, fake_pg):
    pool, conn = fake_pg
    # Use global db_pool from module to verify lazy init path
    m = db_utils_module
    # Ensure it's a DatabasePool and not initialized
    assert isinstance(m.db_pool, db_utils_module.DatabasePool)
    m.db_pool.pool = None
    async with m.db_pool.acquire() as c:
        assert c is conn
    assert pool.acquire_calls >= 1


@pytest.mark.asyncio
async def test_initialize_and_close_database_helpers(db_utils_module, fake_pg):
    m = db_utils_module
    m.db_pool.pool = None
    await m.initialize_database()
    assert m.db_pool.pool is fake_pg[0]
    await m.close_database()
    assert m.db_pool.pool is None


@pytest.mark.asyncio
async def test_create_session_inserts_and_returns_id(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    conn.program_fetchrow({"id": "11111111-1111-1111-1111-111111111111"})
    sid = await m.create_session(user_id="u1", metadata={"a": 1}, timeout_minutes=5)
    assert sid == "11111111-1111-1111-1111-111111111111"
    # Verify that metadata was json-dumped and expires_at computed
    ops = conn.queries
    assert any(op[0] == "fetchrow" and "INSERT INTO sessions" in op[1] for op in ops)
    # parameters: user_id, metadata JSON, expires_at
    for op in ops:
        if op[0] == "fetchrow" and "INSERT INTO sessions" in op[1]:
            _, q, params = op
            assert params[0] == "u1"
            # Validate JSON passed
            assert json.loads(params[1]) == {"a": 1}
            assert isinstance(params[2], datetime)


@pytest.mark.asyncio
async def test_get_session_when_found_and_when_expired(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    now = datetime.now(timezone.utc)
    # Found
    conn.program_fetchrow({
        "id": "abcd",
        "user_id": "userX",
        "metadata": json.dumps({"x": 2}),
        "created_at": now - timedelta(minutes=2),
        "updated_at": now - timedelta(minutes=1),
        "expires_at": now + timedelta(minutes=10),
    })
    data = await m.get_session("abcd")
    assert data["id"] == "abcd"
    assert data["user_id"] == "userX"
    assert data["metadata"] == {"x": 2}
    assert data["expires_at"] is not None

    # Not found (simulate None)
    conn.program_fetchrow(None)
    data2 = await m.get_session("nonexistent")
    assert data2 is None


@pytest.mark.asyncio
async def test_update_session_returns_bool(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    # Updated one row
    conn.program_execute("UPDATE 1")
    assert await m.update_session("sid", {"new": True}) is True
    # No rows affected
    conn.program_execute("UPDATE 0")
    assert await m.update_session("sid", {"new": True}) is False


@pytest.mark.asyncio
async def test_add_message_inserts_and_returns_id(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    conn.program_fetchrow({"id": "msg-1"})
    mid = await m.add_message("sid", role="user", content="hi", metadata={"lang": "en"})
    assert mid == "msg-1"
    # Verify JSON metadata
    seen = False
    for op in conn.queries:
        if op[0] == "fetchrow" and "INSERT INTO messages" in op[1]:
            seen = True
            assert json.loads(op[2][3]) == {"lang": "en"}
    assert seen


@pytest.mark.asyncio
async def test_get_session_messages_with_and_without_limit(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    now = datetime.now(timezone.utc)
    rows = [
        {"id": "m1", "role": "user", "content": "a", "metadata": json.dumps({}), "created_at": now - timedelta(seconds=2)},
        {"id": "m2", "role": "assistant", "content": "b", "metadata": json.dumps({"k": 1}), "created_at": now - timedelta(seconds=1)},
    ]
    conn.program_fetch(rows)
    res = await m.get_session_messages("sid")
    assert [r["id"] for r in res] == ["m1", "m2"]
    assert res[1]["metadata"] == {"k": 1}
    # With limit: ensure query string contains LIMIT; function appends if provided
    conn._queries.clear()
    conn.program_fetch(rows[:1])
    res2 = await m.get_session_messages("sid", limit=1)
    assert len(res2) == 1
    # The constructed SQL should contain LIMIT 1
    assert any("LIMIT 1" in q for (op, q, _) in conn.queries if op == "fetch")


@pytest.mark.asyncio
async def test_get_document_found_and_not_found(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    now = datetime.now(timezone.utc)
    conn.program_fetchrow({
        "id": "d1", "title": "T", "source": "S", "content": "C",
        "metadata": json.dumps({"a": 1}), "created_at": now, "updated_at": now
    })
    doc = await m.get_document("d1")
    assert doc["title"] == "T"
    assert doc["metadata"] == {"a": 1}

    conn.program_fetchrow(None)
    assert await m.get_document("nope") is None


@pytest.mark.asyncio
async def test_list_documents_with_and_without_metadata_filter(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    now = datetime.now(timezone.utc)
    rows = [
        {
            "id": "d1", "title": "T1", "source": "S1", "metadata": json.dumps({"k": "v"}),
            "created_at": now, "updated_at": now, "chunk_count": 3
        }
    ]
    conn.program_fetch(rows)
    # No filter
    res = await m.list_documents(limit=10, offset=0, metadata_filter=None)
    assert len(res) == 1
    assert res[0]["chunk_count"] == 3

    # With filter; ensure WHERE clause with @>
    conn._queries.clear()
    conn.program_fetch(rows)
    res2 = await m.list_documents(limit=5, offset=10, metadata_filter={"k": "v"})
    assert res2[0]["metadata"] == {"k": "v"}
    # Query construction assertions
    where_seen = any("@>" in q for (op, q, _) in conn.queries if op == "fetch")
    assert where_seen, "Expected metadata filter (@>) in query"


@pytest.mark.asyncio
async def test_vector_search_converts_embedding_and_parses_results(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    rows = [
        {
            "chunk_id": "c1", "document_id": "d1", "content": "foo", "similarity": 0.9,
            "metadata": json.dumps({"p": 1}), "document_title": "T", "document_source": "S"
        }
    ]
    conn.program_fetch(rows)
    res = await m.vector_search([1.0, 2.0, 3.0], limit=7)
    assert res[0]["similarity"] == 0.9
    # Ensure correct vector string generated (no spaces)
    params_seen = False
    for (op, q, params) in conn.queries:
        if op == "fetch" and "match_chunks" in q:
            params_seen = True
            assert params[0] == "[1.0,2.0,3.0]"
            assert params[1] == 7
    assert params_seen


@pytest.mark.asyncio
async def test_hybrid_search_builds_params_and_maps_fields(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    rows = [
        {
            "chunk_id": "c2", "document_id": "d2", "content": "bar",
            "combined_score": 0.75, "vector_similarity": 0.8, "text_similarity": 0.7,
            "metadata": json.dumps({"x": 2}), "document_title": "TT", "document_source": "SS"
        }
    ]
    conn.program_fetch(rows)
    res = await m.hybrid_search([0.1, 0.2], "query", limit=5, text_weight=0.4)
    assert res[0]["combined_score"] == 0.75
    # Ensure correct params passed
    found = False
    for (op, q, params) in conn.queries:
        if op == "fetch" and "hybrid_search" in q:
            found = True
            assert params[0] == "[0.1,0.2]"
            assert params[1] == "query"
            assert params[2] == 5
            assert params[3] == 0.4
    assert found


@pytest.mark.asyncio
async def test_get_document_chunks_maps_rows(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    rows = [
        {"chunk_id": "c1", "content": "a", "chunk_index": 0, "metadata": json.dumps({"m": 1})},
        {"chunk_id": "c2", "content": "b", "chunk_index": 1, "metadata": json.dumps({})},
    ]
    conn.program_fetch(rows)
    res = await m.get_document_chunks("d1")
    assert [r["chunk_id"] for r in res] == ["c1", "c2"]
    assert res[0]["metadata"] == {"m": 1}


@pytest.mark.asyncio
async def test_execute_query_returns_dicts(db_utils_module, fake_pg):
    m = db_utils_module
    pool, conn = fake_pg
    conn.program_fetch([{"a": 1}, {"b": 2}])
    res = await m.execute_query("SELECT 1")
    assert res == [{"a": 1}, {"b": 2}]


@pytest.mark.asyncio
async def test_test_connection_success_and_failure(db_utils_module, fake_pg, monkeypatch):
    m = db_utils_module
    pool, conn = fake_pg
    # Success
    conn.program_fetchval(1)
    assert await m.test_connection() is True

    # Failure: Make acquire() raise error by replacing acquire with raiser
    class BadPool(FakePool):
        def acquire(self):
            raise RuntimeError("boom")
    bad_pool = BadPool(conn)
    m.db_pool.pool = bad_pool
    assert await m.test_connection() is False