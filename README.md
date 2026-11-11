# Rosa V2.10.1 — Casa Rosa PMS

Windows desktop: double-click `START_ROSA.bat`. Rosa opens at `http://127.0.0.1:8819`.

Developer Channex staging setup: double-click `SETUP_ROSA_CHANNEX.bat`, then paste the staging API key into the hidden prompt. It is tested against Channex before being saved under `%LOCALAPPDATA%\Rosa\.env.local`, outside the extracted release folder. New standalone Rosa releases automatically keep using it. This shared developer credential belongs on Rosa's server; future property owners never enter it.

After restarting Rosa, open Owner tools → Integrations → Connect Booking.com. Choose the Channex staging property and select Prepare staging. Rosa validates access and creates or reuses the matching Channex room type and Standard Rate through the API; repeating the operation is idempotent.

Connected properties are checked for new Channex booking revisions every 60 seconds while Rosa is running. Use **Check for bookings** on the Integrations page for an immediate check. Rosa routes each revision by Channex room type, saves new/modified/cancelled reservations, refreshes cleaning work, and acknowledges the revision only after the database commit succeeds.

Phone test: double-click `START_ROSA_PHONE.bat`, keep the PC and phone on the same trusted Wi-Fi, and open the `PHONE URL` printed by the launcher on the phone. If Windows Firewall asks, allow Python on **Private networks only**. See `PHONE_TEST.md`.

Demo accounts:
- Owner: `owner@demo.rosa` / `rosa-owner`
- Cleaner: `cleaner@demo.rosa` / `rosa-cleaner`
- Maintenance: `maintenance@demo.rosa` / `rosa-maintenance`


## V2.10.84 changes

- Maps Hungarian visible-text OCR into the actual guest check-in form, including when OCR puts labels and values on separate lines.
- Adds a visible expiry-date input and includes its value in the encrypted sensitive guest-data payload.
- Improves Hungarian sex and identity-card detection, and fixes scan-status updates after the form is re-rendered.
- Adds regression tests that verify parsed values are present in rendered input fields, not only in raw OCR text.
- Automated checks pass; physical-phone validation remains required.

## V2.10.43 changes

- Fixes Channex certification Test 9 when the test baseline is prepared directly in the Channex UI.
- Before creating a certification-workspace reservation, Rosa reads the current Channex room availability for the affected stay dates.
- The remote date-specific availability becomes the local manual baseline for that certification night, so a Double Room baseline of 1 is consumed to 0 even though the configured room inventory remains 4 for Test 10.
- Existing stale queued/retry availability jobs are still discarded before the authoritative reservation delta is sent.
- Added regression coverage for the exact remote-UI baseline workflow.

## V2.10.42 changes

- Fixes Channex Test 9 reservation delivery when an older availability retry is still queued.
- Certification reservation updates now discard stale queued/retry availability payloads before creating the new authoritative reservation delta.
- Prevents an old Double Room availability of 4 from being merged into the Test 9 Double Room 1 -> 0 update.
- Adds regression coverage for the exact stale-retry failure scenario.
- Runtime/health version identifiers are aligned to V2.10.42.

## V2.10.41 changes

- Keeps Channex certification room inventory separate from date-specific manual availability.
- When a reservation is created, a date-specific manual availability is consumed from its existing value before the reservation count is applied.
- Example: Double Room configured inventory 4 + Nov 25 manual availability 1 + one reservation => Nov 25 availability 0, not 3.
- Regression test `test_manual_availability_is_consumed_by_reservation_when_capacity_is_higher` covers the exact Test 9 scenario.
- Runtime/health version identifiers are aligned to V2.10.41 so the running build can be verified after restart.

## V2.10.1 changes

- Added local rate plans and Channex rate-plan mappings for the Casa Rosa apartment structure.
- Extended Channex 500-day Full Sync to publish multiple mapped rate plans in one restrictions request.
- Added durable NTAK/VIZA transport state, VIZA ID-scanner ingestion, and government payload previews.
- Kept government delivery locked until the official NTAK/VIZA developer test artifacts are installed and MTÜ certification is completed.
- Full test suite: 133 passed.


- Adds a real owner-triggered **500-day Channex Full Sync** that sends exactly two batched calls: 500 days of availability and 500 days of rates/restrictions, with Channex task IDs retained in Rosa's durable outbox.
- Adds explicit Channex **429 rate-limit handling** with `Retry-After` support, a minimum 60-second pause, and a persisted pause window so queued updates stop hammering a rate-limited property.
- Keeps normal Channex updates incremental; Full Sync is an explicit recovery/certification action rather than a recurring timer.
- Fixes the V2.9.7 migration test harness and the Channex webhook regression test so the complete automated suite remains green.
- Adds regression coverage for the 500-day Full Sync and rate-limit backoff behavior.

