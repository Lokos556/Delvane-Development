# Rosa V2.6.2 — Local-first intelligence

Rosa now routes every owner chat request in this order:

1. **DATABASE** — exact property/guest facts. Zero external AI calls.
2. **OPERATIONS** — deterministic calculations over reservations, cleaning, registration, maintenance and readiness. Zero external AI calls.
3. **ACTION ENGINE** — governed operational actions such as cleaning reassignment. Zero external AI calls; authority rules still apply.
4. **LUNA** — optional fallback only when the first three routes cannot confidently handle the request.
5. **LOCAL FALLBACK** — if Luna is not configured, Rosa explains that the request needs freer language reasoning instead of inventing an answer.

The route used is shown under every Rosa answer during development and is logged in `rosa_ai_routes`.

## Examples

- `What is the Wi-Fi password?` → DATABASE
- `Does Terra have parking?` → DATABASE
- `Who still needs registration?` → OPERATIONS
- `Anything concerning tomorrow?` → OPERATIONS
- `Move today's cleaning from Anna to Erika.` → ACTION ENGINE
- `Think through whether there are patterns I should worry about and explain why.` → LUNA if configured, otherwise LOCAL FALLBACK

## Optional Luna later

You do not need an OpenAI API key to use or test V2.6.2.

If a Luna API key is configured later with `SETUP_ROSA_AI.bat`, the exact same local-first routing remains in place. The key never causes ordinary database questions to be sent to OpenAI.
