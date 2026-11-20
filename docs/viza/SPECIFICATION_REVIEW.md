# PMS-THF-VIZA v700 specification review

Audit date: 2026-11-20. Documentation and read-only source review only. No application logic, migration, credentials or NTAK checkpoint was changed. No official service was contacted. Neither VIZA integration nor official validation is complete.

## Source and completeness

Authority for this audit: [pms_thf_viza_if_v700_hu.pdf](pms_thf_viza_if_v700_hu.pdf), title PMS-THF-VIZA fejlesztoi csatlakozasi segedlet, v700, 2024-02-22, **57 pages**. SHA-256: `4946453bec2af4297316fd0f206c78d1271bdf9bd5ed40ea1f93840665c778b9`. Page references below use PDF/printed page numbers, which agree. All pages, embedded WSDL and examples were inspected; page13 is intentionally blank. Architecture and validation tables were also rendered for visual checks. These are the rules in the supplied version, not an independent assertion about later legal/specification updates.

The WSDL is printed in section5, pp28-43; the PDF has no embedded file attachment. An audit-only extraction removed standalone PDF page numbers, preserving XML declarations/definitions. Its **one embedded XSD compiles with lxml**, has no WSDL imports or XSD import/include/redefine dependencies, and exposes four operations. Extraction, renders and validation diagnostics are ignored intermediates under `build/viza-audit`, not a production adapter or an additional deliverable.

| Operation | Request/response | Contract |
|---|---|---|
| `allapotLekerdezes` | Empty request; software version, status codes, unsent/rejected counts and timestamp | Sec4.1 pp9-10; sec5 pp29-30,41-43 |
| `erkezesiAdatokBekuldese` | Header plus1-10 guests, each with a separate arrival UUID, source-separated identity and optional-value third-country fields | Sec4.2 pp10-12; sec5 pp28,31-36 |
| `tavozasiAdatokBekuldese` | Header plus1-10 arrival UUID/actual-departure timestamp pairs | Sec4.3 p14; sec5 pp28-29,37 |
| `bekuldetlenAdatLista` | `NEMBEKULDOTT` or `HIBAS`; result code and0-10000 items containing message UUID, property reporting ID and optional error | Sec4.1 p10; sec5 pp30-31,40-43 |

SOAP1.1, document/literal, empty SOAPAction; namespace `http://vizainfo.hu/thf/v1`. The endpoint in sec4 p9 is HTTPS `/ws`; v700 names `https://thf-uat.thf.hu/ws` as developer test THF. The WSDL p43 instead embeds an HTTP private-IP address. It is an example contract address, not authority to contact or configure that host. No URL was opened.

## Architecture and security requirements

- **PMS -> THF -> VIZA**, not PMS -> VIZA. Only THF requests the statutory encryption keys, encrypts for VIZA and forwards; successful downstream packages are not retained by THF. PMS must monitor failures retained there. Reuse local encrypted storage for PMS needs; do not implement a competing VIZA/key-service sender. Sec1.1 pp3-4; sec2 pp5-6.
- THF may run on the PMS infrastructure or infrastructure connected over a protected channel. The installation procedure is a separate document, not included here. Sec2 p5. A local `module_path` string in existing code is not proof that this deployment exists or is correctly configured.
- PMS authenticates and signs SOAP with the NTAK client/signing certificate arrangements; THF supports valid PMS certificates for multiple properties. THF validates PMS certificates through OCSP/CRL with a24-hour validity cache for that result. Do not mistake this THF responsibility for an already implemented PMS revocation policy. Sec3.1 p7.
- Guest-bearing messages also carry `pmsValidaciosUzenet`: property8-character `adatszolgaltatasiAzonosito` (certificate CN), all included arrival UUIDs in their message order, and the exact `bejelentesIdopontja` joined with `|`. Sign using RSA-SHA256; attach Base64 signature and Base64 DER public signing certificate. No trailing newline in the signed string. This is distinct from outer WS-Security. Sec3.2-3.3 pp7-8; `BekuldesFejlecType` pp31-32, `ValidaciosUzenetType` p38; EF0200-0209 pp49-50.
- PMS must validate THF server authenticity using the operator-supplied issuer/root CA certificates; do not bypass TLS/hostname verification. Sec3.4 p8. Existing `government_security.py` supplies reusable primitives, not a completed THF trust/security adapter. Do not assume the NTAK10-character accommodation registration number is this8-character CN/reporting ID.
- Request examples have WS-Security Timestamp, X509PKIPathv1 token and Body signature; response examples show X509v3, signed Body/Timestamp/SignatureConfirmation. These examples are not a sufficient interoperable security policy: see discrepancies below. Sec3.1 p7; sec4.4 pp15-27.