### Channex certification status

Rosa now has the required 500-day Full Sync path and explicit 429 backoff needed for Channex's certification pre-flight. Booking.com staging new-booking and cancellation receiving is already working. Production Channex access is still intentionally not enabled; certification and production authorization remain the next external steps.

## V2.9.10 changes

- Adds one base nightly price per Channex-connected apartment and publishes it across the next 365 days in one action.
- Initializes availability for the same future window from Rosa reservations, while retaining intentional manual closures.
- Extends the published window automatically as each day passes.
- Keeps date-specific prices as overrides when the base price is updated.

## V2.9.9 changes

- A confirmed reservation now closes every occupied night in Channex automatically; its checkout date remains available.
- Reservation changes recalculate both the original and replacement stay, while cancellation reopens only nights with no other confirmed reservation.
- Owner-set availability is stored separately from reservation occupancy, so cancelling a booking cannot reopen a manually closed maintenance night.
- Automatic updates use the existing durable Channex outbox, retry handling, throttling and task tracking.

## V2.9.8 changes

- Keeps the desktop navigation sidebar pinned to the viewport while the main page scrolls.
- Keeps the account card and Rosa Online status visible at the bottom of the screen.
- Preserves the existing mobile slide-out navigation behavior.

## V2.9.7 changes

- Fixes the 100× Channex HUF price error: `42,000 Ft` is now sent as the API integer `4,200,000` and appears remotely as `42,000.00 HUF`, while Rosa continues storing/displaying `42,000 Ft`.
- On upgrade, pending rate jobs are repaired and saved rates are queued once more so rates that already reached Channex incorrectly are corrected automatically.
- Adds regression coverage for the outbound conversion, local whole-forint storage, and upgrade repair.

## V2.9.6 changes

- Minimum-stay updates now use Channex's explicit `min_stay_arrival` restriction, including properties configured to support both minimum-stay modes.
- Any V2.9.5 restriction request already waiting after this warning is repaired and made eligible for automatic retry on startup.
- Partial delivery results now clearly distinguish delivered requests from requests still queued for retry.

## V2.9.5 changes

- Added an owner-facing **Rates & availability** workflow for real operational price, availability, minimum-stay, stop-sell, closed-to-arrival and closed-to-departure changes.
- Rosa persists each date-range change before delivery, then sends one batched Channex request per required endpoint.
- Added a durable outbound ARI queue with six-second per-endpoint throttling, automatic exponential retry and stored Channex task IDs.
- Added visible outgoing-queue and last-delivered status to each mapped property.

## V2.9.4 changes

- Channex reservation modifications now update the OTA-owned HUF total while preserving Rosa's manually managed payment, registration, arrival-time, and special-request fields.
- A one-time migration repairs totals from modifications that V2.9.3 already saved and acknowledged.

## V2.9.3 changes

- Added the real Channex `booking_revisions/feed` receiver with an automatic 60-second fallback poll.
- Added immediate **Check for bookings** controls and clear receiver/acknowledgement status per apartment.
- Added room-type routing, allowing Aqua and Flora to share a Channex property while still reaching the correct Rosa apartment.
- Added durable acknowledgement state and retry safety. Failed acknowledgements never remove the locally saved reservation and redelivery cannot create duplicates.
- Channex webhook notifications now pull the full revision, import it, and acknowledge it after the local transaction commits.
- New, modified, and cancelled reservations automatically refresh cleaner schedules and queue NTAK/VIZA events without overwriting manually enriched reservation fields.

## V2.9 foundation carried forward

- Rosa now keeps its SQLite database in `%LOCALAPPDATA%\Rosa\rosa.db` on Windows, outside the extracted release folder.
- On the first V2.9 launch, Rosa adopts the newest `rosa.db` found in the current or a sibling `rosa-v*` folder when no stable database exists yet.
- Added schema migration 2900 without resetting existing reservations, staff, knowledge, tasks, messages, or configuration.
- Added encrypted provider credential storage; secrets are never returned by the API or included in public integration configuration.
- Added an idempotent provider inbox before the existing reservation preview/apply pipeline.
- Added normalized provider-event intake and Booking.com B.XML/OTA XML staging.
- Added Rosa-managed commercial Booking.com onboarding: buyers enter their property ID and authorize the approved bridge in Booking.com; they never see or supply developer API keys.
- Added a secured Channex webhook receiver for new, modified and cancelled Booking.com reservations, including replay protection and tenant/property isolation.
- Added durable NTAK and VIZA reporting queues. Imported reservation events wait safely until Rosa receives commercial MTÜ certification and the property is configured.
- Booking.com delivery acknowledgement is now implemented after durable reservation saving. Production hosting and Channex certification are still required before live customer traffic.

