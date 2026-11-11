# Rosa V2.5 quick test

Run `START_ROSA.bat`, then use the Owner demo.

## 1. Today
Confirm the first screen feels like an operating command center: arrivals, departures, turnovers, registration risks and maintenance should all be visible and actionable.

## 2. Reservation workspace
Open Reservations and click an existing stay (for example Daniel Weber / Terra). Check the four tabs:
- Stay overview
- Preparation
- Communication
- Activity

Change arrival/payment/registration details, save, add an internal note, and confirm the activity history updates.

## 3. Cleaner
Sign out and use the Cleaner demo. Open a cleaning task, tick checklist items, Start Cleaning, then complete the list and Finish Cleaning. The progress bar should persist after navigation/reload.

## 4. Maintenance
Use the Owner or Maintenance demo and move an issue through:
`Reported/Assigned → In progress → Resolved`.
Owner should then be able to `Verify` it. The maintenance worker must not be able to self-verify.

## 5. Security
Owner → Casa Rosa account card → Security. Confirm the V2.5 Production Core panel shows:
- environment: development
- database: sqlite
- schema: 2500
- version: 2.5.0

The local build intentionally reports secure cookies as local/off. Production refuses to start that way.

## 6. Existing V2.3 sync sandbox
Integrations still contains the fake Booking.com/Szallas.hu pipeline. New/change/cancel/outage/iCal simulation should continue to work.
