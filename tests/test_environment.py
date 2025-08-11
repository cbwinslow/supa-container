import shutil
import subprocess
from pathlib import Path
import pytest


def test_ssh_command_available():
    """Ensure the ssh client is available in the environment."""
    assert shutil.which("ssh") is not None


@pytest.mark.skipif(shutil.which("docker") is None, reason="Docker not installed")
def test_fastapi_dockerfile_builds():
    """Build the FastAPI Docker image to verify Docker setup."""
    dockerfile = Path("src/fastapi_app/Dockerfile")
    result = subprocess.run(
        ["docker", "build", "-q", "-f", str(dockerfile), "src/fastapi_app"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