## Business fields, provenance and validation

| Requirement | Exact rule from supplied source | Citation |
|---|---|---|
| Header | `uzenetAzonosito` UUID; property reporting ID, accommodation/provider names and tax number; timezone-bearing report timestamp; property-validation signature block | Sec5 pp31-32,38-40; sec6.1 pp44-45 |
| Property identity | Reporting ID8 alphanumeric characters; names max200 characters; tax number schema `[0-9]{8}-[0-9]-[0-9]{2}`. Do not copy unrelated NTAK property/software identifiers automatically. | Sec3.2-3.3 p8; sec5 pp39-40; EF0005-0013 p44 |
| Per-guest visit | `erkezesAzonosito` is unique per arrival, reused to reference that arrival on departure. It is not the group message UUID, booking ID or NTAK frozen guest hash. Lowercase UUID syntax is defined. | Sec2.2 p5; sec4.2 p11; sec4.3 p14; sec5 pp34,37,39 |
| Arrival time | Offset-aware actual arrival timestamp; expected departure DATE based on booking. Reporting timestamp and actual arrival are different facts. | Sec4.2 p11; sec5 p34; EF0015-0016 pp44-45; EF0029-0033 pp45-46 |
| Original scans | Send unchanged reader-derived fields in `okmanybolBeolvasottAdat`; preserve originals even when later manually corrected. Field-by-field provenance matters; document images are not required by this interface. | Sec1.1 pp3-4; sec4.2 pp10-12 |
| Manual/corrected fields | Put manually entered or corrected values in `manualisanRogzitettAdat`. When correcting surname OR given name, include BOTH components in that manual group, including the unchanged partner. Same rule for birth-name and mother's-name pairs. Never infer international name splits from `full_name` automatically. | Sec4.2 p11; EF0034-0042 p46; EF0052-0055 p47 |
| Name fields | `csaladnev`, `utonev`, `szuletesiCsaladnev`, `szuletesiUtonev`, `anyjaCsaladnev`, `anyjaUtonev`. Main manual names required when no scanned name supplies them; manual pair-presence rules also apply. | Sec4.2 pp11-12; `SzemelyAdatType` pp35-37; sec6.1 pp46-48 |
| Birth date/place | Date must be real, nonfuture and within parameterized110-year bound; manual date needed when unavailable from reader. Birthplace has a length limit, not an unconditional mandatory rule; v500 change log removed its missing-field error. | Change log p3; sec6.1 pp46-48 |
| Other identity fields | Nationality code and sex must be represented according to source/validation rules; sex values `NO`, `FERFI`, `EGYEB_VAGY_NEM_ISMERT`. Do not fabricate an unknown field as if it had been scanned. | Sec4.2 pp11-12; sec5 pp36-39; EF0059-0062 p47, EF0110-0111 p49 |
| Document type | `SZEM_IG`, `UTLEVEL`, `VEZ_ENG`, `EGYEB`; map UI document types explicitly. MRZ/visible OCR engine/device communication itself is explicitly outside this specification. | Sec1.1 p4; sec4.2 p12; sec5 p39; EF0063-0067 p47, EF0112-0113 p49 |
| Under14 | Document type/number optional for guests who have not reached14 on the actual ARRIVAL date, not report date or today's date. Other field rules remain. Do not reuse NTAK's under18 IFA threshold. | Sec6.3 p50 |
| Country set | Nationality uses accepted alpha2 codes; appendix gives291 alpha2/alpha3 pairs, including special codes. It is not the same set as `ntak_countries.COUNTRIES`. Preserve original code and map only unambiguous pairs. | Sec4.2 pp11-12; sec5 p39; sec6.4 pp50-57 |
| Third-country fields | `vizumEngedelySzam`, `beutazasDatuma`, `beutazasHelye` where relevant. Schema requires these elements but allows xsi:nil; it does not make them omitted optional elements. Entry date cannot be future. Applicability is not reduced to a documented simple nationality predicate. | Sec1.1 p3; sec4.2 p12; sec5 pp34-35; EF0069 p47, EF0072/0075 p48 |
| Null/optional | Scanned/manual groups each have minOccurs0. If present, their12 fields have required element presence and nillable values; absence of data is different from an invalid empty date/enum. Third-country fields are also required/nillable. | Sec5 pp34-37 |
| Length limits | Names/birthplace/entry place:200 characters AND254 UTF8 bytes. Document/visa number:100 characters. These business constraints are not all encoded as XSD facets. | Sec6.1 pp46-49 |
| Timing/batches | Header report time cannot be future; stated history parameter730 days. Arrival stated range730 days past/1 day future; expected departure bound references365 days; departure365 days past/1 day future and later than arrival when known. Parameter wording is not license to hardcode guessed deployment settings. Batch1-10. | EF0015-0033 pp44-46; EF0088-0089 p49; sec5 pp28-29 |
| Result persistence | Save `sikeresBefogadas`, `fogadasAzonosito`, `fogadasIdeje`, and per-arrival `hibaLista` results. THF reception is not proof of delivery to VIZA. Correlate message UUID, each arrival UUID, property and receipts separately. | Sec2.3 p6; sec5 pp32-33 |
| Erroneous arrival | Send departure referencing the erroneous arrival UUID. That arrival UUID must never be reused; a later real arrival needs a new UUID. Already-submitted data cannot be edited/replaced as a normal correction. | Sec6.2 p50 |
| Late arrival | Report real actual time; if retrospectively unknowable the source specifies arrival-day12:00. Current PMS requires an explicit actual timestamp; future supported fallback must have explicit operator/source provenance, never silent scheduled-time inference. | Sec6.2 p50; actual core `guest_stays.apply` |

