# Rosa V2.6.4.2 hotfix

- Fixes the Enter Rosa crash caused by a stale `cp()` localization reference inside the Operations Desk decision-card renderer.
- Restores a visible login on first launch of this local build. Localhost cookies are shared across ports, so an authenticated session from V2.6.3 could make V2.6.4 appear to have no login page. The local client now deliberately clears that carried-over development session on first launch of this version; production behavior is unchanged.
- Enter Rosa now opens the conversation-first Intelligence workspace correctly even when approval/decision cards exist.
- Local port: 8814.
