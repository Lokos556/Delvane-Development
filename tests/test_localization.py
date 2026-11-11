from pathlib import Path
import shutil
import subprocess
import pytest


def test_all_supported_locales_have_full_coverage():
    node = shutil.which("node")
    if not node:
        pytest.skip("Node.js is only needed for the developer localization coverage test")
    script = Path(__file__).with_name("localization_coverage.js")
    result = subprocess.run([node, str(script)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
