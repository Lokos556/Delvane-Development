"""Test-process guards. Never imported by the production application."""
import os
import builtins
import io
from pathlib import Path
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import urllib.request
from unittest.mock import patch
from contextlib import ExitStack
from contextvars import ContextVar


_ACTIVE_ROOT = ContextVar("delvane_test_root", default=None)
_INTERNAL_SOCKETPAIR = ContextVar("delvane_internal_socketpair", default=False)


class TestSafetyError(RuntimeError):
    __test__ = False


class IsolatedEnvironment:
    """Allow database files only inside a freshly allocated temporary tree."""

    database_name = "collection.db"
    demo_mode = "1"
    allow_local_configuration = True

    def allocate_root(self):
        return Path(self.stack.enter_context(
            tempfile.TemporaryDirectory(prefix="delvane-tests-", dir=_ACTIVE_ROOT.get())
        )).resolve()

    def environment_overrides(self):
        return {}

    def __enter__(self):
        self.stack = ExitStack()
        self.root = self.allocate_root()
        token = _ACTIVE_ROOT.set(self.root)
        self.stack.callback(_ACTIVE_ROOT.reset, token)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("ROSA_") and k != "OPENAI_API_KEY"}
        env.update({
            "ROSA_APP_ENV": "test", "ROSA_DEMO_MODE": self.demo_mode,
            "ROSA_DATA_DIR": str(self.root),
            "ROSA_DATABASE_URL": "sqlite:///" + str(self.root / self.database_name),
            "ROSA_AI_PROVIDER": "local", "ROSA_SECURE_COOKIES": "0",
            "LOCALAPPDATA": str(self.root),
            "XDG_CONFIG_HOME": str(self.root), "XDG_DATA_HOME": str(self.root),
        })
        env.update(self.environment_overrides())
        self.stack.enter_context(patch.dict(os.environ, env, clear=True))
        original_connect = sqlite3.connect
        original_read = Path.read_text
        original_glob = Path.glob
        original_copy = shutil.copy2
        original_unlink = Path.unlink
        original_open = builtins.open
        original_io_open = io.open
        original_os_open = os.open
        original_os_unlink = os.unlink
        original_socketpair = socket.socketpair
        original_socket_connect = socket.socket.connect
        self.connections = []

        def socketpair(*args, **kwargs):
            # Windows implements asyncio's private wake-up pair using loopback TCP.
            token = _INTERNAL_SOCKETPAIR.set(True)
            try:
                return original_socketpair(*args, **kwargs)
            finally:
                _INTERNAL_SOCKETPAIR.reset(token)

        def socket_connect(sock, address):
            if _INTERNAL_SOCKETPAIR.get() and address[0] in {"127.0.0.1", "::1"}:
                return original_socket_connect(sock, address)
            return self.block_network()

        def guard_data_file(value):
            if isinstance(value, (str, bytes, os.PathLike)):
                path = Path(os.fsdecode(value))
                name = path.name.lower()
                if any(suffix in name for suffix in (".db", ".sqlite")) or name.startswith(".env"):
                    self.require_path(path)

        def connect(database, *args, **kwargs):
            self.require_path(database)
            connection = original_connect(database, *args, **kwargs)
            self.connections.append(connection)

            def authorize(action, arg1, arg2, database_name, trigger):
                if action == sqlite3.SQLITE_ATTACH:
                    try:
                        self.require_path(arg1)
                    except (TestSafetyError, TypeError, ValueError):
                        return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK

            connection.set_authorizer(authorize)
            return connection

        def open_file(file, *args, **kwargs):
            guard_data_file(file)
            return original_open(file, *args, **kwargs)

        def io_open(file, *args, **kwargs):
            guard_data_file(file)
            return original_io_open(file, *args, **kwargs)

        def os_open(file, *args, **kwargs):
            guard_data_file(file)
            return original_os_open(file, *args, **kwargs)

        def os_unlink(file, *args, **kwargs):
            guard_data_file(file)
            return original_os_unlink(file, *args, **kwargs)

        def read_text(path, *args, **kwargs):
            if path.name.startswith(".env") and (not self.allow_local_configuration or not path.resolve().is_relative_to(self.root)):
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
            ("sqlite3.dbapi2.connect", connect),
            ("builtins.open", open_file), ("io.open", io_open),
            ("os.open", os_open), ("os.unlink", os_unlink), ("os.remove", os_unlink),
            ("subprocess.Popen", self.block_subprocess),
            # JUnit metadata must not launch Windows' `ver` subprocess via platform.uname().
            ("platform.node", lambda: "isolated-tests"),
            ("pathlib.Path.glob", glob), ("shutil.copy2", copy),
            ("pathlib.Path.unlink", unlink),
            ("socket.socketpair", socketpair),
            ("socket.socket.connect", socket_connect),
            ("socket.socket.connect_ex", self.block_network),
            ("socket.create_connection", self.block_network),
            ("socket.getaddrinfo", self.block_network),
            ("socket.socket.sendto", self.block_network),
            ("urllib.request.urlopen", self.block_network),
        ):
            self.stack.enter_context(patch(target, replacement))
        self.stack.callback(self.close_connections)
        return self

    def close_connections(self):
        for connection in self.connections:
            try:
                connection.close()
            except sqlite3.Error:
                pass  # Application-owned worker-thread connections close in app.db().
        self.connections.clear()

    def require_path(self, value):
        # Reject SQLite URI/memory names too: all test data must be identifiable files.
        path = Path(value).resolve()
        if not path.is_relative_to(self.root) or path == self.root:
            raise TestSafetyError("Database access outside isolated temporary data is forbidden")
        return path

    @staticmethod
    def block_network(*args, **kwargs):
        raise TestSafetyError("External network access is forbidden during tests; mock the adapter")

    @staticmethod
    def block_subprocess(*args, **kwargs):
        raise TestSafetyError("Child processes do not inherit test guards and are forbidden")

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

        for name, value in (("DB_PATH", self.root / self.database_name),
                            ("LEGACY_DB_PATH", self.root / "absent-legacy.db"),
                            ("DATA_DIR", self.root)):
            self.stack.enter_context(patch.object(app, name, value, create=True))
        for target, replacement in (("init_db", init_db),
                                    ("migrate_legacy_database", migrate)):
            self.stack.enter_context(patch.object(app, target, replacement))
        self.stack.enter_context(patch.object(app.DBConnection, "__init__", connection_init))

    def __exit__(self, *exc):
        return self.stack.__exit__(*exc)
