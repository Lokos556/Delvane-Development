import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parents[1]))
import app as rosa


def test_v3030_room_types_and_channex_restrictions(tmp_path, monkeypatch):
    db_file = tmp_path / "v3030.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    rosa.init_db(reset=True)
    with rosa.db() as con:
        assert con.execute("SELECT 1 FROM schema_migrations WHERE version=3030").fetchone()
        assert con.execute("SELECT COUNT(*) c FROM room_types").fetchone()["c"] >= 3
        assert con.execute("SELECT COUNT(*) c FROM rate_plans WHERE room_type_id IS NULL").fetchone()["c"] == 0
        assert con.execute("SELECT COUNT(*) c FROM reservations WHERE room_type_id IS NULL").fetchone()["c"] == 0
        cols = {r[1] for r in con.execute("PRAGMA table_info(channel_ari_values)").fetchall()}
        assert {"min_stay_arrival", "min_stay_through", "max_stay"}.issubset(cols)
        cols = {r[1] for r in con.execute("PRAGMA table_info(channex_rate_plan_values)").fetchall()}
        assert {"min_stay_arrival", "min_stay_through", "max_stay"}.issubset(cols)


def test_v3030_room_type_capacity_is_used_for_availability(tmp_path, monkeypatch):
    db_file = tmp_path / "capacity.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    rosa.init_db(reset=True)
    with rosa.db() as con:
        org = "org_casa_rosa"
        prop = "prop_aqua"
        room_id = rosa.new_id("roomtype")
        now = rosa.now_iso()
        con.execute("""INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,1,?,?)""", (room_id,org,prop,"Two Bedroom","two-bedroom",2,5,now,now))
        from datetime import timedelta
        date = rosa.date
        arrival = date.today() + timedelta(days=30)
        departure = arrival + timedelta(days=3)
        for guest in ("A", "B"):
            con.execute("""INSERT INTO reservations(id,organization_id,property_id,room_type_id,source,guest_name,arrival_date,departure_date,guest_count,status,created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)""", (rosa.new_id("res"),org,prop,room_id,"Direct",guest,arrival.isoformat(),departure.isoformat(),2,"confirmed",now))
        assert rosa._reservation_availability(con,org,prop,arrival,room_id) == 0


def test_v3030_ari_sends_all_three_stay_restrictions(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    import json
    db_file = tmp_path / "ari.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    monkeypatch.setattr(rosa, "CHANNEX_API_KEY", "test-key")
    rosa.init_db(reset=True)
    client = TestClient(rosa.app)
    login = client.post("/api/login", json={"email":"owner@demo.rosa","password":"rosa-owner"})
    assert login.status_code == 200
    client.headers.update({"X-Rosa-CSRF": login.json()["csrf_token"]})
    with rosa.db() as con:
        integration=con.execute("SELECT * FROM integrations WHERE property_id='prop_aqua' AND provider='Booking.com' LIMIT 1").fetchone()
        room=con.execute("SELECT * FROM room_types WHERE property_id='prop_aqua' ORDER BY created_at,id LIMIT 1").fetchone()
        plan=con.execute("SELECT * FROM rate_plans WHERE room_type_id=? ORDER BY created_at,id LIMIT 1",(room["id"],)).fetchone()
        cfg={"adapter":"channex_channel_manager","provider_property_id":"bridge-casa","channex_room_type_id":"room-aqua","channex_rate_plan_id":"rate-aqua"}
        con.execute("UPDATE integrations SET public_config_json=?,status='connected' WHERE id=?",(json.dumps(cfg),integration["id"]))
        con.execute("INSERT OR IGNORE INTO channex_rate_mappings(id,organization_id,integration_id,rate_plan_id,channex_room_type_id,channex_rate_plan_id,active,created_at,updated_at) VALUES (?,?,?,?,?,?,1,?,?)",(rosa.new_id('crm'),integration["organization_id"],integration["id"],plan["id"],"room-aqua","rate-aqua",rosa.now_iso(),rosa.now_iso()))
        iid=integration["id"]
    sent=[]
    monkeypatch.setattr(rosa,"_channex_request",lambda path,method='GET',payload=None: (sent.append((path,payload)) or {"data":[{"id":"task"}]}))
    day="2027-05-10"
    response=client.put(f"/api/integrations/{iid}/channex/ari",json={"date_from":day,"date_to":day,"min_stay_arrival":2,"min_stay_through":3,"max_stay":14})
    assert response.status_code==200,response.text
    restriction=[x for x in sent if x[0]=='/api/v1/restrictions'][0][1]["values"][0]
    assert restriction["min_stay_arrival"]==2
    assert restriction["min_stay_through"]==3
    assert restriction["max_stay"]==14
