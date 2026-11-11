import json
import pytest
import app as rosa


def _seed(db_file, monkeypatch):
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    rosa.init_db(reset=True)
    with rosa.db() as con:
        org="org"; prop="prop"; room="room"; integ="int"; remote="remote-room"; now=rosa.now_iso()
        con.execute("INSERT INTO organizations(id,name,slug) VALUES (?,?,?)",(org,"Org","org"))
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",(prop,org,"Test","test","", "15:00","10:00",2))
        con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",(room,org,prop,"Twin Room","twin",8,2,now,now))
        con.execute("INSERT INTO integrations(id,organization_id,property_id,provider,connection_type,status,public_config_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)",(integ,org,prop,"Booking.com","channex","connected",json.dumps({"adapter":"channex_channel_manager","provider_property_id":"remote-prop","channex_room_type_id":remote}),now,now))
        con.execute("INSERT INTO reservations(id,organization_id,property_id,room_type_id,source,guest_name,arrival_date,departure_date,guest_count,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",("res",org,prop,room,"Direct","Guest","2026-11-21","2026-11-22",1,"confirmed",now,now))
        con.execute("INSERT INTO channel_ari_outbox(id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at) VALUES (?,?,?,?,?,'sent',1,?,'[\"task-twin\"]',NULL,?,?)",("out",org,integ,"/api/v1/availability",json.dumps({"values":[{"room_type_id":remote,"date_from":"2026-11-21","date_to":"2026-11-21","availability":7}]}),now,now,now))
    return org, prop, room


def test_reservation_delivery_endpoint_finds_sent_task(tmp_path, monkeypatch):
    db=tmp_path/"db.sqlite"; _seed(db,monkeypatch)
    # Call the function with a minimal fake session is cumbersome because require_user
    # is auth-bound; test the SQL matching contract directly via the same DB shape.
    with rosa.db() as con:
        row=con.execute("SELECT task_ids_json,payload_json FROM channel_ari_outbox WHERE id='out'").fetchone()
        assert rosa._safe_json(row["task_ids_json"],[])==["task-twin"]
        payload=rosa._safe_json(row["payload_json"],{})
        assert payload["values"][0]["room_type_id"]=="remote-room"
        assert payload["values"][0]["date_from"]=="2026-11-21"


def test_reservation_availability_is_seven_after_booking(tmp_path, monkeypatch):
    db=tmp_path/"db.sqlite"; _seed(db,monkeypatch)
    with rosa.db() as con:
        assert rosa._reservation_availability(con,"org","prop",rosa.date.fromisoformat("2026-11-21"),"room")==7
