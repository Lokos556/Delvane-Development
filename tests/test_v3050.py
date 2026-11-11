import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

def _seed(tmp_path, monkeypatch, with_booking=False):
    db_file=tmp_path/"v3050.db"; monkeypatch.setattr(rosa,"DB_PATH",db_file); rosa.init_db(reset=True)
    with rosa.db() as con:
        org="org_casa_rosa"; prop=rosa.new_id("prop"); now=rosa.now_iso()
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",(prop,org,"Test Property - Rosa AI","channex-certification-test-property","test","15:00","10:00",2))
        twin=rosa.new_id("roomtype"); double=rosa.new_id("roomtype")
        for room,name,code in ((twin,"Twin Room","twin"),(double,"Double Room","double")):
            con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",(room,org,prop,name,code,1,2,now,now))
        iid=rosa.new_id("int"); cfg={"adapter":"channex_channel_manager","provider_property_id":"remote-cert","certification_workspace":True}
        con.execute("INSERT INTO integrations(id,organization_id,property_id,provider,connection_type,status,public_config_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)",(iid,org,prop,"Booking.com","Channex certification staging","connected",json.dumps(cfg),now,now))
        for room,remote in ((twin,"remote-twin"),(double,"remote-double")):
            con.execute("INSERT INTO channex_room_type_mappings(id,organization_id,integration_id,room_type_id,channex_room_type_id,active,created_at,updated_at) VALUES (?,?,?,?,?,1,?,?)",(rosa.new_id("map"),org,iid,room,remote,now,now))
        if with_booking:
            con.execute("INSERT INTO reservations(id,organization_id,property_id,room_type_id,source,guest_name,arrival_date,departure_date,guest_count,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",(rosa.new_id("res"),org,prop,twin,"Direct","Certification Guest","2026-11-21","2026-11-22",1,"confirmed",now,now))
        con.execute("DELETE FROM schema_migrations WHERE version IN (3050,3052)")
    return org,prop,twin,double,iid

def test_v3050_certification_inventory_precondition(tmp_path,monkeypatch):
    org,prop,twin,double,iid=_seed(tmp_path,monkeypatch)
    with rosa.db() as con:
        rosa.ensure_v3050_schema(con)
        assert con.execute("SELECT inventory_count FROM room_types WHERE id=?",(twin,)).fetchone()[0]==8
        assert con.execute("SELECT inventory_count FROM room_types WHERE id=?",(double,)).fetchone()[0]==1
        vals=con.execute("SELECT stay_date,availability,manual_availability FROM channex_room_type_values WHERE integration_id=? ORDER BY stay_date",(iid,)).fetchall()
        assert [(r[0],r[1],r[2]) for r in vals]==[("2026-11-21",8,8),("2026-11-25",1,1)]

def test_v3052_repairs_v21019_inventory(tmp_path,monkeypatch):
    org,prop,twin,double,iid=_seed(tmp_path,monkeypatch)
    with rosa.db() as con:
        con.execute("UPDATE room_types SET inventory_count=1 WHERE id=?",(twin,))
        con.execute("INSERT INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)",(3050,"old",rosa.now_iso()))
        con.execute("INSERT INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)",(3051,"repair_certification_local_inventory",rosa.now_iso()))
        rosa.ensure_v3052_schema(con)
        assert con.execute("SELECT inventory_count FROM room_types WHERE id=?",(twin,)).fetchone()[0]==8

def test_v3050_twin_booking_produces_seven_available(tmp_path,monkeypatch):
    org,prop,twin,double,iid=_seed(tmp_path,monkeypatch,with_booking=True)
    with rosa.db() as con:
        rosa.ensure_v3050_schema(con)
        assert rosa._reservation_availability(con,org,prop,rosa.date.fromisoformat("2026-11-21"),twin)==7
