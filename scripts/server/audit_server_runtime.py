#!/usr/bin/env python3
"""Produce a secret-safe, read-only Green VPN server runtime inventory."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import sqlite3
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


KNOWN_SERVICES = (
    "bluevpn-backend.service",
    "greenvpn-paid-beta.service",
    "greenvpn-db-sync.service",
    "greenvpn-paid-beta-db-sync.service",
    "greenvpn-service-probe.service",
    "greenvpn-paid-beta-service-probe.service",
    "wg-quick@wg0.service",
    "greenvpn-amneziawg-canary.service",
    "greenvpn-hysteria2-canary.service",
    "greenvpn-vless-reality-canary.service",
    "greenvpn-naive-https-canary.service",
    "greenvpn-dnstt-canary.service",
    "greenvpn-dnstt-socks-canary.service",
    "greenvpn-dnstt-dns-front.service",
    "greenvpn-yandex-smtp-relay.service",
    "greenvpn-vpn-capacity-report.service",
)

KNOWN_TIMERS = (
    "greenvpn-db-sync.timer",
    "greenvpn-paid-beta-db-sync.timer",
    "greenvpn-service-probe.timer",
    "greenvpn-paid-beta-service-probe.timer",
    "greenvpn-subscription-expiry.timer",
    "greenvpn-billing-renewals.timer",
    "greenvpn-vpn-capacity-report.timer",
)

ENV_PATHS = (
    "/etc/bluevpn/backend.env",
    "/etc/bluevpn/paid-beta.env",
    "/etc/bluevpn/node.env",
    "/etc/bluevpn/paid-beta-node.env",
)

DATABASE_PATHS = (
    "/opt/bluevpn/backend/data/bluevpn.db",
    "/opt/bluevpn-paid-beta/data/bluevpn.db",
)

RELEASE_LINKS = (
    "/opt/bluevpn/backend/current",
    "/opt/bluevpn/current",
    "/opt/bluevpn-paid-beta/current",
)

COUNT_TABLES = (
    "users",
    "sessions",
    "devices",
    "subscriptions",
    "payments",
    "billing_orders",
    "payment_methods",
    "server_catalog_entries",
    "app_releases",
    "replication_tombstones",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def run(command: list[str], timeout: int = 20) -> dict[str, Any]:
    try:
        process = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "returnCode": process.returncode,
            "stdout": process.stdout.strip(),
            "stderr": process.stderr.strip()[:500],
        }
    except FileNotFoundError:
        return {"returnCode": 127, "stdout": "", "stderr": "command_not_found"}
    except subprocess.TimeoutExpired:
        return {"returnCode": 124, "stdout": "", "stderr": "command_timeout"}


def mode_string(path: Path) -> str:
    return oct(stat.S_IMODE(path.stat().st_mode))


def inspect_env(path_text: str) -> dict[str, Any]:
    path = Path(path_text)
    result: dict[str, Any] = {"path": path_text, "exists": path.is_file()}
    if not path.is_file():
        return result
    keys: list[str] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=", line)
        if match:
            keys.append(match.group(1))
    info = path.stat()
    result.update(
        {
            "mode": mode_string(path),
            "uid": info.st_uid,
            "gid": info.st_gid,
            "keys": sorted(set(keys)),
        }
    )
    return result


def table_names(connection: sqlite3.Connection) -> set[str]:
    return {
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }


def inspect_database(path_text: str) -> dict[str, Any]:
    path = Path(path_text)
    result: dict[str, Any] = {"path": path_text, "exists": path.is_file()}
    if not path.is_file():
        return result
    info = path.stat()
    result.update(
        {
            "sizeBytes": info.st_size,
            "mode": mode_string(path),
            "uid": info.st_uid,
            "gid": info.st_gid,
        }
    )
    try:
        connection = sqlite3.connect(f"file:{path_text}?mode=ro", uri=True, timeout=20)
        try:
            names = table_names(connection)
            counts = {
                name: int(connection.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0])
                for name in COUNT_TABLES
                if name in names
            }
            sequence = {}
            if "sqlite_sequence" in {
                str(row[0])
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }:
                sequence = {
                    str(row[0]): int(row[1])
                    for row in connection.execute("SELECT name, seq FROM sqlite_sequence ORDER BY name")
                    if str(row[0]) in COUNT_TABLES
                }
            result.update(
                {
                    "quickCheck": str(connection.execute("PRAGMA quick_check").fetchone()[0]),
                    "userVersion": int(connection.execute("PRAGMA user_version").fetchone()[0]),
                    "schemaVersion": int(connection.execute("PRAGMA schema_version").fetchone()[0]),
                    "tables": sorted(names),
                    "counts": counts,
                    "sequences": sequence,
                }
            )
        finally:
            connection.close()
    except Exception as error:
        result["error"] = f"{type(error).__name__}:{error}"[:500]
    return result


def unit_state(unit: str) -> dict[str, Any]:
    state = run(
        [
            "systemctl",
            "show",
            unit,
            "--no-pager",
            "--property=LoadState,ActiveState,SubState,UnitFileState,Result",
        ]
    )
    properties = {}
    for line in state["stdout"].splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return {"unit": unit, **properties}


def directory_size(path: Path) -> int | None:
    measured = run(["du", "-sb", "--", str(path)], timeout=120)
    if measured["returnCode"] != 0 or not measured["stdout"]:
        return None
    try:
        return int(measured["stdout"].split()[0])
    except (ValueError, IndexError):
        return None


def backup_inventory() -> list[dict[str, Any]]:
    candidates: list[Path] = []
    pattern = re.compile(r"backup|snapshot|checkpoint|pre[-_]", re.IGNORECASE)
    for root_text in ("/root", "/opt"):
        root = Path(root_text)
        if not root.is_dir():
            continue
        for child in root.iterdir():
            if child.is_dir() and not child.is_symlink() and pattern.search(child.name):
                candidates.append(child)
    result = []
    for path in sorted(candidates, key=lambda item: str(item)):
        info = path.stat()
        result.append(
            {
                "path": str(path),
                "sizeBytes": directory_size(path),
                "updatedUtc": datetime.fromtimestamp(info.st_mtime, timezone.utc)
                .isoformat()
                .replace("+00:00", "Z"),
            }
        )
    return result


def root_files_inventory() -> list[dict[str, Any]]:
    root = Path("/root")
    if not root.is_dir():
        return []
    result = []
    for path in sorted(root.iterdir(), key=lambda item: item.name):
        if not path.is_file() or path.is_symlink():
            continue
        if not re.search(r"greenvpn|bluevpn", path.name, re.IGNORECASE):
            continue
        info = path.stat()
        result.append(
            {
                "name": path.name,
                "sizeBytes": info.st_size,
                "mode": mode_string(path),
                "updatedUtc": datetime.fromtimestamp(info.st_mtime, timezone.utc)
                .isoformat()
                .replace("+00:00", "Z"),
            }
        )
    return result


def disk_usage(path: str) -> dict[str, int]:
    usage = shutil.disk_usage(path)
    return {"totalBytes": usage.total, "usedBytes": usage.used, "freeBytes": usage.free}


def release_links() -> list[dict[str, Any]]:
    result = []
    for path_text in RELEASE_LINKS:
        path = Path(path_text)
        result.append(
            {
                "path": path_text,
                "exists": path.exists(),
                "isSymlink": path.is_symlink(),
                "target": os.path.realpath(path_text) if path.exists() else "",
            }
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact", action="store_true")
    args = parser.parse_args()

    failed_units = run(["systemctl", "--failed", "--no-legend", "--plain"])
    listeners = run(["ss", "-H", "-lntu"])
    nginx_installed = shutil.which("nginx") is not None
    nginx = run(["nginx", "-t"]) if nginx_installed else None
    sshd = run(["sshd", "-T"])
    ssh_allowed = {
        "passwordauthentication",
        "permitrootlogin",
        "pubkeyauthentication",
        "kbdinteractiveauthentication",
        "x11forwarding",
        "allowtcpforwarding",
        "maxauthtries",
    }
    ssh_settings = {}
    for line in sshd["stdout"].splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0] in ssh_allowed:
            ssh_settings[parts[0]] = parts[1]

    upgrades = run(["apt", "list", "--upgradable"])
    upgrade_lines = [
        line for line in upgrades["stdout"].splitlines() if line and not line.startswith("Listing")
    ]
    upgrade_packages = sorted({line.split("/", 1)[0] for line in upgrade_lines})
    held = run(["apt-mark", "showhold"])
    held_packages = sorted(line for line in held["stdout"].splitlines() if line)
    actionable_updates = sorted(set(upgrade_packages) - set(held_packages))
    report = {
        "schema": 1,
        "auditedAt": utc_now(),
        "hostname": socket.gethostname(),
        "root": os.geteuid() == 0,
        "osRelease": Path("/etc/os-release").read_text(encoding="utf-8", errors="replace")
        if Path("/etc/os-release").is_file()
        else "",
        "kernel": run(["uname", "-srvmo"])["stdout"],
        "uptime": run(["uptime", "-p"])["stdout"],
        "disk": {"root": disk_usage("/")},
        "failedUnits": failed_units["stdout"].splitlines(),
        "services": [unit_state(unit) for unit in KNOWN_SERVICES],
        "timers": [unit_state(unit) for unit in KNOWN_TIMERS],
        "releaseLinks": release_links(),
        "environmentFiles": [inspect_env(path) for path in ENV_PATHS],
        "databases": [inspect_database(path) for path in DATABASE_PATHS],
        "listeners": listeners["stdout"].splitlines(),
        "nginxInstalled": nginx_installed,
        "nginxConfigOk": nginx["returnCode"] == 0 if nginx is not None else None,
        "sshEffectiveSettings": ssh_settings,
        "unattendedUpgrades": unit_state("unattended-upgrades.service"),
        "fail2ban": unit_state("fail2ban.service"),
        "pendingPackageUpdates": len(upgrade_lines),
        "pendingPackageNames": upgrade_packages,
        "heldPackages": held_packages,
        "actionablePackageUpdates": len(actionable_updates),
        "backupDirectories": backup_inventory(),
        "greenVpnRootFiles": root_files_inventory(),
    }
    print(json.dumps(report, ensure_ascii=False, separators=(",", ":") if args.compact else None, indent=None if args.compact else 2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