## V2.8.3.2 carried forward

- Team & Access typography is substantially larger and easier to scan.
- Team & Access is fully localized in Hungarian, including account creation/editing, role explanations, access health and workload.
- Train Rosa has a complete Hungarian UI layer: knowledge labels/categories, configuration state, save flow and authority rules. Stored knowledge text is kept exactly as entered rather than silently machine-translated.
- Simulation/Operating Mode has a complete Hungarian control layer, including mode explanations, notification events and the structured-memory section. Known seeded demo memory is localized for display.
- Maintenance creation UI and known seeded demo maintenance cases are localized for Hungarian display without rewriting stored records.
- `START_ROSA_PHONE.bat` provides a same-Wi-Fi LAN test mode for real phone testing.
- Added a blank data-URI favicon so the old harmless `/favicon.ico` 404 no longer clutters the server log.

## About the red 401 before login

A single `GET /api/me 401 Unauthorized` before login is expected. Rosa asks the server whether a valid session already exists; if none exists, the protected endpoint correctly returns 401 and the login screen is shown. This is not a security failure. After successful login, `/api/me` returns 200.

## AI

Rosa remains local-first. Run `SETUP_ROSA_AI.bat` once in this folder to connect your own optional GPT-5.6 Luna fallback. The API key is stored only in local `.env.local` and is excluded from packaged builds and Git.

## Boundaries

The Channex staging receiver is implemented and testable now. Live Booking.com customer traffic still requires Channex production access, certification, and the property owner's Booking.com connectivity authorization. Government events are queued, but transmitting them is deliberately locked until MTÜ certifies commercial Rosa for NTAK and VIZA and issues the required credentials. Szallas.hu still requires a supported channel-manager contract or its approved interface. Team account creation is real inside Rosa, but transactional invitation email delivery is not connected yet; local builds display setup credentials once for the owner to transfer securely.


Scanner capture fix: automatic capture no longer waits for arbitrary average brightness/contrast thresholds; it attempts local OCR periodically and retries on failure. The glare hint describes image readability rather than claiming glare detection.


Scanner capture improvement: OCR first crops to the visible document guide (accounting for object-fit: cover), then falls back to the full camera frame if no fields are recognised. Guest-facing status now distinguishes OCR not recognising fields from camera capture startup.


## Scanner diagnostic build v2.10.65

This build exposes Tesseract OCR loading, language initialization, and recognition progress in the guest check-in status line. It is intended to identify which OCR stage is stalling on mobile. JavaScript syntax and ZIP integrity should be checked before use; it has not been tested against a physical identity document.


Scanner diagnostic build v2.10.66: OCR now uses the single `eng` Tesseract model for all passes to reduce mobile initialization dependencies. Hungarian field-label parsing still supports accented and unaccented labels.


Scanner diagnostic build v2.10.67: updated Content-Security-Policy to permit WebAssembly compilation used by Tesseract.js (`wasm-unsafe-eval`) and explicitly allow the CDN as a worker source. The scanner status now displays the caught OCR error instead of masking it. This is a targeted fix based on the app CSP; it still requires phone testing.


## V2.10.68 — Hungarian ID scanner targeting

- Adds an explicit document-type choice before the camera opens.
- Hungarian/national identity-card mode uses MRZ-only OCR instead of generic visible-text OCR, preventing card headings and field labels from being inserted as the person's name.
- Only accepts identity-card MRZ results when ICAO check digits validate (or a unique correction validates); otherwise asks the guest to show the back with the three machine-readable lines.
- Fixes document-type selection to use exact values rather than broad substring regexes, which could classify `id_card` as a driving licence.
- Converts MRZ nationality code `HUN` to `Hungarian` for the form.
- This is a targeted software change; real-document and phone-camera testing is still required.


## V2.10.69 — ID MRZ diagnostics

- Adds privacy-preserving MRZ diagnostics for Hungarian identity-card scans. The final status shows the number and lengths of candidate OCR lines and MRZ check-digit outcomes, but never displays the recognized name, document number, date of birth, or raw MRZ.
- This distinguishes camera/crop/OCR failures from parser/check-digit failures before making another recognition change.
- Bumps guest-checkin.js cache version to v15.
- JavaScript syntax and ZIP integrity should be checked before use; real ID/iPhone testing remains required.


