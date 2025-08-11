import subprocess
import shutil
from pathlib import Path
import pytest


@pytest.mark.skipif(
    shutil.which("shellcheck") is None, reason="ShellCheck not installed"
)
def test_shell_scripts_lint_clean():
    """Run ShellCheck on all shell scripts in the repository."""
    scripts = [p for p in Path(".").rglob("*.sh") if p.is_file()]
    for script in scripts:
        result = subprocess.run(
            ["shellcheck", str(script)],
            capture_output=True,
            text=True,
        )
        assert (
            result.returncode == 0
        ), f"ShellCheck failed for {script}\n{result.stdout}\n{result.stderr}"
