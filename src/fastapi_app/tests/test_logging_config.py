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

@patch.dict(os.environ, {"LOG_FORMAT": "json"}, clear=True)
def test_json_formatter_is_used():
    """Verify that the JsonFormatter is used when LOG_FORMAT is 'json'."""
    # This test requires python-json-logger to be installed
    try:
        from pythonjsonlogger.jsonlogger import JsonFormatter
    except ImportError:
        # If the library isn't installed, we can't run this test,
        # but the code should handle it gracefully.
        # The dependency installation should handle this in the real environment.
        return

    clear_root_handlers()

    # Mock the JsonFormatter to check if it's instantiated
    with patch('pythonjsonlogger.jsonlogger.JsonFormatter', MagicMock()) as mock_json_formatter:
        importlib.reload(logging_config)
        # Check if the formatter of the handler is an instance of the mocked class
        assert len(logging.root.handlers) > 0
        # The mock is on the class, so we check if it was called (instantiated)
        mock_json_formatter.assert_called_once()
