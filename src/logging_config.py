import logging
from logging.config import dictConfig

from settings import settings

LOG_LEVEL = settings.log_level.upper()

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        },
    },
    "handlers": {
        "default": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
        },
    },
    "root": {
        "handlers": ["default"],
        "level": LOG_LEVEL,
    },
}

def setup_logging() -> None:
    """Configure root logger with standard settings."""
    dictConfig(LOGGING_CONFIG)


def get_logger(name: str) -> logging.Logger:
    """Get a logger with the given name."""
    return logging.getLogger(name)

# Configure logging immediately upon import
setup_logging()
