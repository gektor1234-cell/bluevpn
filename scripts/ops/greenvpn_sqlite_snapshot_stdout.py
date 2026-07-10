#!/usr/bin/env python3
"""Write a consistent Green VPN SQLite backup to stdout.

This script is intentionally quiet on stdout because callers stream the
result over SSH into a local snapshot file.
"""

from __future__ import annotations

import os
import pathlib
import sqlite3
import sys
import tempfile


def _load_env(path: pathlib.Path) -> dict[str, str]:
    env: dict[str, str] = {}
    quote_chars = chr(34) + chr(39)
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = raw.split("=", 1)
        env[key.strip()] = value.strip().strip(quote_chars)
    return env


def _db_path() -> pathlib.Path:
    explicit_db = os.getenv("GREENVPN_SNAPSHOT_DB_PATH", "").strip()
    if explicit_db:
        return pathlib.Path(explicit_db).resolve()
    env_file = pathlib.Path(
        os.getenv("GREENVPN_SNAPSHOT_ENV_FILE", "/etc/bluevpn/backend.env")
    )
    env = _load_env(env_file)
    base = pathlib.Path(env.get("BLUEVPN_BASE_DIR", "/opt/bluevpn/backend")).resolve()
    data = pathlib.Path(env.get("BLUEVPN_DATA_DIR", str(base / "data"))).resolve()
    return data / "bluevpn.db"


def main() -> int:
    source = _db_path()
    if not source.exists():
        print(f"source database not found: {source}", file=sys.stderr)
        return 2

    with tempfile.NamedTemporaryFile(prefix="greenvpn-sync-", suffix=".sqlite", delete=False) as tmp:
        tmp_path = pathlib.Path(tmp.name)

    try:
        src = sqlite3.connect(f"file:{source}?mode=ro", uri=True, timeout=30)
        dst = sqlite3.connect(tmp_path, timeout=30)
        try:
            src.backup(dst)
        finally:
            dst.close()
            src.close()

        with tmp_path.open("rb") as fh:
            while True:
                chunk = fh.read(1024 * 1024)
                if not chunk:
                    break
                sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        return 0
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
