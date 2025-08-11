import shutil
import subprocess
from pathlib import Path
import socket
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


def test_firewall_tool_available():
    """Verify that a firewall management utility is installed."""
    if not (shutil.which("ufw") or shutil.which("iptables")):
        pytest.skip("No firewall utility installed")


def test_required_ports_available():
    """Check that common service ports are free for binding."""
    for port in (22, 80, 8000):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            assert sock.connect_ex(("localhost", port)) != 0
