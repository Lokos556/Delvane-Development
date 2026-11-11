import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

from test_v21027 import cert_fixture


def test_availability_delta_and_unchanged_value_noop(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(
        rosa,
        "_channex_request",
        lambda path, method="POST", payload=None: calls.append((path, method, payload))
        or {"data": [{"id": "task-availability"}]},
    )

    twin_id = rooms[0][0]

    response = client.put(
        f"/api/integrations/{iid}/channex/ari",
        json={
            "date_from": "2026-11-21",
            "date_to": "2026-11-21",
            "room_type_id": twin_id,
            "rate_plan_id": plans[0][0],
            "availability": 7,
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["queued"] == 1
    availability_calls = [x for x in calls if x[0] == "/api/v1/availability"]
    assert len(availability_calls) == 1
    assert availability_calls[0][2]["values"][0]["availability"] == 7

    calls.clear()

    response = client.put(
        f"/api/integrations/{iid}/channex/ari",
        json={
            "date_from": "2026-11-21",
            "date_to": "2026-11-21",
            "room_type_id": twin_id,
            "rate_plan_id": plans[0][0],
            "availability": 7,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["no_change"] is True
    assert body["queued"] == 0
    assert not [x for x in calls if x[0] == "/api/v1/availability"]


def test_reservation_cancellation_forces_availability_reconciliation(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(
        rosa,
        "_channex_request",
        lambda path, method="POST", payload=None: calls.append((path, method, payload))
        or {"data": [{"id": "task-cancel-reconcile"}]},
    )

    room_id = rooms[1][0]  # Double Room, inventory 4
    with __import__("sqlite3").connect(db_file) as con:
        prop_id = con.execute("SELECT property_id FROM room_types WHERE id=?", (room_id,)).fetchone()[0]
        now = rosa.now_iso()
        reservation_id = rosa.new_id("res")
        con.execute(
            """INSERT INTO reservations
               (id,organization_id,property_id,room_type_id,source,external_ref,guest_name,
                arrival_date,departure_date,guest_count,total_huf,payment_status,registration_status,
                arrival_time,special_requests,status,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (reservation_id, "org_casa_rosa", prop_id,
             room_id, "Direct", "CANCEL-1", "Cancellation Test",
             "2026-11-25", "2026-11-26", 1, 100, "unknown", "incomplete", None, "[]",
             "confirmed", now, now),
        )
        # Simulate Rosa already holding the recalculated effective value. The
        # cancellation must still produce one outbound availability update.
        con.execute(
            """INSERT INTO channex_room_type_values
               (id,organization_id,integration_id,room_type_id,stay_date,availability,
                manual_availability,reservation_availability,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            (rosa.new_id("rtv"), "org_casa_rosa", iid, room_id, "2026-11-25", 3, 3, 3, now),
        )

    response = client.delete(f"/api/reservations/{reservation_id}")
    assert response.status_code == 200, response.text
    availability_calls = [x for x in calls if x[0] == "/api/v1/availability"]
    assert len(availability_calls) == 1
    value = availability_calls[0][2]["values"][0]
    assert value["room_type_id"] == rooms[1][1]
    assert value["date_from"] == "2026-11-25"
    assert value["date_to"] == "2026-11-25"
    assert value["availability"] == 3