## V2.10.70 — MRZ line segmentation and crop tuning
- Adds OCR page-segmentation passes 6, 11, 7 and 13 for ID-card MRZ recognition.
- Upscales the captured frame up to 3x (bounded to 2400 px) before OCR.
- Uses a tighter lower 42% crop for the card's MRZ and retries alternate segmentation modes on that crop.
- Keeps strict ICAO check-digit validation; it does not accept unvalidated identity fields.
- Bumps guest scanner script cache version.
- Requires testing on the target phone and card; no physical ID test was available during this build.


## v2.10.71 — Guided MRZ row capture

- In Hungarian identity-card mode, the camera guide narrows to the three MRZ rows instead of framing the entire card.
- Runs a final row-by-row OCR pass, preserving three row boundaries before MRZ parsing and check-digit validation.
- Keeps validation strict and does not show recognized personal data in diagnostics.
- Verification: JavaScript syntax and ZIP integrity checked; not physically tested against a real ID or phone camera.

## v2.10.72 — Detected MRZ row bands
- Replaced the final equal-third OCR attempt with horizontal ink-band detection and per-band OCR, with fallback segmentation only if the image does not yield 2–3 likely rows.
- Per-row OCR keeps the longest normalized line instead of concatenating multiple OCR lines into one oversized string.
- Tries adjacent-row joins for OCR segmentation errors; document data is still accepted in ID-card mode only when the strict MRZ checks validate.
- This improves MRZ layout handling but does not claim universal coverage of every country's non-MRZ national ID format. Non-MRZ documents need document-specific OCR/barcode/NFC support or manual confirmation.


## v2.10.73 — International document scanner foundation
- Removed the Hungarian-ID-only three-line MRZ gate.
- Whole-document OCR is attempted for every document type; MRZ is an optional enhancement.
- Added auto-detect mode and broader multilingual field-label hints.
- This is a foundation, not a claim of universal accuracy: document-specific OCR, non-Latin scripts, and supplementary fields still need validation with representative test documents.


## v2.10.74 — Persistent OCR worker and scan timing
- Replaced repeated one-shot `Tesseract.recognize()` calls with a persistent Tesseract.js worker for the lifetime of the guest-check-in page. The old call pattern could repeatedly initialize workers and reload model resources for every OCR pass.
- Added elapsed-millisecond diagnostics per visible-text and MRZ pass without exposing recognized personal data.
- Explicitly resets OCR parameters between general-text and MRZ passes so the MRZ character whitelist does not leak into visible-field OCR.
- Bumped guest-check-in script cache version to v18.
- Validation: JavaScript syntax and ZIP integrity checked. Device performance and extraction accuracy still require a real-phone test.


## V2.10.76 changes

See `MILESTONE_V21076.md` for the scanner latency and partial-MRZ changes. This is an experimental build; test with synthetic/demo data where possible and verify every extracted field manually.


## V2.10.78 scanner name guard

- Preserves the faster single-pass OCR workflow from v2.10.77.
- Adds conservative name plausibility checks for both visible-text OCR and MRZ-derived names.
- Rejects heading-like text, long concatenated OCR tokens, numeric noise, and implausible token counts rather than inserting them into the guest name field.
- This guard intentionally prefers leaving a name blank for manual review over populating a likely false name.
- Syntax and archive checks do not establish real-document accuracy; test on the same document and verify every field.


## v2.10.81 — Always-visible scanner diagnostics
- Fixes a diagnostic-display bug: the failure details were only displayed when `id_card` was explicitly selected. Auto-detect mode (the default) hid the OCR timing, line lengths, field flags, and MRZ validation status.
- No OCR algorithm or field-extraction logic changed. This is a diagnostic build to expose why the current scan yields no fields, not a claimed extraction fix.
- Bumped guest-check-in JavaScript cache version to v23.


## v2.10.83

Adds multilingual, mid-line visible-field label parsing and Hungarian date-order support. This is a targeted parser improvement, not a claim of universal document support.


## v2.10.83

Adds tolerant bilingual visible-field parsing, including Hungarian labels and day-first dates. Not a claim of universal document support.

## Latest scanner update — v2.10.86
See `MILESTONE_V21085.md`. The guest ID flow now captures a still image on button press, displays a processing overlay during local OCR, writes extracted values into existing visible form controls, and omits document expiry from the guest-facing form/payload. Real-phone validation is still required.
