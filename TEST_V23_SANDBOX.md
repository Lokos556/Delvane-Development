# Quick V2.3 test tonight

1. Start Rosa and log in as Owner.
2. Open the Casa Rosa account card → Integrations.
3. Terra / Booking.com initially shows pending changes.
4. Press **Sync now**. The dry-run should show one CHANGED reservation and one NEW reservation.
5. Press **Apply import**. The new Marta Klein reservation appears in Rosa; downstream actions are recorded in Simulation as simulated because the organization starts in OBSERVE mode.
6. Open a sandbox, create a fake booking, then Sync now → Apply import.
7. Open it again, press **+1 night**, Sync now, and Rosa should classify it as CHANGED.
8. Open it again, cancel it in the feed, Sync now, and Rosa should classify it as CANCELLED.
9. Use **Simulate outage**. Sync now becomes unavailable and the connection reports an error. Recover the feed to continue.
10. Expand **Paste iCal sample** to test a small standard `.ics` calendar event without any real private URL.