## Monitoring, retry and errors

THF outages must not stop PMS guest operations; save durable work and catch up. Sec4 p9. Sec6.2 p50 recommends three immediate attempts, then random1-60 seconds,10 minutes,1 hour,6 hours, then every24 hours continuously. This is **not NTAK's1/10/60-minute policy**. Distinguish definitely-not-sent failures from a timeout after possible receipt; v700 does not define a complete safe uncertain-outcome protocol.

Poll `allapotLekerdezes` every1-60 minutes and visibly show unsent/rejected counts, timestamps and THF health. Primary codes are OK/WARNING/ERROR. Additional codes: VIZA-OFFLINE, KM-OFFLINE, OUTOFKEYS, RA-OFFLINE, CERT-WARNING, CERT-EXPIRED, CERT-RENEWED, RESTART-THF, DATA-REJECTED. Codes may coexist separated by `|`. CERT-WARNING's stated window is30 days; this differs from the existing generic3-day local certificate status helper. Rejected downstream records remain for support processing; do not blindly retry permanent data errors. Provide operator retrieval of both unsent and rejected lists. Sec4.1 pp9-10; `BekuldetlenAdatType` p40.

The complete supplied error table has **73 distinct codes**; preserve multiple errors, original codes, safe structured fields and authorized diagnostic text, not only a single generic last_error:

| Page | Codes inspected | Principal scope |
|---|---|---|
| 44 | EF0001,0003,0005,0006,0008,0009,0010,0011,0012,0013,0015 | Header UUID/property/provider/report time |
| 45 | EF0016,0017,0018,0019,0020,0021,0029,0030,0032,0033 | Ranges, batches, arrival UUID and duplicate interval; stated duplicate window1 hour is not permanent replay permission |
| 46 | EF0034,0035,0036,0037,0039,0040,0041,0042,0047,0048 | Manual name pairs, UTF8 limits and DOB |
| 47 | EF0051,0052,0053,0054,0055,0059,0060,0061,0062,0063,0064,0065,0067,0069 | Birthplace/mother pair, nationality/sex/document and visa |
| 48 | EF0072,0075,0101,0102,0103,0104,0105,0106,0107,0108,0109 | Entry details and unchanged scanned fields |
| 49 | EF0088,0089,0110,0111,0112,0113,0200,0201,0202,0203,0204 | Departure and certificate/signature checks |
| 50 | EF0205,0206,0207,0208,0209,7050 | Check string, revocation/CRL chain and list selector |

