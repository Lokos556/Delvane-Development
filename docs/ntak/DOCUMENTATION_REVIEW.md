# NTAK v9 documentation review and first implementation batch

Date: 2026-11-18. This is a partial implementation, not the completed integration,
an official validation result, or permission to transmit. Network transmission
remains disabled. No credentials were generated or read and no database was reset.

## Supplied source material

All seven files under `docs/ntak/v9` were inspected:

| Material | Finding |
|---|---|
| `ntak-pms-interface-v907-eng-1794401423 (1).pdf` | 260 pages; title/version 9.07, 28 November 2025; document control says “Request for comment”. This is the supplied authority, not a verified later version. |
| `pms-interface-v8-ertekkeszletek-magyarazata-hun-eng-1777453678.pdf` | Two-page HU/EN explanations of accommodation types, sales channels and market segments. Its filename says v8; v9 machine values come from the supplied v9 schemas. |
| Five `PMS … v9 WSDL.txt` files | Each has one embedded, independently compilable XSD. No `xs:import`, `xs:include`, `xs:redefine` or WSDL imports. No separate XSD files are needed to compile these contracts. |

The stay-event, reservation-event and daily-close files begin with a browser's
“This XML file does not appear…” sentence. The loader removes exactly that known
sentence in memory. Source files remain unchanged. Each WSDL uses SOAP 1.1,
document/literal binding, empty SOAPAction and the example service address
`http://localhost:8082/ntak/v9`. That address is NOT an issued test endpoint.

The PDF includes the country-code, charge-category, extreme-value and postal-code
appendices; those should not be requested again as missing external files.

## Exact unresolved contract requirements

1. **Final information-query result is absent from the supplied response schemas.**
   PDF section 7.3.3, page 46, says the successful verification result returns
   `elvartAdatszolgaltatasKezdoDatuma`. The information WSDL's
   `adatszolgaltatasKezdoDatumResponse` permits a processing ID or error/warning
   lists only. The verification WSDL's `UzenetValaszokType` permits only
   `feldolgozasAzonosito`, `statusz`, `figyelmeztetesLista`, `hibaLista`.
   There is no extension point or declaration for the date in any supplied WSDL.
   A regression test proves that adding the date causes schema rejection.
   Needed: the matching official verification/result WSDL/XSD or an official
   clarification describing the exact response element, nesting, namespace and
   way to retrieve the start date. Do not add this field to the supplied XSD locally.
2. **Information-query interval is underspecified.** PDF pages 41–42 describe
   a queried interval (normally up to 31 days within 15 months), but the supplied
   request has only message, software and provider identity groups. Needed:
   clarification whether the interval paragraph is obsolete or a different request
   contract is missing. No guessed interval elements were implemented.
3. **Signing example conflicts with prose.** Pages 61–62 repeat a Timestamp ID
   and show references to Timestamp and Body; page 63 says one Body reference.
   The prose requires exclusive canonicalization, permitted RSA SHA-256/384/512,
   direct X509 token reference and a 300-second timestamp window. A production
   implementation must not copy the duplicate ID or 12-hour example literally.
   Obtain confirmation of the normative signature reference policy/test vector
   before claiming exact signing-profile interoperability.
4. Issued HTTPS test endpoint URLs, signed universal certificate and trust-chain
   details remain pending as already expected. Existing VPS key/CSR must be reused.

These gaps do not mean all schema work is blocked. They prevent calling the
complete five-operation workflow verified and ready. This batch implements the
unambiguous contract boundary and repairs the existing preview; transport,
signing and automated reporting have not been enabled or claimed complete.

## Implemented changes

- `ntak_contracts.py`: isolated offline contract loader, compilation of all five
  embedded schemas, operation/root checks, request/response validation, UTF-8 SOAP
  envelope construction, schema-derived enum inventory and source hashes.
- Existing `app.py::_ntak_start_date_request_xml` now uses the official information
  schema. Removed the unofficial `szallasNev` and `szallashelySzolgaltatoNev` nodes.
  Missing software version/identity is an explicit HTTP 422, not a guessed version.
  Eleven tax-number digits can be formatted as `12345678-1-12` without changing
  their values. The supplied official test identities are not hardcoded.
- `requirements.txt`: `lxml>=6,<7` for actual XSD validation (installed 6.1.3 locally).
- `tests/test_ntak_contracts.py`: offline contract and XML security regressions.
- `docs/ntak/DOCUMENTATION_REVIEW.md` and `CONTRACT_INVENTORY.json`: findings,
  unresolved requirements, repeatable commands, schema provenance and enumerations.

This preview remains an **unsigned start-date request**, not a reservation report.
The existing preview API's historical reservation-preview name does not establish
reporting coverage. The new validator can validate all five message contracts,
but no new business-data serializers, submission worker or UI management flows
were implemented in this batch.

## Requirements-to-implementation matrix

