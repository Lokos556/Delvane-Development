"""Install isolation before pytest imports any application test modules."""
import sys
from datetime import date, datetime
from pathlib import Path

import pytest

from testing_safety import IsolatedEnvironment
from testing_clock import FixedDate, FixedDatetime, reset_clock


def pytest_configure(config):
    if "app" in sys.modules:
        raise pytest.UsageError("Application imported before test isolation; restart pytest")
    if config.option.basetemp:
        raise pytest.UsageError("Do not supply --basetemp; isolation owns temporary storage")
    safety = IsolatedEnvironment().__enter__()
    def close_isolation():
        # Pytest's optional "current" links can become dangling directory links
        # on Windows; Python 3.14 rmtree leaves them behind (WinError 145).
        # Remove only aliases in our own guarded temp tree, never their targets.
        pytest_root = safety.root / "pytest"
        if sys.platform == "win32" and pytest_root.is_dir():
            for alias in pytest_root.iterdir():
                if (alias.name.endswith("current") and alias.is_symlink()
                        and alias.resolve(strict=False).is_relative_to(safety.root)):
                    alias.unlink(missing_ok=True)
        safety.__exit__(None, None, None)
    config.add_cleanup(close_isolation)
    config._delvane_safety = safety
    config.option.basetemp = str(safety.root / "pytest")
    import app
    safety.protect_app(app)


@pytest.fixture(autouse=True)
def deterministic_calendar(monkeypatch):
    import app
    reset_clock()
    test_root = (Path(__file__).parent / "tests").resolve()
    for module in list(sys.modules.values()):
        source = getattr(module, "__file__", None)
        if module is not app and (not source or not Path(source).resolve().is_relative_to(test_root)):
            continue
        for name, value in list(vars(module).items()):
            if value is date:
                monkeypatch.setattr(module, name, FixedDate)
            elif value is datetime:
                monkeypatch.setattr(module, name, FixedDatetime)


@pytest.fixture(autouse=True)
def isolated_application(request, tmp_path, monkeypatch, deterministic_calendar):
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
    assert app.DB_PATH.resolve().is_relative_to(safety.root)
    assert app.APP_ENV == "test" and app.DB_BACKEND == "sqlite"
    assert not app.CHANNEX_API_KEY and not app.OPENAI_API_KEY
    try:
        yield
    finally:
        safety.close_connections()


def pytest_collection_modifyitems(items):
    for item in items:
        if item.path.name == "test_localization.py":
            item.add_marker(pytest.mark.skip(
                reason="Node child process cannot inherit Python isolation/network guards"))
