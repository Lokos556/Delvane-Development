# Delvane — read-only, local-first owner assistant

The active owner conversation remains on the original FastAPI authentication,
conversation tables and /api/rosa routes. It now follows this order:

1. Authorize owner/manager and enforce the existing organization boundary.
2. Interpret supported English/Hungarian lookup phrasing locally.
3. Execute parameterized database queries and render actual records/counts.
4. Optionally ask OpenAI for a schema-validated lookup plan for unfamiliar wording.
5. Execute that plan through the same authorized read-only query layer.
6. Explain unavailable facts, unknown properties or unsupported questions honestly.

No autonomous action, simulated action or approval proposal is created by chat.
Old proposal approval returns a read-only error. Chat/history/audit metadata is
stored; PMS business records are not modified. The conversation GET can initialize
a user's chat metadata, but does not modify reservation or operational records.

The original integration used a 7-day prompt snapshot and free-form Responses API
prose. The current phase bounds factual responses to database-backed lookup types
instead; unsupported judgment, financial analysis and open-ended 'why' reasoning
are not presented as verified facts. Existing stored property knowledge/scalar
lookups, readiness and maintenance facts are reused locally.

Counts include all reservation statuses unless confirmed/cancelled is requested.
Arrivals/departures/upcoming stays use confirmed reservations. This month means
arrival dates in the business calendar month. This week means Monday through Sunday
and checkout questions filter departure dates. Cancellation date filters use planned
arrival dates and explicitly say so; missing cancellation timestamps are not guessed.
Upcoming means arrivals on/after the current business day. Lists are capped at 50
with truncation indicated where applicable.

Next weekend means the next strictly future Saturday arrival and Monday checkout.
Availability checks active room inventory against confirmed overlapping nights;
checkout frees that night. External channel restrictions/live sales are not checked.
Exact dates may be supplied as YYYY-MM-DD pairs (arrival inclusive, checkout
exclusive), with a maximum 366-day availability window. Unsupported relative
periods ask for explicit dates rather than silently broadening the query.

Business dates use organization_settings.timezone (Europe/Budapest by default),
including DST through IANA tzdata. Chat follows the authenticated user's persistent
thread. Supported follow-ups retain lookup type/date/property filters; ambiguous
property scope is rejected without revealing whether an inaccessible property exists.
Owners/managers currently have organization-wide property access under the existing
PMS role model; this change does not invent a narrower property ACL.

See AI_SETUP.md for offline/persistent startup, server-side key opt-in, model
configuration and request limits. No credentials belong in Flutter or web assets.