| Requested capability | Current state |
|---|---|
| All five supplied schemas and enums | Loaded and validated offline; no external schema dependencies |
| Information request | Existing unsigned preview corrected and schema validated; final result contract unresolved |
| Verification, stay, reservation, daily-close operations | Contracts compiled; no operational send/receive implementation |
| Property configuration | Existing government connection rows retained; not yet extended to complete v9 configuration |
| Certificate lifecycle, mTLS, signing | Not implemented in this batch; no replacement key/CSR generated |
| Durable queue and history | Existing government outbox retained; not yet an NTAK protocol state machine |
| Automatic events/daily closure | Not enabled; missing mandatory PMS mappings must block, not fabricate facts |
| Retry/reconciliation | PDF distinguishes receipt from success; confirmed server-error retry delays are 1/10/60 minutes, not generic unlimited retry. UJRA_KULDENDO requires its documented resend/version rules. Not yet implemented. |
| XML security | DTD/entities prohibited; external schema loading prohibited; parser networking disabled; size/depth guards; safe validation errors without guest values |
| Tenant authorization | Existing API owner/manager checks retained; no new cross-property endpoints |
| Flutter management | Existing government status interface retained; full management interface not yet implemented |
| Database changes | None; no migrations or operational database access |
| Official certification | Not performed; no external NTAK calls |

## PMS data work still required

The existing event snapshot is not a complete NTAK payload. It contains reservation
dates/count/status/source and limited guest data. Before automation, audit and add
explicit mappings for accommodation units/buildings/types and capacity; sales
channel/market segment; genuine arrival/departure/room-change facts; guest hash
inputs and frozen reporting identity; residence country/postcode, sex and IFA
status; daily capacity/inventory and operating status; itemized charges/payments,
VAT/IFA, official categories and correction reasons/version records. This is an
initial gap inventory, not a completed field-by-field legal compliance audit.

Neither guest-registration completion nor scheduled arrival time proves actual
arrival. Neither a reservation total nor an unpaid balance is a complete daily
charge/payment ledger. No defaults were introduced to fill those gaps.

## Local verification

From `C:\Delvane\Delvane-Development`:

```powershell
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python -B -m ntak_contracts
.\.venv\Scripts\python -B -m pytest tests/test_ntak_contracts.py tests/test_v3010.py -q
.\.venv\Scripts\python -B -m pytest tests/test_ntak_contracts.py tests/test_v3010.py tests/test_v3000.py tests/test_flutter_reservation_reception.py tests/test_flutter_distribution.py tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_persistent_development.py -q
```

These tests use the existing temporary-database/network isolation guards. They do
not start/reset the persistent workspace. The contract inventory command does not
import the backend or open a database.

Results: focused contract/legacy-preview tests **21 passed**. Broader guarded
backend run **49 passed, 1 failed**, with two dependency deprecation warnings.
Failure: `test_v3000.py::test_viza_id_scan_requires_owner_verification_before_queueing`
expects `pending`, but receives `incomplete`. The tested scanner path was not
modified; this failure remains reported rather than changing guest business rules
to make the assertion pass. Newer guest lifecycle, reservation, distribution and
persistent-workspace tests in the same run passed.

Flutter analysis: clean. Full Flutter suite: **272 passed**.
Flutter 3.50.0 / Dart 3.14.0 retained. No Android/Windows builds or physical-device
tests are claimed for this backend-only batch. No message-signature tests or mock
SOAP transport tests are claimed; there is no transport implementation yet.

## Before future Hetzner deployment

No deployment was performed or is ready. First resolve the official contract
questions, complete the remaining mapping/queue/security/UI work and offline tests,
then validate with the issued test credentials. The future isolated service needs
its own test database/storage, explicit test property/software identities, issued
HTTPS endpoints/trust chain, access to the existing private key with restricted
service-user permissions, matching signed certificate, synchronized UTC clock,
durable worker scheduling and restart recovery, and redacted audit/diagnostic logs.
Production must have separate credentials, property registration/configuration,
database and explicit deployment controls. Do not deploy this partial batch as an
operational NTAK reporting adapter.


## Tasks3–5 follow-up — 2026-11-19

See [TASKS3_5_IMPLEMENTATION.md](TASKS3_5_IMPLEMENTATION.md) for the current implementation; the initial-batch-only matrix above is historical. The issued test endpoint from ticket150337 remains documented in VALIDATION_READINESS.md; transmission stays disabled.

Additional specific blocker: interface9.07 section9.1.1–9.1.3 pp57–59 prescribes UTF-8, SHA256 hexadecimal input to bcrypt with a permanent property salt, final31 characters and frozen ID reuse after correction. That algorithm/example is verified. The supplied translated name description differs from the example concatenation and supplies no comprehensive international name-order/normalization rules. `guest_reporting.identity_for_submission` isolates the missing canonical identity policy: no first identity is derived without a canonical result from a future approved internal adapter; existing frozen identities remain stable. Normal guest profile storage, effective IFA corrections and review remain available. No owner-facing hash input or schema modification bypasses this gate.

ELO_01B continues to block specifically on EGYEBKULFOLDI versus supplied OrszagKodType. Statutory IFA mappings pp79–80 are implemented; property-specific local exemption code mappings not supplied are rejected rather than guessed. Imported reservations missing an actual original provider booking timestamp remain usable in PMS with reporting blocked; local ingestion time is not substituted.
