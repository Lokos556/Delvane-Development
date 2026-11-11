# Rosa v2.11.10 — Calendar and mobile Reception rebuild

- Replaced the reservation page with a full-width month grid; no property-name rail on the left.
- Reservation chips are color-coded by property, strongly contrasting, and open the existing reservation workspace.
- Day numbers are touch targets for creating a reservation with that arrival date prefilled.
- Added a property color legend and workspace shortcuts below the calendar.
- Mobile Reception now follows an inbox-list → full-screen message → back-to-list pattern, similar to Gmail on phones.
- Updated CSS/JS cache-busting and service-worker cache name.

Validation: `node --check static/app.js` passed; ZIP integrity checked. Browser/device interaction testing has not been performed.
