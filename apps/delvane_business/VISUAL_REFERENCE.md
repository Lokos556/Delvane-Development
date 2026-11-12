# PMS visual reference and comparison

Updated 2026-11-12. The reference is the existing `static/index.html`,
`static/styles.css`, `static/app.js` and `static/v283.js`, including their later
overrides. This is a source-based fidelity pass, not a redesign or a claim of
pixel-perfect parity. Backend source and operational databases were not changed.

## Latest continuation

The reference now includes **38 web and 38 final Flutter captures**: the original
15 states plus `desk-overview`, `desk-decisions`, `desk-exceptions` and `desk-next48`
at both viewport sizes. The same safe commands below regenerate them. Both
renderers share synthetic decision/exception records; no production data is used.
Earlier references to 30 captures below describe the first visual pass.

The new Live context desk follows the active v264 layer, including original
At a glance / Needs you / Exceptions / Next 48h labels, a protected contextual
route, independently scrolling tabs/content and record-resolution actions.
Computed desktop source bounds: layer x254/y17, 1167 × 964; desk x580.77/y17,
840.23 × 964. The native layer uses those insets and the same 72%/82%/full-width
breakpoints. On the 390px reference, the layer is x11/y75, 368 × 759. Its backdrop
uses the final overridden white .42 surface and blur20/saturation1.6, leaving the
sidebar visible. Earlier dark full-window dimming was corrected after comparison.
The native desk recommendation panel, neutral action buttons, font family, compact
cards and heading were corrected using the expanded reference images. Some text,
badge and row positions still differ; the expanded screenshots are not goldens.

Shared modal surfaces now apply the actual CSS blur26/saturation1.55 and settings
blur42/saturation1.9 using a composed backdrop filter. This replaces the previous
unfiltered modal translucency. It does not guarantee identical Chromium rasterization
or CSS inset-shadow behavior. Reservation detail uses the original narrow-screen
bottom-sheet alignment; other dialogs retain their reference-specific centered form.

Security now displays server runtime fields, six posture metrics, sessions and role
permissions in side-by-side desktop panels. Knowledge has scope tabs, prototype
warning, persisted completeness and editable field status. Property details include
arrival/departure time and the primary stay's source/reference and registration
badge, using existing overview fields. These correct omitted visual context without
introducing a new calculation or mutation API.

Remaining visible differences include the Security runtime decoration and compact
metric dimensions, exact typography/weights, native scrollbar/menu behavior,
property-dialog borders/fact chips/scroll layout and some mobile reception/forms.
Only selected pairs were inspected visually; all 38 states were rendered and
layout-checked. This is not exhaustive visual acceptance of all 125 capabilities.

## Measured reference

Values below come from the source and computed browser styles at 1440 × 1000 and
390 × 844. Contextual and late CSS overrides take precedence over base declarations.

