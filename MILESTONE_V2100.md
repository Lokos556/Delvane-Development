# Rosa V2.10.1 — Casa Rosa rate plans + government integration foundation

## Implemented

- Added a real local rate-plan model per Casa Rosa apartment.
- Existing single Channex Standard Rate mappings are automatically backfilled into the new mapping table.
- Added rate-plan CRUD/read APIs and Channex rate-plan mapping APIs.
- Channex 500-day Full Sync now supports multiple mapped rate plans in the single restrictions request while keeping availability grouped by room type.
- Added durable government transport state and delivery-attempt storage for NTAK and VIZA.
- Added VIZA ID-scanner ingestion boundary that updates guest registration records and queues the required government event.
- Added NTAK/VIZA preview payload generation from Rosa's durable government outbox.
- Added government worker state handling so events remain durable instead of being falsely marked as delivered before official MTÜ test credentials/modules are installed.
- Schema upgraded to 3000.
- Full automated test suite: 133 passed.

## Important certification boundary

Rosa cannot truthfully claim NTAK or VIZA certification yet. The official developer process first provides the current NTAK developer package/test endpoint and the VIZA storage-forwarding module/unique identifiers after the respective connection requests are accepted. The transport adapters must be completed against those official test artifacts and then pass MTÜ validation.

Official developer process:
- NTAK: test connection questionnaire -> developer package/test environment -> integration test -> certificate.
- VIZA: PMS–THF–VIZA test connection form -> test environment/module/unique ID -> validation test -> certificate.
