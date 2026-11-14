import json
import re
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file = tmp_path / "v25.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(client, email="owner@demo.rosa", password="rosa-owner"):
    r = client.post("/api/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    client.headers.update({"X-Rosa-CSRF": r.json()["csrf_token"]})
    return r


def test_schema_migration_and_runtime_health(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch)
    assert c.get("/health/live").json()["status"] == "ok"
    ready = c.get("/health/ready")
    assert ready.status_code == 200, ready.text
    with rosa.db() as con:
        row = con.execute("SELECT * FROM schema_migrations WHERE version=?", (2500,)).fetchone()
        assert row and row["name"] == "production_core_complete_operations"
        for table in ("reservation_notes", "reservation_events", "task_checklist_items", "sensitive_guest_data", "account_tokens"):
            assert con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone()
    login(c)
    runtime = c.get("/api/system/runtime").json()
    assert runtime["version"] == rosa.APP_VERSION == rosa.app.version
    assert runtime["schema_version"] == rosa.SCHEMA_VERSION
    assert runtime["database_backend"] == "sqlite"
    assert runtime["environment"] == rosa.APP_ENV == "test"


def test_reservation_workspace_note_and_operational_update(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch); login(c)
    rid = "res_terra_next"
    detail = c.get(f"/api/reservations/{rid}/detail")
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["reservation"]["property_name"] == "Terra"
    assert {"notes", "messages", "registration", "cleaning", "events", "guest", "maintenance"} <= set(body)

    n = c.post(f"/api/reservations/{rid}/notes", json={"body": "VIP arrival note for Rosa V2.5 test."})
    assert n.status_code == 200, n.text
    u = c.patch(f"/api/reservations/{rid}/operations", json={
        "arrival_time": "20:45",
        "payment_status": "partial",
        "registration_status": body["reservation"]["registration_status"],
        "special_requests": ["High chair", "Extra towels"],
    })
    assert u.status_code == 200, u.text
    after = c.get(f"/api/reservations/{rid}/detail").json()
    assert after["reservation"]["arrival_time"] == "20:45"
    assert after["reservation"]["payment_status"] == "partial"
    assert after["reservation"]["registration_status"] == body["reservation"]["registration_status"]
    assert json.loads(after["reservation"]["special_requests"]) == ["High chair", "Extra towels"]
    assert any(x["body"].startswith("VIP arrival") for x in after["notes"])
    assert any(x["event_type"] == "operational_update" for x in after["events"])


def test_reservation_detail_tenant_isolation(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch); login(c)
    assert c.get("/api/reservations/res_terra_next/detail").status_code == 200
    c.post("/api/logout")
    login(c, "owner@isolation.demo", "rosa-isolation")
    assert c.get("/api/reservations/res_terra_next/detail").status_code == 404
    assert c.post("/api/reservations/res_terra_next/notes", json={"body": "steal"}).status_code == 404
    assert c.patch("/api/reservations/res_terra_next/operations", json={"arrival_time": "00:01"}).status_code == 404


def test_persistent_cleaner_checklist_and_counts(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch); login(c, "cleaner@demo.rosa", "rosa-cleaner")
    tasks = c.get("/api/worker/dashboard").json()["tasks"]
    task = next(x for x in tasks if x["status"] != "complete")
    assert task["checklist_total"] == 6
    assert task["checklist_done"] == 0
    item = task["checklist"][0]
    r = c.patch(f"/api/work-tasks/{task['id']}/checklist/{item['id']}", json={"completed": True})
    assert r.status_code == 200, r.text
    refreshed = next(x for x in c.get("/api/worker/dashboard").json()["tasks"] if x["id"] == task["id"])
    assert refreshed["checklist_done"] == 1
    assert next(x for x in refreshed["checklist"] if x["id"] == item["id"])["completed"] == 1


def test_maintenance_commercial_lifecycle_and_permissions(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch); login(c)
    case = next(x for x in c.get("/api/maintenance").json() if x["status"] in {"reported", "assigned"})
    cid = case["id"]
    assert c.patch(f"/api/maintenance/{cid}/status", json={"status": "in_progress"}).status_code == 200
    assert c.patch(f"/api/maintenance/{cid}/status", json={"status": "resolved"}).status_code == 200
    assert c.patch(f"/api/maintenance/{cid}/status", json={"status": "verified"}).status_code == 200
    final = next(x for x in c.get("/api/maintenance").json() if x["id"] == cid)
    assert final["status"] == "verified"
    assert final["started_at"] and final["resolved_at"] and final["verified_at"]

    # A maintenance worker may resolve work, but cannot self-verify it.
    other = next((x for x in c.get("/api/maintenance").json() if x["id"] != cid), None)
    c.post("/api/logout"); login(c, "maintenance@demo.rosa", "rosa-maintenance")
    if other:
        assert c.patch(f"/api/maintenance/{other['id']}/status", json={"status": "verified"}).status_code == 403


def test_sensitive_registration_vault_is_encrypted_and_owner_only(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch); login(c)
    center = c.get("/api/registration").json()
    entry = next(x for x in center if x.get("guests"))
    record = entry["guests"][0]
    secret = "TEST-PASSPORT-DO-NOT-STORE-PLAINTEXT"
    r = c.put(f"/api/registration/records/{record['id']}/sensitive", json={
        "date_of_birth": "1988-04-20",
        "document_type": "passport",
        "document_number": secret,
        "address": "Test Address 1",
    })
    assert r.status_code == 200, r.text
    with rosa.db() as con:
        stored = con.execute("SELECT encrypted_payload FROM sensitive_guest_data WHERE guest_record_id=?", (record["id"],)).fetchone()["encrypted_payload"]
        assert secret not in stored
        assert "Test Address 1" not in stored
    revealed = c.get(f"/api/registration/{entry['id']}/sensitive")
    assert revealed.status_code == 200
    assert any(x["sensitive"] and x["sensitive"]["document_number"] == secret for x in revealed.json())

    c.post("/api/logout"); login(c, "cleaner@demo.rosa", "rosa-cleaner")
    assert c.get(f"/api/registration/{entry['id']}/sensitive").status_code == 403




def test_account_recovery_tokens_are_hashed_single_use_and_revoke_sessions(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch)
    login(c)
    assert c.get("/api/me").status_code == 200
    requested = c.post("/api/security/password-reset/request", json={"email":"owner@demo.rosa"})
    assert requested.status_code == 200, requested.text
    raw = requested.json().get("development_token")
    assert raw
    with rosa.db() as con:
        row = con.execute("SELECT token_hash FROM account_tokens WHERE token_type='password_reset'").fetchone()
        assert row and raw not in row["token_hash"]
        assert row["token_hash"] == rosa.token_digest(raw)
    reset = c.post("/api/security/password-reset/confirm", json={"token":raw,"new_password":"a-strong-new-password-25"})
    assert reset.status_code == 200, reset.text
    # Current session is revoked by a successful password reset.
    assert c.get("/api/me").status_code == 401
    assert c.post("/api/security/password-reset/confirm", json={"token":raw,"new_password":"another-strong-password"}).status_code == 400
    assert c.post("/api/login", json={"email":"owner@demo.rosa","password":"a-strong-new-password-25"}).status_code == 200

def test_production_runtime_guard_and_postgres_sql_translation(monkeypatch):
    monkeypatch.setattr(rosa, "APP_ENV", "production")
    monkeypatch.setattr(rosa, "DB_BACKEND", "sqlite")
    monkeypatch.setattr(rosa, "SECURE_COOKIES", False)
    monkeypatch.setattr(rosa, "DEMO_MODE", True)
    monkeypatch.delenv("ROSA_ENCRYPTION_KEY", raising=False)
    with pytest.raises(RuntimeError) as exc:
        rosa.validate_runtime()
    msg = str(exc.value)
    assert "PostgreSQL" in msg and "ROSA_SECURE_COOKIES" in msg and "ROSA_ENCRYPTION_KEY" in msg

    wrapper = object.__new__(rosa.DBConnection)
    wrapper.backend = "postgresql"
    sql = wrapper._sql("INSERT OR IGNORE INTO demo(a,b) VALUES (?,?)")
    assert sql == "INSERT INTO demo(a,b) VALUES (%s,%s) ON CONFLICT DO NOTHING"


def _extract_js_object(source: str, var_name: str):
    marker = f"const {var_name}="
    start = source.index(marker) + len(marker)
    depth = 0; in_string = None; escape = False
    for i in range(start, len(source)):
        ch = source[i]
        if in_string:
            if escape: escape = False
            elif ch == "\\": escape = True
            elif ch == in_string: in_string = None
            continue
        if ch in "'\"`": in_string = ch; continue
        if ch == "{": depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[start:i+1]
    raise AssertionError(f"Could not parse {var_name}")


def test_v25_frontend_commercial_workspaces_and_full_locale_sets(tmp_path, monkeypatch):
    fresh(tmp_path, monkeypatch)
    root = Path(__file__).resolve().parents[1]
    js = (root / "static" / "app.js").read_text(encoding="utf-8")
    css = (root / "static" / "styles.css").read_text(encoding="utf-8")
    for expected in (
        "productionCore", "v25-command-top", "v25-reservation-workspace", "v25-res-tabs",
        "v25-cleaning-card", "v25-checklist", "v25-maint-rail", "/api/operations/today-command",
        "/detail`", "/checklist/", "/api/system/runtime",
    ):
        assert expected in (js + css)
    locales = ["en","hu","de","es","fr","it","pt","pl","nl","ro","cs","sk","hr","sr","uk","ru","tr","zh"]
    for dictionary in ("V25_I18N", "V25_SYS"):
        data = json.loads(_extract_js_object(js, dictionary))
        assert set(locales) == set(data), f"{dictionary} locale set changed"
        base_keys = set(data["en"])
        assert len(base_keys) >= (20 if dictionary == "V25_I18N" else 5)
        for lang in locales:
            assert set(data[lang]) == base_keys, f"{dictionary}.{lang} key mismatch"
            assert all(str(v).strip() for v in data[lang].values()), f"{dictionary}.{lang} contains blank translation"