| Component | Original specification | Native treatment |
|---|---|---|
| Font stack | `Inter, "DM Sans", system-ui, sans-serif`; body 16px. No bundled Inter/DM Sans files were found. | Windows Segoe UI fallback, with Arial and symbol fallback; tests load installed fonts. No new font download. |
| Ink / muted | `#171717` and black; muted `#686868` | Shared text styling rather than Material defaults. |
| Base surface | Body `rgb(244,241,232)`; white/translucent main surfaces | White main workspace and ivory/translucent chrome. |
| Sidebar | 235px; padding 28px top, 18px sides, 20px bottom; ivory `rgba(255,252,244,.55)` | Fixed desktop rail, independently scrollable navigation, account footer, compact mobile drawer. |
| Navigation | 54px desktop / 60px mobile; radius 19px; desktop padding 15px × 17px; text 16px and selected weight 800 | Shared selected/hover/focus rows; original labels and role filtering retained. |
| Brand | Logo 48px desktop / 36px mobile; name 19.2px / 17.28px; tracking 1.728px / 1.296px | Existing logo asset and matching dimensions. |
| Main Today content | Desktop padding 36px top, 72px horizontal, 130px bottom | Source-shaped content column and reserved scroll gutter. |
| Page heading | 57.6px desktop / 38.4px mobile; line height 1.04; tracking −2px | Responsive shared heading; contextual calendar override. |
| Regular buttons | 16px, weight 700, padding 13px vertical / 18px horizontal, roughly 49px high | Shared button layout; compact variants retained for dense controls. |
| Primary button | `#FFE76A` → `#FFD000`; shadow `0 8px 24px rgba(191,155,0,.2)` | Yellow gradient and soft shadow, source hover treatment. |
| Shared surfaces | Radius 24px; translucent white border .48; shadow `0 12px 36px rgba(45,39,25,.09)` plus inset highlight | Matching geometry and soft shadow; CSS saturation/inset rendering remains approximate. |
| Property dialog | Width 760px, max height 92vh, padding 28px, radius 24px, white .88, title 32px | Shared scrollable dialog, close glyph, responsive action wrapping, existing busy-close guard. |
| Settings sheet | Width 490px, viewport margin 12px, radius 32px, padding 26px; blur 42px, saturation 190%; ivory .66 | Right-side protected sheet and blur. Mobile margin 8px, radius 30px, padding 22px vertical / 18px horizontal. Saturation is not exact. |
| Today metrics | 66px high, gap 12px, four desktop columns; two mobile columns; Georgia numerals | Source-sized cards and responsive grid. |
| Registration strip | Radius 22px; padding 18px vertical / 20px horizontal; header 54px and row 66px | Count, title, attention marker and stay action hierarchy reproduced. |
| Operational queues | Radius 20px; row minimum 66px, padding 13px × 15px; yellow count 26px | Compact clipped panels, source symbols, time and severity hierarchy. |
| Property cards | Radius 18px; padding 20px; desktop width about 339px; title 23.2px | Attention/readiness badges and footer alignment corrected. |
| Reception | Desktop list 365px, gap 12px; workspace height 765px at 1000px viewport | Independent pane scrolling and source metric hierarchy. |
| Calendar heading | `clamp(30px,3vw,44px)` = 43.2px at 1440; narrower overrides 30/26px | Contextual sizing and source header action placement. |
| Calendar cells | Desktop `clamp(110px,12vw,158px)`; mobile `clamp(78px,17vw,116px)` and 72px at ≤430px | Elastic min-height cells, uppercase weekday labels, preserved overflow controls. |
| Calendar stays | White .42 surface, black text, property-color dot, radius 18px, padding 5px × 6px | Replaces former solid property-color bars without changing date selection or stay actions. |
| Team | Person card radius 24px, padding 18px; avatar 48px; two contact panels and four workload statistics | Source card hierarchy, compact Georgia metrics and plain tabs. |
| Intelligence | Active v264 layout has compact mode/search bar and pulse, Georgia 28px empty heading, 72px logo and bottom composer | Replaced oversized legacy-style blocks with the active DOM hierarchy; independent message scrolling. |
| Floating Ask | Only Reservations, Reception, Team and Train; desktop max width 900px, height 84px, bottom 22px; mobile height 74px, bottom 12px | Same page conditions and existing local-answer endpoint; not an alternative provider integration. |

The source has several generations of overlapping CSS. In particular, older
Intelligence metric declarations are not the active v264 chat layout. They were
not used as the visual target. Likewise, shared button/dialog rules have local
overrides; not every component is forced into one radius or fixed height.

## Page and interaction changes

- Today: corrected header, urgency, metric density, registration queue, operational
  panels, property readiness and worker task columns; existing routes/actions retained.
- Intelligence: active compact workspace, bottom prompts/composer, short-window
  scrolling, source prompt labels and existing proposal/session handling.
- Reservations: calendar typography, cell sizing, stay appearance and contextual
  controls; existing booking forms, date navigation and API mutations preserved.
- Reception: source list/detail proportions, independent scrolling, empty detail
  panel and typography; inbox/draft/schedule/approval actions retained.
