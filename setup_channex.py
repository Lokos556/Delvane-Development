from __future__ import annotations

import getpass
import json
from pathlib import Path
import urllib.error
import urllib.request
import os


ROOT = Path(__file__).resolve().parent
def stable_env_path() -> Path:
    if os.name == "nt" and os.getenv("LOCALAPPDATA", "").strip():
        return Path(os.environ["LOCALAPPDATA"]) / "Rosa" / ".env.local"
    xdg=os.getenv("XDG_CONFIG_HOME", "").strip()
    return (Path(xdg) / "rosa" / ".env.local") if xdg else ROOT / ".env.local"

ENV = stable_env_path()
BASE_URL = "https://staging.channex.io"


def _read_env() -> tuple[list[str], dict[str, str]]:
    lines = ENV.read_text(encoding="utf-8").splitlines() if ENV.exists() else []
    values: dict[str, str] = {}
    for raw in lines:
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return lines, values


def _set_env_values(updates: dict[str, str]) -> None:
    ENV.parent.mkdir(parents=True,exist_ok=True)
    lines, _ = _read_env()
    remaining = dict(updates)
    output: list[str] = []
    for raw in lines:
        stripped = raw.strip()
        key = stripped.split("=", 1)[0].strip() if "=" in stripped and not stripped.startswith("#") else ""
        if key in remaining:
            output.append(f"{key}={remaining.pop(key)}")
        else:
            output.append(raw)
    if output and output[-1].strip():
        output.append("")
    if remaining:
        output.append("# Rosa-managed Channex staging connection. DO NOT SHARE OR UPLOAD THIS FILE.")
        output.extend(f"{key}={value}" for key, value in remaining.items())
    ENV.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")


def test_key(key: str) -> tuple[bool, str]:
    request = urllib.request.Request(
        f"{BASE_URL}/api/v1/properties?pagination[limit]=100",
        headers={"user-api-key": key, "Accept": "application/json"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            payload = json.loads(response.read().decode("utf-8"))
        properties = payload.get("data", [])
        names = [str((item.get("attributes") or {}).get("title") or item.get("id")) for item in properties]
        summary = f"Connected. Rosa can access {len(properties)} staging propert{'y' if len(properties) == 1 else 'ies'}."
        if names:
            summary += " Found: " + ", ".join(names[:5])
        return True, summary
    except urllib.error.HTTPError as exc:
        return False, f"Channex returned HTTP {exc.code}. Check that the complete staging API key was copied."
    except Exception as exc:
        return False, f"{type(exc).__name__}: {exc}"


def main() -> None:
    print("\nROSA V2.10.0 — Channex staging connection")
    print("This is Rosa's developer key. Future Rosa customers will not enter Channex API keys.")
    print("The key is stored in Rosa's private persistent configuration on this computer.")
    print("Do not paste it into ChatGPT or send .env.local to anyone.\n")
    key = getpass.getpass("Paste the Channex staging API key (hidden): ").strip()
    if len(key) < 20:
        raise SystemExit("That does not look like a complete API key. Nothing was saved.")
    ok, message = test_key(key)
    if not ok:
        raise SystemExit("\nConnection failed: " + message + "\nNothing was saved.")
    _set_env_values({"ROSA_CHANNEX_API_KEY": key, "ROSA_CHANNEX_BASE_URL": BASE_URL})
    print("\n" + message)
    print("The key was saved securely for local Rosa development.")
    print("Close any running Rosa server, then start it again with START_ROSA.bat.")


if __name__ == "__main__":
    main()
