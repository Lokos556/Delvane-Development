#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export ROSA_APP_ENV=development
export ROSA_DEMO_MODE=1
export ROSA_SECURE_COOKIES=0
export ROSA_REQUIRE_COMPLETE_CHECKLIST=0
python3 -m uvicorn app:app --host 127.0.0.1 --port 8819
