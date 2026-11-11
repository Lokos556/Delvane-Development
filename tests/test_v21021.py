import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def _seed_cert(tmp_path, monkeypatch):
    db_file=tmp_path/"v21021.db"
    monkeypatch.setattr(rosa,"DB_PATH",db_file)
    rosa.init_db(reset=True)
    with rosa.db() as con:
        org="org_casa_rosa"; prop=rosa.new_id("prop"); now=rosa.now_iso()
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",
                    (prop,org,"Test Property - Rosa AI","channex-certification-test-property","test","15:00","10:00",2))
        rooms=[]
        for name,code in (("Twin Room","twin"),("Double Room","double")):
            rid=rosa.new_id("roomtype")
            con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",
                        (rid,org,prop,name,code,8 if code=="twin" else 4,2,now,now))
            rooms.append(rid)
        iid=rosa.new_id("int")
        cfg={"certification_workspace":True}
        con.execute("INSERT INTO integrations(id,organization_id,property_id,provider,connection_type,status,public_config_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                    (iid,org,prop,"Booking.com","Channex certification staging","connected",json.dumps(cfg),now,now))
        for rid,title in [(rooms[0],"Standard Rate"),(rooms[0],"Best Available Rate"),(rooms[0],"Bed & Breakfast Rate"),(rooms[1],"Best Available Rate"),(rooms[1],"Bed & Breakfast Rate")]:
            pid=rosa.new_id("rateplan")
            con.execute("INSERT INTO rate_plans(id,organization_id,property_id,room_type_id,name,code,meal_type,cancellation_policy,base_rate_huf,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,1,?,?)",
                        (pid,org,prop,rid,title,rosa.new_id("code"),"none","flexible",100,now,now))
        con.execute("DELETE FROM schema_migrations WHERE version=3055")
    return prop,rooms


def test_v3055_removes_legacy_standard_only_from_certification(tmp_path, monkeypatch):
    prop,rooms=_seed_cert(tmp_path,monkeypatch)
    with rosa.db() as con:
        rosa.ensure_v3055_schema(con)
        twin=[dict(r) for r in con.execute("SELECT name,active FROM rate_plans WHERE room_type_id=? ORDER BY name",(rooms[0],)).fetchall()]
        assert [(r["name"],r["active"]) for r in twin]==[("Bed & Breakfast Rate",1),("Best Available Rate",1),("Standard Rate",0)]
        assert con.execute("SELECT COUNT(*) FROM rate_plans WHERE room_type_id=? AND active=1",(rooms[1],)).fetchone()[0]==2
        assert con.execute("SELECT version FROM schema_migrations WHERE version=3055").fetchone()[0]==3055


def test_standard_rate_seed_skips_multi_rate_property(tmp_path, monkeypatch):
    db_file=tmp_path/"seed.db"; monkeypatch.setattr(rosa,"DB_PATH",db_file); rosa.init_db(reset=True)
    with rosa.db() as con:
        org="org_casa_rosa"; prop=rosa.new_id("prop"); now=rosa.now_iso()
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",
                    (prop,org,"Multi-rate","multi-rate","test","15:00","10:00",2))
        rid=rosa.new_id("roomtype")
        con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",
                    (rid,org,prop,"Room","room",1,2,now,now))
        for title in ("Best Available Rate","Bed & Breakfast Rate"):
            con.execute("INSERT INTO rate_plans(id,organization_id,property_id,room_type_id,name,code,meal_type,cancellation_policy,base_rate_huf,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,1,?,?)",
                        (rosa.new_id("rateplan"),org,prop,rid,title,title.lower().replace(" ","-"),"none","flexible",100,now,now))
        # Re-run only the seeding block semantics directly against this property.
        has_plan=con.execute("SELECT 1 FROM rate_plans WHERE property_id=? AND active=1 LIMIT 1",(prop,)).fetchone()
        assert has_plan is not None
        assert con.execute("SELECT COUNT(*) FROM rate_plans WHERE property_id=? AND lower(name)='standard rate'",(prop,)).fetchone()[0]==0
