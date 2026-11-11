# Rosa V2.9.7 — Channex HUF Rate Test

1. Start Rosa and open **Owner tools → Integrations**.
2. Open **Rates & availability** for the mapped Aqua property.
3. Choose a future date and enter `42000` as the nightly price.
4. Save the update and wait for the delivered confirmation.
5. Open Channex Inventory for the same property, rate plan, and date.
6. Confirm Channex shows `42,000.00 HUF`, not `420.00 HUF`.

Rosa should continue showing the nightly price as `42,000 Ft`.
