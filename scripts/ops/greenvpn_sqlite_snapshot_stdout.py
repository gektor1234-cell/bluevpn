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
import gzip
import shutil


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


def _compression() -> str:
    value = os.getenv("GREENVPN_SNAPSHOT_COMPRESSION", "none").strip().lower()
    if value not in {"none", "gzip"}:
        raise ValueError(f"unsupported snapshot compression: {value}")
    return value


def _write_snapshot(path: pathlib.Path, compression: str) -> None:
    with path.open("rb") as source:
        if compression == "gzip":
            with gzip.GzipFile(
                fileobj=sys.stdout.buffer,
                mode="wb",
                compresslevel=1,
                mtime=0,
            ) as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
        else:
            shutil.copyfileobj(source, sys.stdout.buffer, length=1024 * 1024)
    sys.stdout.buffer.flush()


def main() -> int:
    try:
        compression = _compression()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

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

        _write_snapshot(tmp_path, compression)
        return 0
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
