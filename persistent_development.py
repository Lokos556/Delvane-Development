"""Owned, local-only acceptance storage using the existing isolation guards.

No configurable DB URL/path, legacy adoption, external credentials or outbound
connections. Production code never imports this module. Normal startup keeps all
test data; only the explicit offline archive/reset command replaces the store.
"""
import json
import os
from pathlib import Path
import secrets
from contextlib import contextmanager
from unittest.mock import patch

from cryptography.fernet import Fernet

from testing_safety import IsolatedEnvironment, TestSafetyError, _ACTIVE_ROOT
from run_development_workspace import prepare_workspace, register_workspace_marker


REPOSITORY = Path(__file__).resolve().parent
FORMAT = "delvane-persistent-development-v1"
RESET_CONFIRMATION = "RESET PERSISTENT DEVELOPMENT DATA"


def _no_links(path, base):
    """Reject redirected directories/files and hard-linked storage before access."""
    path = Path(path).absolute()
    if not path.is_relative_to(base):
        raise TestSafetyError("Persistent development storage must stay in its owned directory")
    for candidate in (path, *path.parents):
        if candidate == base:
            break
        if candidate.is_symlink() or (hasattr(candidate, "is_junction") and candidate.is_junction()):
            raise TestSafetyError("Redirected persistent development storage is forbidden")
        if candidate.is_file() and candidate.stat().st_nlink > 1:
            raise TestSafetyError("Hard-linked persistent development files are forbidden")
    if not path.resolve().is_relative_to(base.resolve()):
        raise TestSafetyError("Persistent development storage escaped its directory")
    return path


@contextmanager
def store_lock(container):
    """OS-owned lock survives stale lock files and is released on process death."""
    _no_links(container, container.parent)
    container.mkdir(parents=True, exist_ok=True)
    lock_path = _no_links(container / "persistent.lock", container)
    with open(lock_path, "a+b") as stream:
        stream.seek(0, os.SEEK_END)
        if stream.tell() == 0:
            stream.write(b"0"); stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise RuntimeError("Persistent development is already running or locked; stop it before restarting/resetting") from None
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


