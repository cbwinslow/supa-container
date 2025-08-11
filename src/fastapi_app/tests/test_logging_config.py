import logging
import os
import importlib
from unittest.mock import patch, MagicMock

# Import the module that configures logging
import src.logging_config as logging_config

def clear_root_handlers():
    """Remove all handlers from the root logger."""
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)
        handler.close()

@patch.dict(os.environ, {}, clear=True)
def test_setup_logging_is_idempotent():
    """Verify that calling setup_logging multiple times doesn't add more handlers."""
    # Ensure a clean state
    clear_root_handlers()

    # Reload the module to trigger the initial setup_logging() call
    importlib.reload(logging_config)
    initial_handler_count = len(logging.root.handlers)
    assert initial_handler_count > 0, "Logging should be configured on import"

    # Call setup_logging again and check that no new handlers were added
    logging_config.setup_logging()
    assert len(logging.root.handlers) == initial_handler_count

@patch.dict(os.environ, {"LOG_OUTPUT": "console"}, clear=True)
def test_default_handler_is_console():
    """Verify that the default handler is a StreamHandler (console)."""
    clear_root_handlers()
    importlib.reload(logging_config)

    assert len(logging.root.handlers) == 1
    handler = logging.root.handlers[0]
    assert isinstance(handler, logging.StreamHandler)

@patch.dict(os.environ, {"LOG_OUTPUT": "file", "LOG_FILE_PATH": "test.log"}, clear=True)
def test_file_handler_is_added():
    """Verify that a FileHandler is added when LOG_OUTPUT is 'file'."""
    clear_root_handlers()
    importlib.reload(logging_config)

    assert len(logging.root.handlers) == 1
    handler = logging.root.handlers[0]
    assert isinstance(handler, logging.FileHandler)
    # Clean up the created log file
    if os.path.exists("test.log"):
        os.remove("test.log")

@patch.dict(os.environ, {"LOG_OUTPUT": "console,file", "LOG_FILE_PATH": "test.log"}, clear=True)
def test_console_and_file_handlers_are_added():
    """Verify that both StreamHandler and FileHandler are added when LOG_OUTPUT is 'console,file'."""
    clear_root_handlers()
    importlib.reload(logging_config)

    handlers = logging.root.handlers
    assert len(handlers) == 2
    stream_handler_found = any(isinstance(h, logging.StreamHandler) for h in handlers)
    file_handler_found = any(isinstance(h, logging.FileHandler) for h in handlers)
    assert stream_handler_found, "StreamHandler not found in handlers"
    assert file_handler_found, "FileHandler not found in handlers"
    # Clean up the created log file
    if os.path.exists("test.log"):
        os.remove("test.log")

@patch.dict(os.environ, {"LOG_FORMAT": "json"}, clear=True)
def test_json_formatter_is_used(monkeypatch, caplog):
    """Verify that the JsonFormatter is used when LOG_FORMAT is 'json', and fallback behavior if unavailable."""

    clear_root_handlers()

    # Simulate ImportError for python-json-logger
    import builtins
    real_import = builtins.__import__

    def fake_import(name, *args, **kwargs):
        if name == "pythonjsonlogger.jsonlogger":
            raise ImportError("Simulated missing python-json-logger")
        return real_import(name, *args, **kwargs)

    # Test fallback behavior when python-json-logger is missing
    monkeypatch.setattr(builtins, "__import__", fake_import)
    with caplog.at_level("WARNING"):
        importlib.reload(logging_config)
        handler = logging.root.handlers[0]
        # Should use standard formatter
        assert not hasattr(handler.formatter, "jsonify"), "Fallback to standard formatter expected"
        # Should log a warning about missing dependency
        assert any("python-json-logger" in r.message for r in caplog.records), "Warning about missing python-json-logger expected"

    # Restore import for normal test
    monkeypatch.setattr(builtins, "__import__", real_import)
    try:
        from pythonjsonlogger.jsonlogger import JsonFormatter
        importlib.reload(logging_config)
        handler = logging.root.handlers[0]
        assert isinstance(handler.formatter, JsonFormatter), "JsonFormatter should be used when available"
    except ImportError:
        # If not installed, fallback already tested above
        pass

    # Mock the JsonFormatter to check if it's instantiated
    with patch('pythonjsonlogger.jsonlogger.JsonFormatter', MagicMock()) as mock_json_formatter:
        importlib.reload(logging_config)
        # Check if the formatter of the handler is an instance of the mocked class
        assert len(logging.root.handlers) > 0
        # The mock is on the class, so we check if it was called (instantiated)
        mock_json_formatter.assert_called_once()
