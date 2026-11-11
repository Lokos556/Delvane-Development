# Rosa V2.6 security architecture

Rosa V2.6 continues the with a **production-capable security foundation**. It is not a claim that Rosa has completed an external security audit or penetration test.

## Boundaries

- Browsers never receive database credentials.
- Every customer-owned resource is resolved through the authenticated user's `organization_id` on the server.
- Roles and permissions are enforced by the FastAPI backend, not by hidden frontend buttons.
- Sensitive registration payloads use a separate encrypted vault table (`sensitive_guest_data`).
- Production requires a separately supplied Fernet encryption key; the development fallback key must never be used for real data.
- Passwords are stored as memory-hard scrypt hashes. Legacy PBKDF2 hashes are upgraded at successful login.
- Session cookies are HttpOnly + SameSite and become `Secure` in production. Only SHA-256 session-token digests are stored server-side.
- Mutating authenticated API calls use a per-session CSRF token.
- Login attempts are rate limited.
- Password-reset and email-verification tokens are random, single-use, expiry-limited, and only their hashes are stored.
- Password reset revokes all active sessions for that user.
- Sensitive and security-relevant actions create audit events.

## Production runtime guard

`ROSA_APP_ENV=production` refuses to start unless:

1. PostgreSQL is configured.
2. secure cookies are enabled.
3. demo mode is disabled.
4. a production encryption key is supplied.
5. the PostgreSQL driver is installed.
6. if `ROSA_AI_PROVIDER=openai`, an API key is supplied through secrets/environment configuration.

This is deliberate: an unsafe environment should fail closed rather than silently run as production.

## Still required before commercial launch

- HTTPS at the hosting/load-balancer edge.
- managed PostgreSQL encryption/backups/point-in-time recovery as configured by the provider.
- a transactional email provider for reset/verification links.
- real MFA/passkey implementation (the database/security model already has MFA fields, but V2.5 does not claim working MFA).
- secret/key manager for database, encryption, AI and integration credentials.
- dependency and container vulnerability scanning in CI.
- centralized security/error monitoring.
- independent professional penetration test and fix retest.
- legal/privacy review for the exact production data-retention and Hungarian VENDÉGEM/VIZA/NTAK flows.

## Identity-document caution

The demo is designed to test registration workflow without requiring real passport/ID data. Do not put real identity-document information into the local demo. The encrypted vault is an architecture component, not authorization to collect data outside the applicable legal/certified process.


## V2.6 AI security boundary

- Rosa AI never receives direct database credentials.
- The external provider adapter, when explicitly enabled, receives a backend-built operational snapshot rather than raw database access.
- Sensitive identity-vault payloads are excluded from that snapshot.
- Conversational action requests become structured proposals and are resolved by deterministic backend validators.
- Organization mode (OBSERVE/ASSIST/AUTONOMOUS) and per-action authority rules remain authoritative even when an external model is used.
- An LLM-generated sentence can never itself prove that a write happened; execution and audit evidence come from the backend action engine.
- Prompt-injection and adversarial-input testing are still required before commercial launch, particularly once guest-originated messages are sent to the model.
