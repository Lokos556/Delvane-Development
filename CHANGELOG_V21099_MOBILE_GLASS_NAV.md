# Rosa v2.10.99 — Mobile glass navigation

- Restyled the mobile navigation drawer as translucent warm glass with blur and saturation, matching the Workspace settings panel.
- Softened the modal backdrop with translucent dark tint and stronger blur.
- Removed opaque white navigation item backgrounds on mobile; active/hover states use Rosa yellow with readable black text.
- Preserved the existing drawer open/close logic, navigation actions, and desktop styles.
- Bumped CSS and JS asset query versions to prevent stale cache.

Validation: checked HTML asset references and JavaScript syntax. Visual appearance should still be verified on the target phone because browser backdrop-filter support and actual contrast depend on the device/browser.