class PersistentDevelopment(IsolatedEnvironment):
    database_name = "workspace.db"
    demo_mode = "0"
    allow_local_configuration = False

    def __init__(self, *, _test_parent=None):
        parent = REPOSITORY
        if _test_parent is not None:
            active = _ACTIVE_ROOT.get()
            if active is None or not Path(_test_parent).resolve().is_relative_to(active):
                raise TestSafetyError("Test storage override requires active temporary isolation")
            parent = Path(_test_parent).resolve()
        self.container = parent / ".development"
        self.storage = self.container / "persistent"
        self.fresh = False

    def inspect(self):
        """Read only this owned store's marker, never an application database."""
        _no_links(self.storage, self.container.parent)
        if not self.storage.exists() or not any(self.storage.iterdir()):
            return None
        allowed = {"workspace.json", self.database_name, self.database_name + "-wal",
                   self.database_name + "-shm", self.database_name + "-journal"}
        for entry in self.storage.iterdir():
            _no_links(entry, self.container.parent)
            if entry.name not in allowed or not entry.is_file():
                raise RuntimeError("Unrecognized files in persistent development storage; refusing to adopt or reset it")
        marker = self.storage / "workspace.json"
        if not marker.is_file():
            raise RuntimeError("Missing development ownership marker; refusing to adopt this directory")
        try:
            metadata = json.loads(marker.read_text(encoding="utf-8"))
            if (metadata["format"] != FORMAT or metadata["database"] != self.database_name
                    or len(metadata["workspace_id"]) < 20):
                raise ValueError()
            Fernet(metadata["encryption_key"].encode())
        except (KeyError, TypeError, ValueError):
            raise RuntimeError("Invalid persistent development ownership marker; no data was initialized or reset") from None
        return metadata

    def allocate_root(self):
        self.stack.enter_context(store_lock(self.container))
        self.metadata = self.inspect()
        if self.metadata is None:
            self.fresh = True
            self.storage.mkdir(parents=True, exist_ok=True)
            self.metadata = {"format": FORMAT, "database": self.database_name,
                             "workspace_id": secrets.token_urlsafe(24),
                             "encryption_key": Fernet.generate_key().decode()}
            marker = self.storage / "workspace.json"
            with open(marker, "x", encoding="utf-8") as stream:
                json.dump(self.metadata, stream); stream.flush(); os.fsync(stream.fileno())
            marker.chmod(0o600)
        elif not (self.storage / self.database_name).is_file():
            raise RuntimeError("Persistent database is missing; refusing silent reinitialization. Use the explicit reset command")
        return self.storage.resolve()

    def environment_overrides(self):
        return {"ROSA_ENCRYPTION_KEY": self.metadata["encryption_key"]}

    def __enter__(self):
        try:
            return super().__enter__()
        except BaseException:
            self.stack.close()
            raise

    def require_path(self, value):
        path = super().require_path(value)
        _no_links(Path(value), self.container.parent)
        return path

    def protect_app(self, application):
        super().protect_app(application)
        self.stack.enter_context(patch.object(application, "DATABASE_URL", "sqlite:///" + str(self.root / self.database_name)))
        self.stack.enter_context(patch.object(application, "DEMO_MODE", False))
        original_init = application.init_db

        def init_db(*args, **kwargs):
            if (args and args[0]) or kwargs.get("reset"):
                raise TestSafetyError("Use the explicit offline persistent-development reset command")
            if (application.DB_PATH.resolve() != self.root / self.database_name
                    or application.DATABASE_URL != "sqlite:///" + str(self.root / self.database_name)
                    or application.APP_ENV != "test"):
                raise TestSafetyError("Persistent development database configuration changed")
            return original_init(*args, **kwargs)

        self.stack.enter_context(patch.object(application, "init_db", init_db))
        if not self.fresh:
            # An owned directory alone does not authorize adopting an unrelated DB.
            try:
                with application.db() as con:
                    row = con.execute("SELECT workspace_id FROM development_workspace_identity").fetchall()
                    if len(row) != 1 or row[0]["workspace_id"] != self.metadata["workspace_id"]:
                        raise ValueError()
            except Exception:
                raise RuntimeError("Database does not match the persistent development marker; refusing initialization") from None

    def prepare(self, application, password=None):
        if self.fresh:
            if password is None or len(password) < 12:
                raise ValueError("Initial test-account password requires at least 12 characters")
            # Reuse the existing synthetic bootstrap once, never on ordinary restart.
            application.DEMO_MODE = True
            try:
                prepare_workspace(application, self, password, register_marker=False)
            finally:
                application.DEMO_MODE = False
            with application.db() as con:
                con.execute("CREATE TABLE development_workspace_identity(workspace_id TEXT PRIMARY KEY)")
                con.execute("INSERT INTO development_workspace_identity VALUES (?)", (self.metadata["workspace_id"],))
        else:
            application.DEMO_MODE = False
            application.init_db()  # Existing schema migrations; no demo seeding or account reset.
        register_workspace_marker(application, self.metadata["workspace_id"], mode="persistent")

    def reset(self, confirmation):
        """Archive only an owned, stopped development store; never delete a tree."""
        if confirmation != RESET_CONFIRMATION:
            raise ValueError("Reset confirmation did not match; no data was moved")
        with store_lock(self.container):
            if self.inspect() is None:
                raise RuntimeError("No persistent development store exists; nothing to reset")
            archive = self.container / ("persistent-archive-" + secrets.token_hex(8))
            _no_links(archive, self.container.parent)
            if self.storage.resolve().parent != self.container.resolve() or archive.resolve().parent != self.container.resolve():
                raise TestSafetyError("Reset paths escaped the development directory")
            self.storage.rename(archive)
            return archive
