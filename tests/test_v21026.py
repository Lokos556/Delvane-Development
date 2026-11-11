
import json, sys, sqlite3
from datetime import date, timedelta
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

def test_full_sync_uses_500_future_dates(tmp_path, monkeypatch):
    # Use the existing fixture helper from the older certification suite.
    from test_v2912 import fresh, set_base_rate
    client, db_file, integration_id, _ = fresh(tmp_path, monkeypatch)
    set_base_rate(db_file, integration_id)
    calls=[]
    monkeypatch.setattr(
        rosa, "_channex_request",
        lambda path, method="GET", payload=None: calls.append((path,method,payload)) or {"data":[{"id":"task"}]}
    )
    response=client.post(f"/api/integrations/{integration_id}/channex/full-sync")
    assert response.status_code==200, response.text
    for _,_,payload in calls:
        dates=[x["date"] for x in payload["values"]]
        assert len(dates)==500
        assert dates[0]==str(date.today()+timedelta(days=1))
        assert dates[-1]==str(date.today()+timedelta(days=500))

def test_v3060_repairs_stale_full_sync_restrictions(tmp_path, monkeypatch):
    from test_v2912 import fresh
    client, db_file, integration_id, _ = fresh(tmp_path, monkeypatch)
    with sqlite3.connect(db_file) as con:
        con.execute(
            """INSERT INTO channel_ari_outbox
            (id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at)
            VALUES (?,?,?,?,?,'retry',12,?,'[]',?,?,NULL)""",
            ("job","org_casa_rosa",integration_id,"/api/v1/restrictions",
             json.dumps({"values":[{"property_id":"p","rate_plan_id":"r","date":str(date.today()),"rate":1000} for _ in range(500)]}),
             rosa.now_iso(),"bad",rosa.now_iso())
        )
        con.execute("DELETE FROM schema_migrations WHERE version=3060")
        rosa.ensure_v3060_schema(con)
        row=con.execute("SELECT payload_json,status,attempts,last_error FROM channel_ari_outbox WHERE id='job'").fetchone()
        payload=json.loads(row[0])
        assert payload["values"][0]["date"]==str(date.today()+timedelta(days=1))
        assert payload["values"][-1]["date"]==str(date.today()+timedelta(days=500))
        assert row[1]=="queued" and row[2]==0 and row[3] is None
