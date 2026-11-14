"""No network/database setup: root conftest installs isolation before app import."""
import pytest
from fastapi.testclient import TestClient

import app


def test_unconfigured_local_server_does_not_advertise_remote_environment(monkeypatch):
    monkeypatch.delenv("ROSA_DEPLOYMENT_ENVIRONMENT", raising=False)
    monkeypatch.delenv("ROSA_DEPLOYMENT_ID", raising=False)
    assert TestClient(app.app).get("/api/client/environment").status_code == 404


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_metadata_is_public_and_contains_no_credentials_or_database_values(monkeypatch, environment):
    monkeypatch.setenv("ROSA_DEPLOYMENT_ENVIRONMENT", environment)
    monkeypatch.setenv("ROSA_DEPLOYMENT_ID", "public-deployment-01")
    monkeypatch.setattr(app, "APP_ENV", "production")
    monkeypatch.setattr(app, "SECURE_COOKIES", True)

    def forbidden_db():
        raise AssertionError("Metadata must never open a database")
    monkeypatch.setattr(app, "db", forbidden_db)
    # Deliberately no TestClient lifespan: startup migrations must not run here.
    result = TestClient(app.app).get("/api/client/environment")
    assert result.status_code == 200
    assert result.json() == {"environment": environment,
                             "deployment_id": "public-deployment-01", "secure_cookies": True}


@pytest.mark.parametrize("environment,deployment,runtime,secure", [
    ("staging", "public-stage-01", "development", True),
    ("staging", "public-stage-01", "test", True),
    ("staging", "public-stage-01", "production", False),
    ("local", "public-stage-01", "production", True),
    ("staging", "", "production", True),
    ("", "public-stage-01", "production", True),
    ("staging", "contains spaces", "production", True),
])
def test_unsafe_remote_metadata_fails_closed(monkeypatch, environment, deployment, runtime, secure):
    monkeypatch.setenv("ROSA_DEPLOYMENT_ENVIRONMENT", environment)
    monkeypatch.setenv("ROSA_DEPLOYMENT_ID", deployment)
    monkeypatch.setattr(app, "APP_ENV", runtime)
    monkeypatch.setattr(app, "SECURE_COOKIES", secure)
    result = TestClient(app.app).get("/api/client/environment")
    assert result.status_code == 503
    assert result.json() == {"detail": "Remote client environment is not ready."}
