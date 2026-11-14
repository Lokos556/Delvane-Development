"""Public native-client deployment metadata. No database access or secret values.

Staging deliberately uses the existing production runtime hardening, with its own
database and credentials. This metadata is an environment guard, not authentication.
"""
import os
import re

from fastapi import HTTPException


def client_environment_metadata(runtime_environment: str, secure_cookies: bool):
    environment = os.getenv("ROSA_DEPLOYMENT_ENVIRONMENT", "")
    deployment_id = os.getenv("ROSA_DEPLOYMENT_ID", "")
    if not environment and not deployment_id:
        raise HTTPException(404, "Remote client environment is not configured.")
    if (environment not in {"staging", "production"}
            or runtime_environment != "production" or not secure_cookies
            or not re.fullmatch(r"[A-Za-z0-9_-]{8,128}", deployment_id)):
        raise HTTPException(503, "Remote client environment is not ready.")
    return {"environment": environment, "deployment_id": deployment_id,
            "secure_cookies": True}
