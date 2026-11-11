# Rosa AI v2.10.38 — Channex certification unchanged-availability resend

- Added an explicit `force_availability` option to the Channex ARI update endpoint.
- The option is honored only for the dedicated Channex certification workspace, so production integrations keep the safe unchanged-value no-op behavior.
- The certification ARI screen exposes the resend option and enables it by default in the certification workspace.
- This allows Channex certification Test #10 to make the second availability update even when the requested value already equals Rosa’s current state.
