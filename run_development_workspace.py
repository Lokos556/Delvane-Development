"""Disposable, loopback-only PMS for native development. Never use `uvicorn app:app`.

Reuses the test isolation guards BEFORE importing the application. Outbound socket
connections, secrets, legacy adoption, subprocesses and non-temporary DBs stay blocked.
No operational database is read/copied. Data is discarded when this process exits.
"""
import getpass
import secrets
import sys
import threading

from testing_safety import IsolatedEnvironment


def prepare_workspace(application, safety, password, *, register_marker=True):
    """Called only inside guards; also exercised by isolated API tests."""
    safety.require_path(application.DB_PATH)
    if application.APP_ENV != "test" or application.DB_BACKEND != "sqlite":
        raise RuntimeError("Disposable workspace configuration required")
    if len(password) < 12:
        raise ValueError("Choose at least 12 characters for the disposable accounts")
    application.init_db()
    org="org_casa_rosa"
    with application.db() as con:
        # Replace demo logins; never print passwords or accept them on the CLI.
        con.execute("UPDATE users SET active=0")
        for role in ("owner","manager","cleaner","maintenance"):
            user_id={"owner":"usr_owner","cleaner":"usr_cleaner",
                     "maintenance":"usr_maint","manager":"dev_manager"}[role]
            email=role+"@workspace.invalid"
            if role=="manager":
                con.execute("INSERT INTO users(id,organization_id,full_name,email,password_hash,role,active) VALUES (?,?,?,?,?,?,1)",
                            (user_id,org,"Development Manager",email,application.hash_password(password),role))
            else:
                con.execute("UPDATE users SET full_name=?,email=?,password_hash=?,active=1 WHERE id=?",
                            ("Development "+role.title(),email,application.hash_password(password),user_id))
        con.execute("UPDATE properties SET address='Synthetic development address' WHERE organization_id=?",(org,))
    if register_marker:
        register_workspace_marker(application,secrets.token_urlsafe(18))


def register_workspace_marker(application, workspace_id, *, mode="disposable"):

    @application.app.get("/api/development/workspace")
    def development_workspace():
        return {"isolated":True,"workspace_id":workspace_id,"mode":mode,"date":str(application.date.today())}


def serve_application(application, *, port=8765, sockets=None, _stop_stream=None):
    """Same loopback server for both launchers; optional graceful test control."""
    import uvicorn
    server=uvicorn.Server(uvicorn.Config(application.app,host="127.0.0.1",port=port,
                         access_log=False,log_level="warning",reload=False,workers=1,loop="asyncio"))
    if _stop_stream is not None:
        def stop():
            _stop_stream.readline()
            server.should_exit=True
        threading.Thread(target=stop,daemon=True).start()
    server.run(sockets=sockets)


def main():
    if "app" in sys.modules:
        raise RuntimeError("Application imported before isolation")
    password=getpass.getpass("Choose a disposable workspace password (12+ characters): ")
    if len(password)<12:
        raise SystemExit("Password must have at least 12 characters")
    # Import the server library before subprocess guards; never import app here.
    import uvicorn
    with IsolatedEnvironment() as safety:
        import app
        safety.protect_app(app)
        prepare_workspace(app,safety,password)
        del password
        print("Isolated PMS: http://127.0.0.1:8765 (temporary data; outbound access blocked)")
        print("Accounts: owner, manager, cleaner, maintenance @workspace.invalid")
        serve_application(app)


if __name__=="__main__":
    main()
