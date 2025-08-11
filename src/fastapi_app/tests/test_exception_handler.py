import pytest
from fastapi.testclient import TestClient

from fastapi_app.api import app


def test_global_exception_handler_preserves_request_id_and_details():
    class CustomException(Exception):
        def __init__(self, message, request_id, details):
            super().__init__(message)
            self.request_id = request_id
            self.detail = details

    @app.get("/error-test")
    async def error_test():
        raise CustomException("boom", "req-123", {"foo": "bar"})

    client = TestClient(app)
    response = client.get("/error-test")
    assert response.status_code == 500
    data = response.json()
    assert data["error"] == "boom"
    assert data["error_type"] == "CustomException"
    assert data["details"] == {"foo": "bar"}
    assert data["request_id"] == "req-123"

    # Clean up the test route
    app.router.routes.pop()
