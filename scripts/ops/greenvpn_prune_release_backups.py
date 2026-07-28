#!/usr/bin/env python3
"""Keep a bounded number of Green VPN release rollback directories."""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil


BACKUP_ROOTS = (
    pathlib.Path("/root/greenvpn-public-product-backups"),
    pathlib.Path("/root/greenvpn-paid-beta-backend-backups"),
    pathlib.Path("/root/greenvpn-paid-beta-client-release-backups"),
    pathlib.Path("/root/greenvpn-paid-beta-backups"),
    pathlib.Path("/root/greenvpn-apk-release-backups"),
    pathlib.Path("/root/greenvpn-windows-release-backups"),
    pathlib.Path("/root/greenvpn-main-site-backups"),
    pathlib.Path("/root/greenvpn-admin-static-backups"),
    pathlib.Path("/root/greenvpn-release-rollback-backups"),
)


def prune_root(root: pathlib.Path, keep: int, apply: bool) -> dict[str, object]:
    if not root.exists():
        return {"root": str(root), "status": "missing"}
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"backup root is not a regular directory: {root}")

    resolved_root = root.resolve(strict=True)
    entries = sorted(
        (
            child
            for child in resolved_root.iterdir()
            if child.is_dir() and not child.is_symlink()
        ),
        key=lambda child: (child.stat().st_mtime_ns, child.name),
        reverse=True,
    )
    retained = entries[:keep]
    candidates = entries[keep:]

    removed: list[str] = []
    for child in candidates:
        resolved_child = child.resolve(strict=True)
        if resolved_child.parent != resolved_root or child.is_symlink():
            raise ValueError(f"unsafe backup candidate: {child}")
        removed.append(str(resolved_child))
        if apply:
            shutil.rmtree(resolved_child)

    return {
        "root": str(resolved_root),
        "status": "ok",
        "apply": apply,
        "keep": keep,
        "retained": [str(path) for path in retained],
        "removed": removed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--keep", type=int, default=4)
    args = parser.parse_args()
    if args.keep < 2 or args.keep > 20:
        parser.error("--keep must be between 2 and 20")

    results = [prune_root(root, keep=args.keep, apply=args.apply) for root in BACKUP_ROOTS]
    print(json.dumps({"ok": True, "results": results}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
