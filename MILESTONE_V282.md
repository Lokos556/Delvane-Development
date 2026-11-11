# Rosa V2.8.2 milestone — Team & Access

## Goal
Turn Team from an upcoming-cleaning list into a real staff administration and access-control workspace.

## Delivered
- People / Access & roles / Workload views.
- Owner-created accounts for owner, manager, cleaner and maintenance roles.
- Hashed generated setup passwords displayed once.
- Staff contact + job-title fields.
- Active/suspended lifecycle; suspension revokes sessions.
- Password access reset + session revocation.
- Read-only manager visibility; account mutation remains owner-only through `users.manage`.
- Backend-derived access matrix and security posture.
- Per-person upcoming cleaning, open maintenance, in-progress work, completion history and last sign-in.
- Schema migration 2820 (`team_and_access_workspace`).

Local URL: `http://127.0.0.1:8818`.