All abbreviated entries in a row retain the EF prefix. The table is not a claim to enumerate every possible TLS, SOAP or future server fault.

## Exact discrepancies / information still needed

| ID | Source and observation | Safe offline boundary / requested clarification |
|---|---|---|
| Q1 | Sec4 p9 HTTPS UAT `/ws` vs WSDL p43 HTTP/private-IP service location | Bind to explicit server configuration; never use the embedded address blindly. Assigned test access/THF provisioning is still needed. |
| Q2 | Sec3.1 p7 delegates SOAP security to NTAK; sec4.4 pp15-27 request examples use RSA-SHA384 with SHA1 Body digest and long timestamps, while responses use SHA384 digests and5-minute timestamps with additional signed references | Need normative WS-Security algorithms, reference/token/response-verification policy and signed interoperability vectors. Do not copy weak/contradictory examples or silently assume unresolved NTAK v9 signing policy resolves VIZA. The separate property RSA-SHA256 check-string algorithm is specified and can be developed offline. |
| Q3 | Arrival example p22 has empty date/country/sex/document-type values; its body fails the supplied XSD. Arrival/departure responses pp24/27 omit required `hibaSzoveg`, also failing XSD | Keep schema unchanged; generate schema-valid nil/required fields. Request matching machine-readable successful/error samples; malformed examples must be negative evidence, not golden successful fixtures. |
| Q4 | `BekuldesValaszType` p32 says multiple errors comma-separated; `EredmenyType` p33 says semicolon-separated | Retain raw protected response and all structured results; obtain authoritative delimiter and multi-error/mixed-batch acceptance semantics. Do not mark an entire batch successful based only on a receipt/global boolean. |
| Q5 | Sec6.2 p50 prohibits correction of submitted data and covers erroneous arrival only; shared NTAK/PMS service supports departure reversal, timestamp correction and transfer | Do not reuse NTAK compensating semantics for VIZA. Need procedure for already-received departure/timestamp/identity mistakes. Preserve factual PMS corrections but block unsupported VIZA execution. Room transfer alone must not invent a new VIZA visit. |
| Q6 | Sec6.1 EF0033 pp45-46 expects expected-departure date later than arrival; no explicit same-day/day-use exception is given, although the XSD date permits it | Keep true PMS day-use unchanged; obtain THF same-day rule and test example. Gate affected VIZA report if safe business validation cannot be established; do not add a fake overnight. |
| Q7 | Sec4.1 p10 list capped10000 in WSDL p31; no paging protocol or per-message final-delivery lookup is defined. Delivered records are removed by THF (p6). EF0021 p45 covers a1-hour duplicate window | Need recovery/correlation procedure for uncertain sends, mixed batches, late duplicate requests and counts above list cap. Absence from a list alone is not individual delivery proof. Other durable queue/polling work is implementable offline. |
| Q8 | Country appendix p55 maps NLD to both NL and BQ; p57 uses XK/XKA, while existing scanner accepts XKX. Special AA/QM.../ZZ codes have no country-name explanation | Preserve exact original codes; no ambiguous inverse lookup or invented meanings. Build the supplied accepted set separately from NTAK; request ambiguity guidance where needed. |
| Q9 | Intro p3 document-contained starred fields, validation pp46-49 fallback requirements and parameter descriptions need careful reconciliation; third-country applicability is not enumerated | Implement unambiguous field/age/pair/format rules. Obtain exact applicability/parameter/error examples for affected edge cases rather than changing official schemas or fabricating fields. |

Additional artifacts not supplied: separate THF installation/operations guide (sec2 p5), issuer/root CA files (sec3.4 p8), actual test assignment/credential/property bindings, and official validation exercises. No official validation scenario identifiers are invented here. The older `NTAK_VIZA_NEXT.md` is historical context, not the v700 contract or proof that local module_path/registration_id checks establish readiness.

See [IMPLEMENTATION_READINESS.md](IMPLEMENTATION_READINESS.md) for code evidence and [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) for bounded offline tasks.

## V05-V07 implementation boundary update

The unambiguous property signature, local TLS/credential binding, durable mock delivery/monitoring and administration work are implemented in [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md). This does not resolve Q1-Q9. In particular Q2 still blocks every real exchange; Q4 mixed receipts and Q7 uncertain outcomes/list caps retain explicit holds. No official schema or supplied PDF was amended, and no official service was contacted.
