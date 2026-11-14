"""Persistent, isolated, loopback-only acceptance backend. No production config."""
import argparse
import getpass
import socket
import sys

from persistent_development import PersistentDevelopment, RESET_CONFIRMATION
from run_development_workspace import serve_application


def serve(storage, password=None, *, port=8765, _stop_stream=None):
    if "app" in sys.modules:
        raise RuntimeError("Application imported before development isolation")
    import uvicorn
    # Reserve the listener before creating any store; never replace another server.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(("127.0.0.1", port))
        with storage:
            import app
            storage.protect_app(app)
            storage.prepare(app, password)
            password = None
            print(f"Persistent isolated PMS: http://127.0.0.1:{port}", flush=True)
            print(f"Fictional data retained at: {app.DB_PATH}", flush=True)
            print("Accounts: owner, manager, cleaner, maintenance @workspace.invalid; outbound access blocked", flush=True)
            serve_application(app,port=port,sockets=[listener],_stop_stream=_stop_stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset", action="store_true", help="Stop server first; confirm and archive only persistent test data")
    args = parser.parse_args()
    storage = PersistentDevelopment()
    if args.reset:
        print("This archives ONLY persistent fictional development data. Stop the persistent backend first.")
        confirmation = input(f"Type {RESET_CONFIRMATION}: ")
        print(f"Archived fictional development data: {storage.reset(confirmation)}")
        print("Start the persistent launcher again to create a new workspace and password.")
        return
    password = None
    if storage.inspect() is None:
        password = getpass.getpass("Choose initial fictional-account password (12+ characters): ")
        if len(password) < 12:
            raise SystemExit("Password must have at least 12 characters; no database was created")
        if getpass.getpass("Confirm password: ") != password:
            raise SystemExit("Passwords did not match; no database was created")
    serve(storage, password)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
