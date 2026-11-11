"""Guard checks runnable without pytest, FastAPI, or any operational database."""
import os
from pathlib import Path
import shutil
import socket
import sqlite3
from types import SimpleNamespace
import unittest
import urllib.request
from contextlib import closing

from testing_safety import IsolatedEnvironment, TestSafetyError


class IsolationTests(unittest.TestCase):
    def test_environment_is_replaced_and_restored(self):
        previous = dict(os.environ)
        with IsolatedEnvironment() as safety:
            self.assertEqual(os.environ["ROSA_APP_ENV"], "test")
            self.assertNotIn("OPENAI_API_KEY", os.environ)
            self.assertNotIn("ROSA_CHANNEX_API_KEY", os.environ)
            self.assertEqual(Path(os.environ["ROSA_DATA_DIR"]), safety.root)
        self.assertEqual(dict(os.environ), previous)

    def test_sqlite_outside_temp_is_blocked_before_open(self):
        with IsolatedEnvironment() as safety:
            with self.assertRaises(TestSafetyError):
                sqlite3.connect(safety.root.parent / "never-open.db")
            with closing(sqlite3.connect(safety.root / "safe.db")) as con:
                con.execute("CREATE TABLE synthetic(value INTEGER)")

    def test_sqlite_uris_and_memory_names_are_rejected(self):
        with IsolatedEnvironment():
            for value in (":memory:", "file:outside.db?mode=rw"):
                with self.assertRaises(TestSafetyError):
                    sqlite3.connect(value, uri=True)

    def test_reset_guard_runs_before_application_delete(self):
        calls = []
        class Connection:
            def __init__(self):
                calls.append("connect")
        app = SimpleNamespace(DBConnection=Connection, DB_BACKEND="sqlite",
                              init_db=lambda **kw: calls.append("reset"),
                              migrate_legacy_database=lambda: calls.append("migrate"))
        with IsolatedEnvironment() as safety:
            safety.protect_app(app)
            app.DB_PATH = safety.root.parent / "never-reset.db"
            with self.assertRaises(TestSafetyError):
                app.init_db(reset=True)
            with self.assertRaises(TestSafetyError):
                app.DBConnection()
            self.assertEqual(calls, [])
            app.DB_PATH = safety.root / "safe.db"
            app.DB_BACKEND = "postgresql"
            with self.assertRaises(TestSafetyError):
                app.DBConnection()
            with self.assertRaises(TestSafetyError):
                app.init_db(reset=True)
            self.assertEqual(calls, [])

    def test_local_environment_and_sibling_discovery_are_blocked(self):
        with IsolatedEnvironment() as safety:
            self.assertEqual((safety.root.parent / ".env.local").read_text(), "")
            self.assertEqual(list(safety.root.parent.glob("rosa-v*/rosa.db")), [])
            with self.assertRaises(OSError):
                shutil.copy2(safety.root.parent / "never-read.db", safety.root / "copy.db")

    def test_database_unlink_is_blocked_before_filesystem_access(self):
        with IsolatedEnvironment() as safety:
            with self.assertRaises(TestSafetyError):
                (safety.root.parent / "never-delete.db").unlink()

    def test_nested_isolation_can_use_its_own_temporary_database(self):
        with IsolatedEnvironment() as outer:
            with IsolatedEnvironment() as inner:
                self.assertTrue(inner.root.is_relative_to(outer.root))
                with closing(sqlite3.connect(inner.root / "nested.db")) as con:
                    con.execute("SELECT 1")

    def test_network_is_blocked(self):
        with IsolatedEnvironment():
            with self.assertRaises(TestSafetyError):
                urllib.request.urlopen("https://example.invalid")
            with self.assertRaises(TestSafetyError):
                socket.getaddrinfo("example.invalid", 443)
            with socket.socket() as sock:
                with self.assertRaises(TestSafetyError):
                    sock.connect(("127.0.0.1", 1))


if __name__ == "__main__":
    unittest.main()
