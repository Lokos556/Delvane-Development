# Rosa V2.6.4.2 — Luna fallback hotfix

- Keeps the local-first router unchanged.
- Simplifies Luna calls to the plain Responses API text path already proven by the setup connection test.
- Removes unnecessary JSON-schema Structured Output from answer-only fallback requests.
- Adds sanitized diagnostics under `/api/rosa/provider` as `last_external_status`.
- Never exposes or logs the API key.
- Local port: 8814.
