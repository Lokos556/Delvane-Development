"""Install isolation before pytest imports any application test modules."""
import sys

import pytest

from testing_safety import IsolatedEnvironment


def pytest_configure(config):
    if "app" in sys.modules:
        raise pytest.UsageError("Application imported before test isolation; restart pytest")
    if config.option.basetemp:
        raise pytest.UsageError("Do not supply --basetemp; isolation owns temporary storage")
    safety = IsolatedEnvironment().__enter__()
    config.add_cleanup(lambda: safety.__exit__(None, None, None))
    config._delvane_safety = safety
    config.option.basetemp = str(safety.root / "pytest")
    import app
    safety.protect_app(app)


@pytest.fixture(autouse=True)
def isolated_application(request, tmp_path, monkeypatch):
    import app
    safety = request.config._delvane_safety
    safety.require_path(tmp_path / "test.db")
    monkeypatch.setattr(app, "DB_PATH", tmp_path / "test.db")
    monkeypatch.setattr(app, "DATA_DIR", tmp_path)
    monkeypatch.setattr(app, "LEGACY_DB_PATH", tmp_path / "absent-legacy.db")
    monkeypatch.setattr(app, "DATABASE_URL", "sqlite:///" + str(tmp_path / "test.db"))
    monkeypatch.setattr(app, "DB_BACKEND", "sqlite")
    monkeypatch.setattr(app, "STABLE_ENV_PATH", tmp_path / ".env.local")
    monkeypatch.setattr(app, "APP_ENV", "test")
    monkeypatch.setattr(app, "DEMO_MODE", True)
    monkeypatch.setattr(app, "SECURE_COOKIES", False)
    monkeypatch.setattr(app, "CHANNEX_API_KEY", "")
    monkeypatch.setattr(app, "OPENAI_API_KEY", "")
    monkeypatch.setattr(app, "AI_PROVIDER", "local")
    monkeypatch.setattr(app, "AI_LAST_STATUS", {"state": "never_called", "error": None,
                        "last_success_at": None, "last_attempt_at": None})
