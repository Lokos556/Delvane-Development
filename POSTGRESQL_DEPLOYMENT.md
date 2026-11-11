# PostgreSQL deployment path

Rosa V2.6 keeps SQLite as the zero-friction local demo database while the same backend can use PostgreSQL when `ROSA_DATABASE_URL` begins with `postgresql://` or `postgres://`.

## Production sequence

1. Create a managed PostgreSQL database in the chosen EU region.
2. Create a dedicated Rosa database user with a strong provider-generated password.
3. Configure the hosting platform's **secret/environment manager**, not a source file:
   - `ROSA_APP_ENV=production`
   - `ROSA_DATABASE_URL=postgresql://...`
   - `ROSA_SECURE_COOKIES=1`
   - `ROSA_DEMO_MODE=0`
   - `ROSA_REQUIRE_COMPLETE_CHECKLIST=1`
   - `ROSA_ENCRYPTION_KEY=<Fernet key>`
4. Install `requirements-production.txt` (or build the supplied Dockerfile).
5. Start `uvicorn` through `start_production.sh`.
6. Rosa runs its idempotent schema creation/forward-migration ledger at startup.
7. Check `/health/live` and `/health/ready` through the hosting health checker.
8. Create the first real organization through the future onboarding/admin path; production does **not** auto-seed demo users or Casa Rosa fake data.
9. Enable provider backups and point-in-time recovery and perform a restore drill before relying on the database.

## Important

- Never commit `.env`, database passwords, OTA feed URLs, encryption keys, or API keys.
- The local `rosa.db` must never be copied into production as the production datastore.
- V2.6 has a PostgreSQL compatibility layer and migration ledger, but the actual managed cloud deployment should still be smoke-tested against the selected provider before real guest data is introduced.
