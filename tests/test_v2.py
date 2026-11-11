
from fastapi.testclient import TestClient
import app

def login(client, email="owner@demo.rosa", password="rosa-owner"):
    r=client.post("/api/login",json={"email":email,"password":password})
    assert r.status_code==200
    client.headers.update({"X-Rosa-CSRF":r.json()["csrf_token"]})

def test_v2_intelligence_and_operations():
    app.init_db(reset=True)
    with TestClient(app.app) as c:
        login(c)
        intel=c.get("/api/intelligence")
        assert intel.status_code==200
        data=intel.json()
        assert "brief" in data and "approvals" in data and "exceptions" in data
        assert len(data["approvals"]) >= 1
        assert c.get("/api/operations/timeline").status_code==200
        journeys=c.get("/api/guest-journeys")
        assert journeys.status_code==200 and len(journeys.json()) >= 1
        inv=c.get("/api/inventory")
        assert inv.status_code==200 and len(inv.json()["items"]) >= 1

def test_v2_maintenance_and_command():
    app.init_db(reset=True)
    with TestClient(app.app) as c:
        login(c)
        props=c.get("/api/properties").json()
        r=c.post("/api/maintenance",json={"property_id":props[0]["id"],"title":"Test issue","detail":"Test","severity":"high"})
        assert r.status_code==200
        cases=c.get("/api/maintenance").json()
        created=next(x for x in cases if x["title"]=="Test issue")
        assert c.post(f"/api/maintenance/{created['id']}/resolve").status_code==200
        cmd=c.post("/api/rosa/command",json={"command":"Who still needs registration?"})
        assert cmd.status_code==200 and "registration" in cmd.json()["answer"].lower()

def test_v2_approval_resolves():
    app.init_db(reset=True)
    with TestClient(app.app) as c:
        login(c)
        a=c.get("/api/intelligence").json()["approvals"][0]
        assert c.post(f"/api/approvals/{a['id']}/resolve",json={"decision":"Approved"}).status_code==200
        ids=[x["id"] for x in c.get("/api/intelligence").json()["approvals"]]
        assert a["id"] not in ids
