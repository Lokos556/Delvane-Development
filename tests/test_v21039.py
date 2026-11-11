import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa
from test_v21027 import cert_fixture


def test_certification_baseline_repair_restores_inventory_from_stale_zero(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    twin_id = rooms[0][0]
    today = date.today()
    stale_days = [today + timedelta(days=i) for i in range(1, 8)]

    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        now = rosa.now_iso()
        for day in stale_days:
            con.execute(
                """INSERT INTO channex_room_type_values
                   (id,organization_id,integration_id,room_type_id,stay_date,availability,manual_availability,reservation_availability,updated_at)
                   VALUES (?,?,?,?,?,?,?,?,?)""",
                (rosa.new_id('rtv'), 'org_casa_rosa', iid, twin_id, day.isoformat(), 0, 0, 8, now),
            )
        # Pretend an older build already ran the previous repair migration. The new
        # migration must still repair this stale state exactly once.
        con.execute(
            "DELETE FROM schema_migrations WHERE version IN (3066,3065)"
        )
        con.commit()
        rosa.ensure_v3065_schema(con)
        rosa.ensure_v3066_schema(con)

        rows = con.execute(
            "SELECT availability,manual_availability,reservation_availability "
            "FROM channex_room_type_values WHERE integration_id=? AND room_type_id=? "
            "ORDER BY stay_date LIMIT 7",
            (iid, twin_id),
        ).fetchall()
        assert all(tuple(r) == (8, None, 8) for r in rows)

        queued = con.execute(
            "SELECT payload_json FROM channel_ari_outbox WHERE integration_id=? AND endpoint='/api/v1/availability' AND status='queued'",
            (iid,),
        ).fetchall()
        assert queued
        values = []
        for row in queued:
            values.extend(json.loads(row[0])['values'])
        assert any(v['room_type_id'] == 'remote-twin' and v['availability'] == 8 for v in values)



def test_certification_mapping_and_max_availability_cap_are_repaired(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    twin_id = rooms[0][0]
    double_id = rooms[1][0]
    now = rosa.now_iso()
    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        # Simulate a stale/wrong Twin mapping and a channel rule that caps Twin at 1.
        con.execute(
            "UPDATE channex_room_type_mappings SET channex_room_type_id=? WHERE integration_id=? AND room_type_id=?",
            ('remote-stale-double', iid, double_id),
        )
        con.execute(
            "UPDATE channex_room_type_mappings SET channex_room_type_id=? WHERE integration_id=? AND room_type_id=?",
            ('remote-double', iid, twin_id),
        )
        con.execute(
            "DELETE FROM schema_migrations WHERE version=?", (3067,)
        )
        con.commit()

    calls = []
    def fake_request(path, method='GET', payload=None):
        calls.append((path, method, payload))
        if path.startswith('/api/v1/room_types?'):
            return {'data': [
                {'id':'remote-twin','attributes':{'title':'Twin Room','count_of_rooms':8,'occ_adults':2,'occ_children':0,'occ_infants':0,'default_occupancy':2,'room_kind':'room'}},
                {'id':'remote-double','attributes':{'title':'Double Room','count_of_rooms':1,'occ_adults':2,'occ_children':0,'occ_infants':0,'default_occupancy':2,'room_kind':'room'}},
            ]}
        if path.startswith('/api/v1/channel_availability_rules?'):
            return {'data': [
                {'id':'rule-twin-cap','attributes':{'id':'rule-twin-cap','type':'max_availability','value':1,'affected_room_types':['remote-twin']}},
            ]}
        return {'data':[{'id':'task'}], 'meta':{'message':'Success'}}

    monkeypatch.setattr(rosa, '_channex_request', fake_request)
    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        rosa.ensure_v3067_schema(con)
        mapping = con.execute(
            "SELECT channex_room_type_id FROM channex_room_type_mappings WHERE integration_id=? AND room_type_id=?",
            (iid, twin_id),
        ).fetchone()
        assert mapping['channex_room_type_id'] == 'remote-twin'
        assert con.execute("SELECT 1 FROM schema_migrations WHERE version=3067").fetchone()

    assert any(path == '/api/v1/channel_availability_rules/rule-twin-cap' and method == 'DELETE' for path, method, _ in calls)
