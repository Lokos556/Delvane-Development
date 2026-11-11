"""Test-process guards. Never imported by the production application."""
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import tempfile
import urllib.request
from unittest.mock import patch
from contextlib import ExitStack
from contextvars import ContextVar


_ACTIVE_ROOT = ContextVar("delvane_test_root", default=None)


class TestSafetyError(RuntimeError):
    __test__ = False


class IsolatedEnvironment:
    """Allow database files only inside a freshly allocated temporary tree."""

    def __enter__(self):
        self.stack = ExitStack()
        self.root = Path(self.stack.enter_context(
            tempfile.TemporaryDirectory(prefix="delvane-tests-", dir=_ACTIVE_ROOT.get())
        )).resolve()
        token = _ACTIVE_ROOT.set(self.root)
        self.stack.callback(_ACTIVE_ROOT.reset, token)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("ROSA_") and k != "OPENAI_API_KEY"}
        env.update({
            "ROSA_APP_ENV": "test", "ROSA_DEMO_MODE": "1",
            "ROSA_DATA_DIR": str(self.root),
            "ROSA_DATABASE_URL": "sqlite:///" + str(self.root / "collection.db"),
            "ROSA_AI_PROVIDER": "local", "ROSA_SECURE_COOKIES": "0",
            "LOCALAPPDATA": str(self.root),
            "XDG_CONFIG_HOME": str(self.root), "XDG_DATA_HOME": str(self.root),
        })
        self.stack.enter_context(patch.dict(os.environ, env, clear=True))
        original_connect = sqlite3.connect
        original_read = Path.read_text
        original_glob = Path.glob
        original_copy = shutil.copy2
        original_unlink = Path.unlink

        def connect(database, *args, **kwargs):
            self.require_path(database)
            return original_connect(database, *args, **kwargs)

        def read_text(path, *args, **kwargs):
            if path.name.startswith(".env") and not path.resolve().is_relative_to(self.root):
                return ""  # Do not load real local configuration, including during import.
            return original_read(path, *args, **kwargs)

        def glob(path, pattern, *args, **kwargs):
            if str(pattern).lower() in {"rosa*/.env.local", "rosa-v*/rosa.db"}:
                return iter(())  # Never discover sibling release secrets or databases.
            return original_glob(path, pattern, *args, **kwargs)

        def copy(source, destination, *args, **kwargs):
            try:
                self.require_path(source)
                self.require_path(destination)
            except TestSafetyError as exc:
                raise OSError("Test isolation blocked a copy outside temporary data") from exc
            return original_copy(source, destination, *args, **kwargs)

        def unlink(path, *args, **kwargs):
            if any(suffix in path.name.lower() for suffix in (".db", ".sqlite")):
                self.require_path(path)
            return original_unlink(path, *args, **kwargs)

        for target, replacement in (
            ("sqlite3.connect", connect), ("pathlib.Path.read_text", read_text),
            ("pathlib.Path.glob", glob), ("shutil.copy2", copy),
            ("pathlib.Path.unlink", unlink),
            ("socket.socket.connect", self.block_network),
            ("socket.socket.connect_ex", self.block_network),
            ("socket.create_connection", self.block_network),
            ("socket.getaddrinfo", self.block_network),
            ("socket.socket.sendto", self.block_network),
            ("urllib.request.urlopen", self.block_network),
        ):
            self.stack.enter_context(patch(target, replacement))
        return self

    def require_path(self, value):
        # Reject SQLite URI/memory names too: all test data must be identifiable files.
        path = Path(value).resolve()
        if not path.is_relative_to(self.root) or path == self.root:
            raise TestSafetyError("Database access outside isolated temporary data is forbidden")
        return path

    @staticmethod
    def block_network(*args, **kwargs):
        raise TestSafetyError("External network access is forbidden during tests; mock the adapter")

    def protect_app(self, app):
        original_init = app.init_db
        original_migrate = app.migrate_legacy_database
        original_connection_init = app.DBConnection.__init__

        def check_database():
            if app.DB_BACKEND != "sqlite":
                raise TestSafetyError("Tests may only use temporary SQLite databases")
            self.require_path(app.DB_PATH)

        def init_db(*args, **kwargs):
            check_database()  # Must run BEFORE init_db can unlink/reset anything.
            return original_init(*args, **kwargs)

        def migrate():
            check_database()
            self.require_path(app.LEGACY_DB_PATH)
            return original_migrate()

        def connection_init(connection):
            check_database()
            original_connection_init(connection)

        for name, value in (("DB_PATH", self.root / "collection.db"),
                            ("LEGACY_DB_PATH", self.root / "absent-legacy.db"),
                            ("DATA_DIR", self.root)):
            self.stack.enter_context(patch.object(app, name, value, create=True))
        for target, replacement in (("init_db", init_db),
                                    ("migrate_legacy_database", migrate)):
            self.stack.enter_context(patch.object(app, target, replacement))
        self.stack.enter_context(patch.object(app.DBConnection, "__init__", connection_init))

    def __exit__(self, *exc):
        return self.stack.__exit__(*exc)