- Team: source header, person cards, contact blocks, workload and security chips.
- Operations: shared heading/surfaces and numbered maintenance lifecycle rail.
- Administration, integrations, property dialogs and worker views inherit the
  corrected shell, controls, headings, badges and dialog geometry.
- Shared navigation has selected, hover and focus states. Mobile navigation closes
  before opening the destination. Existing Ctrl-K/Cmd-K search remains intact.
  The settings sheet stays inside the protected navigator and disappears on session
  revocation. Dialogue submission and busy-close safeguards remain intact.
- The floating Ask bar supports keyboard submit, pending/error/answer states and
  calls `POST /api/rosa/ask`. Intelligence continues to use `/api/rosa/chat` and its
  existing proposal endpoint. Neither silently switches to test fixtures.

## Screenshot evidence and reproduction

The ignored `build/visual-reference/` directory contains **30 original-web images
and 30 final Flutter images**: 15 states at both 1440 × 1000 and 390 × 844.
States: today, intelligence, calendar, reception, operations, team, maintenance,
supplies, knowledge, simulation, security, integrations, property, settings, worker.
Both renderers use the same clearly synthetic test fixture and May 2032 calendar.

- Original: `web-{state}-{width}x{height}.png`.
- Flutter: `flutter-after-{state}-{width}x{height}.png`.
- Browser measurements: `computed-styles.json`, `computed-styles-by-page.json`.
- Native positions: corresponding `.geometry.json` files.

For example, the Today metric row is `(307,208.89)`, size `1046 × 66` in the
browser and `(307,208)`, size `1046 × 66` in Flutter. Queue/property positions still
diverge farther down the page because text metrics and row heights are not exact.
This measurement does not establish whole-page pixel equivalence.

From the Flutter directory, using the already installed environment:

```powershell
..\..\.venv\Scripts\python -B tool\capture_web_reference.py
flutter --no-version-check test test\visual_parity_test.dart --reporter expanded
```

The browser capture serves only allowlisted static files and synthetic GET JSON on
its own ephemeral loopback server. Writes return 405. A temporary Chrome profile,
request interception, dead proxy and DNS restrictions block external access. It
does not import the backend or open any database. Flutter captures use test-only
fake HTTP transport; the live application still uses its existing API client.
Windows fonts are read from the installed system for tests, not copied into assets.

These are browser and Flutter-renderer screenshots, not an automated Win32 click
test or acceptance test on Android/iOS/macOS. Earlier `flutter-before-*` images
were captured with a less complete shadow/font harness; they must not be used to
claim a numerical before/after pixel score. The final paired reference is the
comparison evidence. No image-difference threshold is currently enforced by CI.

## Reference limitations and remaining differences

- The original v283 Team and Train rendering calls a missing `wireRosa` helper.
  Capture records the original error after confirming the expected DOM exists.
  No compatibility shim was inserted and no web source was edited. Native working
  controls were preserved rather than reproducing that JavaScript failure.
- Flutter and Chromium differ in font weight/kerning, text wrapping, shadows,
  saturation, inset highlights, scrollbar rendering and menu placement. Native
  refresh/session controls remain visible where needed.
- Some mobile source pages hide navigation/metrics/tabs; existing native accessible
  controls remain available. Exact mobile reception behavior and all narrow-screen
  form/table variants still need a dedicated comparison pass.
- Native dropdowns, focus/selection behavior, hover transitions, some dialogs,
  dense operational tables and rare/error/expanded states are not individually
  screenshot-matched. Calendar heights remain content-sensitive in both clients.
- The 15 captured states cover the major page families, not all 125 capabilities,
  languages, worker roles, mutation results or OS rendering variants. Cleaner view
  is captured; maintenance-specific behavior remains covered by workflow tests.
- Functional parity gaps and backend limitations from FEATURE_PARITY.md remain;
  this pass does not upgrade a partial feature solely because it looks closer.
