import pathlib

import pytest

SCRIPTS = [
    pathlib.Path("config.sh"),
    pathlib.Path("deploy.sh"),
    pathlib.Path("deploy-production.sh"),
    pathlib.Path("populate_secrets.sh"),
    pathlib.Path("post-deploy-setup.sh"),
    pathlib.Path("push_to_remotes.sh"),
    pathlib.Path("tests/test_deploy.sh"),
]

@pytest.mark.parametrize("script", SCRIPTS, ids=[str(s) for s in SCRIPTS])
def test_shell_scripts_use_strict_mode(script: pathlib.Path) -> None:
    """Ensure that shell scripts enable strict mode for safer execution."""
    contents = script.read_text()
    assert "set -euo pipefail" in contents
