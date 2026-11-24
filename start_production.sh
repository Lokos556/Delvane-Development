#!/usr/bin/env sh
set -eu
# Production settings (database URL, encryption key, HTTPS-cookie mode, demo mode)
# must be supplied by the hosting platform's encrypted environment/secrets store.
# Guest check-in routes carry bearer tokens in their paths.
exec uvicorn app:app --host 0.0.0.0 --port "${PORT:-8080}" --proxy-headers --no-access-log
