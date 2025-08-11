import logging
from logging.config import dictConfig


def setup_logging() -> None:
    """
    Configure logging for the application.
    This function is idempotent and will not add duplicate handlers if called multiple times.
    """
    if logging.root.hasHandlers():
        return

    formatters = {
        "standard": {
            "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        },
    }

    handlers = {}
    log_formatter = "standard"
    if LOG_FORMAT == "json":
        log_formatter = "json"
        formatters["json"] = {
            "class": "pythonjsonlogger.jsonlogger.JsonFormatter",
            "format": "%(asctime)s %(name)s %(levelname)s %(message)s",
        }

    if "console" in LOG_OUTPUT:
        handlers["console"] = {
            "class": "logging.StreamHandler",
            "formatter": log_formatter,
        }

    if "file" in LOG_OUTPUT:
        handlers["file"] = {
            "class": "logging.FileHandler",
            "formatter": log_formatter,
            "filename": LOG_FILE_PATH,
        }

    if not handlers:
        # Default to console if LOG_OUTPUT is misconfigured
        handlers["console"] = {
            "class": "logging.StreamHandler",
            "formatter": log_formatter,
        }

    LOGGING_CONFIG = {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": formatters,
        "handlers": handlers,
        "root": {
            "handlers": list(handlers.keys()),
            "level": LOG_LEVEL,
        },
    }
    dictConfig(LOGGING_CONFIG)


def get_logger(name: str) -> logging.Logger:
    """Get a logger with the given name."""
    return logging.getLogger(name)

# Configure logging immediately upon import
setup_logging()
