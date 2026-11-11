"""Native-client contract tests: root pytest guards own all data and networking."""
import asyncio
import socket

import pytest
from fastapi.testclient import TestClient

import app
from run_development_workspace import prepare_workspace
from testing_safety import TestSafetyError


@pytest.fixture
def client():
    app.init_db()
    with app.db() as con:
        con.execute("INSERT INTO users(id,organization_id,full_name,email,password_hash,role,active) VALUES (?,?,?,?,?,?,1)",
                    ("test_manager","org_casa_rosa","Synthetic Manager","manager@workspace.invalid",app.hash_password("synthetic-password"),"manager"))
    with TestClient(app.app) as client:
        yield client


def sign_in(client, role):
    credentials={"owner":("owner@demo.rosa","rosa-owner"),
                 "manager":("manager@workspace.invalid","synthetic-password"),
                 "cleaner":("cleaner@demo.rosa","rosa-cleaner"),
                 "maintenance":("maintenance@demo.rosa","rosa-maintenance")}
    email,password=credentials[role]
    response=client.post("/api/login",json={"email":email,"password":password})
    assert response.status_code==200
    client.headers["X-Rosa-CSRF"]=response.json()["csrf_token"]
    return response


@pytest.mark.parametrize("role",["owner","manager","cleaner","maintenance"])
def test_native_cookie_csrf_logout_and_role_contract(client,role):
    login=sign_in(client,role)
    cookie=login.headers["set-cookie"].lower()
    assert "httponly" in cookie and "max-age=604800" in cookie and "path=/" in cookie
    identity=client.get("/api/me")
    assert identity.status_code==200 and identity.json()["role"]==role
    assert identity.json()["csrf_token"]==client.headers["X-Rosa-CSRF"]
    properties=client.get("/api/operations/properties")
    assert properties.status_code==200
    assert all(set(row)=={"id","name","checkin_time","checkout_time"} for row in properties.json())
    assert all(row["id"]!="prop_other" for row in properties.json())
    operator=role in ("owner","manager")
    assert client.get("/api/properties").status_code==(200 if operator else 403)
    assert client.get("/api/operations/today-command").status_code==(200 if operator else 403)
    assert client.get("/api/reservations/res_terra_next/detail").status_code==(200 if operator else 403)
    del client.headers["X-Rosa-CSRF"]
    assert client.post("/api/logout").status_code==403
    client.headers["X-Rosa-CSRF"]=identity.json()["csrf_token"]
    assert client.post("/api/logout").status_code==200
    assert client.get("/api/me").status_code==401


def test_operational_properties_requires_login(client):
    assert client.get("/api/operations/properties").status_code==401


def test_today_stable_property_ids_and_backwards_compatible_fields(client):
    sign_in(client,"owner")
    body=client.get("/api/operations/today-command").json()
    known={row["id"] for row in client.get("/api/properties").json()}
    for queue in ("arrivals","departures","cleaning","maintenance","registration_risks"):
        for row in body[queue]:
            assert row["id"] and row["property_id"] in known and row["property_name"]
    for row in body["cleaning"]:
        assert row["scheduled_date"]==body["date"]
        assert {"deadline_time","priority","status","assigned_name","worker_note"}<=set(row)


def test_maintenance_property_context_excludes_cases_assigned_to_other_workers(client):
    sign_in(client,"maintenance")
    with app.db() as con:
        con.execute("UPDATE maintenance_cases SET assigned_to='usr_owner' WHERE organization_id='org_casa_rosa'")
    assert client.get("/api/operations/properties").json()==[]
    with app.db() as con:
        con.execute("UPDATE maintenance_cases SET assigned_to=NULL WHERE id='maint_terra_tap'")
    data=client.get("/api/operations/properties").json()
    assert [row["id"] for row in data]==["prop_terra"]


def test_disposable_launcher_uses_guards_fresh_accounts_and_no_external_connections(request):
    safety=request.config._delvane_safety
    previous_routes=list(app.app.router.routes)
    try:
        prepare_workspace(app,safety,"synthetic-workspace-password")
        assert app.DB_PATH.resolve().is_relative_to(safety.root)
        assert app.LEGACY_DB_PATH.resolve().is_relative_to(safety.root)
        assert not app.CHANNEX_API_KEY and not app.OPENAI_API_KEY
        with pytest.raises(TestSafetyError):
            socket.create_connection(("example.invalid",443))
        with TestClient(app.app) as c:
            marker=c.get("/api/development/workspace").json()
            assert marker["isolated"] is True and marker["workspace_id"]
            for role in ("owner","manager","cleaner","maintenance"):
                response=c.post("/api/login",json={"email":role+"@workspace.invalid","password":"synthetic-workspace-password"})
                assert response.status_code==200
                assert c.get("/api/me").json()["role"]==role
            assert c.post("/api/login",json={"email":"owner@demo.rosa","password":"rosa-owner"}).status_code==401
    finally:
        app.app.router.routes[:]=previous_routes


def test_loopback_server_can_boot_and_stop_under_existing_isolation_guards():
    # Real listener on an ephemeral loopback port; no client/outbound connection.
    # Verifies that the development launcher's guards do not break Uvicorn startup.
    import uvicorn
    server=uvicorn.Server(uvicorn.Config(app.app,host="127.0.0.1",port=0,
                                       access_log=False,log_level="critical",loop="asyncio"))

    async def exercise():
        serving=asyncio.create_task(server.serve())
        try:
            for _ in range(300):
                if server.started or serving.done():
                    break
                await asyncio.sleep(0.01)
            assert server.started
        finally:
            server.should_exit=True
            await serving
    asyncio.run(exercise())
