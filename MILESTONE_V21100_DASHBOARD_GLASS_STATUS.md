# Rosa v2.11.00 — Dashboard, glass surfaces, status system

## UI changes
- Improved Today dashboard metric cards and arrivals/turnovers/maintenance columns with clearer hierarchy, numeric alignment, subtle elevation, and keyboard focus states.
- Unified the translucent warm-glass treatment across mobile navigation, Workspace settings, and notification/context drawers. Data-entry forms and data-heavy panels remain opaque for readability.
- Standardized status colors: green for success/ready, yellow/amber for attention/pending, red for errors/high severity, and neutral tones for ordinary states. Borders and shapes accompany color to improve clarity.
- Added reduced-motion support for the new transitions.
- Bumped stylesheet/script query versions and service-worker cache namespace.

## Scope and validation
- CSS-only UI changes plus cache-version updates; application business logic is unchanged.
- JavaScript syntax checks and package integrity checks are run before release.
- Visual appearance still requires browser testing on desktop and phone.
