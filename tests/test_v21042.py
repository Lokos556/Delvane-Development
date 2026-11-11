import json
import sqlite3

from test_v21027 import cert_fixture
import app as rosa


def test_cert_reservation_drops_stale_availability_jobs_and_sends_only_authoritative_zero(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    double_id, double_remote, _ = rooms[1]
    target = "2026-11-25"
    now = rosa.now_iso()

    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        property_id = con.execute(
            "SELECT property_id FROM integrations WHERE id=?", (iid,)
        ).fetchone()["property_id"]

        # Test 9 precondition: Double has four configured units, but this
        # particular night is manually reduced to one before the booking.
        con.execute(
            """INSERT INTO channex_room_type_values
               (id,organization_id,integration_id,room_type_id,stay_date,availability,manual_availability,reservation_availability,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?)
               ON CONFLICT(integration_id,room_type_id,stay_date) DO UPDATE SET
                 availability=excluded.availability,manual_availability=excluded.manual_availability,
                 reservation_availability=excluded.reservation_availability,updated_at=excluded.updated_at""",
            (rosa.new_id("rtv"), "org_casa_rosa", iid, double_id, target, 1, 1, 1, now),
        )

        # Simulate the exact stale retry that caused the real failure: an older
        # job still contains availability 4 for this room/date.
        stale_payload = {
            "values": [{
                "property_id": "remote-cert",
                "room_type_id": double_remote,
                "date_from": target,
                "date_to": target,
                "availability": 4,
            }]
        }
        con.execute(
            """INSERT INTO channel_ari_outbox
               (id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at)
               VALUES (?,?,?,?,?,'retry',3,?,'[]',?,?,NULL)""",
            (
                rosa.new_id("ariq"),
                "org_casa_rosa",
                iid,
                "/api/v1/availability",
                json.dumps(stale_payload),
                now,
                "stale max-availability failure",
                now,
            ),
        )
        con.commit()

    calls = []

    def fake_request(path, method="GET", payload=None):
        calls.append((path, method, payload))
        return {"data": [{"id": "task-availability"}]}

    monkeypatch.setattr(rosa, "_channex_request", fake_request)

    response = client.post(
        "/api/reservations",
        json={
            "property_id": property_id,
            "room_type_id": double_id,
            "source": "Direct",
            "guest_name": "Test Channex",
            "arrival_date": target,
            "departure_date": "2026-11-26",
            "guest_count": 2,
            "total_huf": 100,
            "payment_status": "unknown",
            "registration_status": "incomplete",
            "arrival_time": "15:00",
            "special_requests": [],
        },
    )
    assert response.status_code == 200, response.text

    availability_calls = [p for path, _, p in calls if path == "/api/v1/availability"]
    assert len(availability_calls) == 1
    values = availability_calls[0]["values"]
    assert values == [{
        "property_id": "remote-cert",
        "room_type_id": double_remote,
        "date_from": target,
        "date_to": target,
        "availability": 0,
    }]

    with sqlite3.connect(db_file) as con:
        stale = con.execute(
            "SELECT COUNT(*) FROM channel_ari_outbox WHERE integration_id=? AND endpoint='/api/v1/availability' AND status IN ('queued','retry')",
            (iid,),
        ).fetchone()[0]
        assert stale == 0


def test_cert_reservation_consumes_current_channex_date_baseline_when_remote_ui_set_to_one(
    tmp_path, monkeypatch
):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    double_id, double_remote, _ = rooms[1]
    target = "2026-11-25"
    property_id = None

    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        property_id = con.execute(
            "SELECT property_id FROM integrations WHERE id=?", (iid,)
        ).fetchone()["property_id"]

    calls = []

    def fake_request(path, method="GET", payload=None):
        calls.append((path, method, payload))
        if path.startswith("/api/v1/availability?"):
            return {
                "data": {
                    double_remote: {target: 1},
                }
            }
        return {"data": [{"id": "task-availability"}]}

    monkeypatch.setattr(rosa, "_channex_request", fake_request)

    response = client.post(
        "/api/reservations",
        json={
            "property_id": property_id,
            "room_type_id": double_id,
            "source": "Direct",
            "guest_name": "Test Channex Remote Baseline",
            "arrival_date": target,
            "departure_date": "2026-11-26",
            "guest_count": 2,
            "total_huf": 100,
            "payment_status": "unknown",
            "registration_status": "incomplete",
            "arrival_time": "15:00",
            "special_requests": [],
        },
    )
    assert response.status_code == 200, response.text

    availability_calls = [
        p for path, _, p in calls if path == "/api/v1/availability"
    ]
    assert len(availability_calls) == 1
    assert availability_calls[0]["values"] == [{
        "property_id": "remote-cert",
        "room_type_id": double_remote,
        "date_from": target,
        "date_to": target,
        "availability": 0,
    }]

    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        row = con.execute(
            """SELECT availability,manual_availability,reservation_availability
               FROM channex_room_type_values
               WHERE integration_id=? AND room_type_id=? AND stay_date=?""",
            (iid, double_id, target),
        ).fetchone()
        assert tuple(row) == (0, 1, 3)
