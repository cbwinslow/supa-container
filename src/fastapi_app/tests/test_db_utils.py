import pytest
from unittest.mock import patch, AsyncMock
from fastapi_app.db_utils import create_session, get_session, add_message
from datetime import datetime

pytestmark = pytest.mark.asyncio

@pytest.fixture
def mock_db_pool():
    with patch('fastapi_app.db_utils.db_pool.acquire') as mock_acquire:
        mock_conn = AsyncMock()
        mock_acquire.return_value.__aenter__.return_value = mock_conn
        yield mock_conn

async def test_create_session(mock_db_pool):
    mock_db_pool.fetchrow.return_value = {'id': 'new-session-id'}
    session_id = await create_session(user_id="test-user")
    assert session_id == "new-session-id"
    mock_db_pool.fetchrow.assert_called_once()
    assert "INSERT INTO sessions" in mock_db_pool.fetchrow.call_args[0][0]

async def test_get_session_found(mock_db_pool):
    mock_db_pool.fetchrow.return_value = {
        "id": "test-session", "user_id": "test-user", "metadata": '{}',
        "created_at": datetime.now(), "updated_at": datetime.now(),
        "expires_at": datetime.now()
    }
    session = await get_session("test-session")
    assert session is not None
    assert session['id'] == "test-session"

async def test_get_session_not_found(mock_db_pool):
    mock_db_pool.fetchrow.return_value = None
    session = await get_session("not-found-session")
    assert session is None

async def test_add_message(mock_db_pool):
    mock_db_pool.fetchrow.return_value = {'id': 'new-message-id'}
    message_id = await add_message(session_id="test-session", role="user", content="Hello")
    assert message_id == "new-message-id"
    assert "INSERT INTO messages" in mock_db_pool.fetchrow.call_args[0][0]
