import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def test_v3056_raises_only_certification_double_inventory(tmp_path, monkeypatch):
    db_file=tmp_path/"v21022.db"
    monkeypatch.setattr(rosa,"DB_PATH",db_file)
    rosa.init_db(reset=True)
    with rosa.db() as con:
        org="org_casa_rosa"; cert=rosa.new_id("prop"); prod=rosa.new_id("prop"); now=rosa.now_iso()
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",(cert,org,"Test Property - Rosa AI","channex-certification-test-property","test","15:00","10:00",2))
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",(prod,org,"Production","production","test","15:00","10:00",2))
        d=rosa.new_id("roomtype"); p=rosa.new_id("roomtype")
        for rid,prop,name,count in ((d,cert,"Double Room",1),(p,prod,"Double Room",1)):
            con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",(rid,org,prop,name,name.lower().replace(" ","-"),count,2,now,now))
        con.execute("DELETE FROM schema_migrations WHERE version=3056")
        rosa.ensure_v3056_schema(con)
        assert con.execute("SELECT inventory_count FROM room_types WHERE id=?",(d,)).fetchone()[0]==4
        assert con.execute("SELECT inventory_count FROM room_types WHERE id=?",(p,)).fetchone()[0]==1
        assert con.execute("SELECT version FROM schema_migrations WHERE version=3056").fetchone()[0]==3056
