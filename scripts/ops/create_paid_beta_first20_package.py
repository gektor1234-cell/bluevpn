#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import pathlib
import re
import shutil
import tempfile
import urllib.request
from datetime import datetime, timezone
from typing import Any


APPROVED_API_BASES = {
    "http://127.0.0.1:8010",
    "https://api.greenvpn.pro/paid-beta-api",
    "https://176-113-81-35.sslip.io/paid-beta-api",
}
LOCAL_PRIMARY_API_BASE = "http://127.0.0.1:8010"
POSIX_OUTPUT_ROOT = pathlib.Path("/root/greenvpn-paid-beta-first20")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create the protected owner package for the first paid beta cohort.",
    )
    parser.add_argument("--api-base", default="http://127.0.0.1:8010")
    parser.add_argument("--admin-token-file", default="")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--label-prefix", default="First 20")
    parser.add_argument("--source", default="first20-owner-invite-20260710")
    parser.add_argument("--expires-at", default="")
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def validate_plan(args: argparse.Namespace) -> tuple[str, pathlib.Path]:
    api_base = str(args.api_base or "").strip().rstrip("/")
    if api_base not in APPROVED_API_BASES:
        raise ValueError("api-base must be an approved isolated paid beta endpoint")
    if args.count < 1 or args.count > 50:
        raise ValueError("count must be 1..50")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{4,79}", args.source):
        raise ValueError("source must be a stable 5..80 character identifier")
    if not str(args.label_prefix or "").strip():
        raise ValueError("label-prefix cannot be empty")
    output_dir = pathlib.Path(args.output_dir).expanduser().resolve()
    if output_dir.exists():
        raise ValueError(f"output directory already exists: {output_dir}")
    return api_base, output_dir


def api_request(
    api_base: str,
    token: str,
    path: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None
    headers = {
        "Accept": "application/json",
        "X-Admin-Token": token,
        "X-Admin-Actor": "paid-beta-first20-package",
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        api_base + path,
        data=data,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def validate_created_invites(response: dict[str, Any], expected_count: int) -> list[dict[str, Any]]:
    invites = list(response.get("invites") or [])
    if response.get("codesShownOnce") is not True or len(invites) != expected_count:
        raise RuntimeError("paid beta API returned an incomplete invite batch")
    codes = []
    ids = []
    for invite in invites:
        code = str(invite.get("code") or "").strip()
        invite_id = str(invite.get("inviteId") or "").strip()
        if not re.fullmatch(r"GREEN-[A-Z0-9-]{8,64}", code):
            raise RuntimeError("paid beta API returned an invalid invite code")
        if not invite_id.startswith("inv_"):
            raise RuntimeError("paid beta API returned an invalid invite id")
        if int(invite.get("maxUses") or 0) != 1:
            raise RuntimeError("first20 invite must be single-use")
        codes.append(code)
        ids.append(invite_id)
    if len(set(codes)) != expected_count or len(set(ids)) != expected_count:
        raise RuntimeError("paid beta API returned duplicate invites")
    return invites


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def secure_file(path: pathlib.Path) -> None:
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def securely_remove(path: pathlib.Path) -> None:
    if not path.exists():
        return
    try:
        size = path.stat().st_size
        with path.open("r+b", buffering=0) as stream:
            stream.write(b"\0" * size)
            os.fsync(stream.fileno())
    finally:
        path.unlink(missing_ok=True)


def write_recovery_response(path: pathlib.Path, response: dict[str, Any]) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(response, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    secure_file(path)


def write_package(
    output_dir: pathlib.Path,
    *,
    api_base: str,
    source: str,
    invites: list[dict[str, Any]],
) -> None:
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary = pathlib.Path(
        tempfile.mkdtemp(prefix=output_dir.name + ".tmp-", dir=output_dir.parent)
    )
    try:
        os.chmod(temporary, 0o700)
        secret_csv = temporary / "invites_secret.csv"
        with secret_csv.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(
                ["slot", "invite_id", "label", "code", "expires_at", "max_uses"]
            )
            for slot, invite in enumerate(invites, start=1):
                writer.writerow(
                    [
                        slot,
                        invite["inviteId"],
                        invite.get("label") or "",
                        invite["code"],
                        invite.get("expiresAt") or "",
                        invite.get("maxUses") or 1,
                    ]
                )
        secure_file(secret_csv)

        tracker_csv = temporary / "participant_tracker.csv"
        with tracker_csv.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(
                [
                    "slot",
                    "invite_id",
                    "code_hint",
                    "participant",
                    "contact",
                    "sent_at",
                    "installed",
                    "connected",
                    "payment_opened",
                    "paid",
                    "day7_active",
                    "support_issue",
                    "notes",
                ]
            )
            for slot, invite in enumerate(invites, start=1):
                writer.writerow(
                    [
                        slot,
                        invite["inviteId"],
                        invite.get("codeHint") or "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                    ]
                )
        secure_file(tracker_csv)

        readme = temporary / "README_RU.txt"
        readme.write_text(
            "Green VPN: пакет первых 20 участников\n\n"
            "Файл invites_secret.csv содержит полные одноразовые коды. Не отправляйте "
            "его целиком и не публикуйте. Каждому человеку передаётся только одна строка.\n\n"
            "Перед первой отправкой должны быть закрыты четыре gate:\n"
            "1. Android beta установлена и проверена на реальном телефоне.\n"
            "2. Windows beta установлена и проверена на реальном ПК.\n"
            "3. Выполнен один реальный платёж 149 RUB и проверена активация.\n"
            "4. Владелец принял beta-условия и ограничения распространения.\n\n"
            "Основная beta-страница: https://greenvpn.pro/paid-beta/\n"
            "Резервная beta-страница: https://176-113-81-35.sslip.io/paid-beta/\n"
            "Условия: 3 дня Trial, первый период 149 RUB, далее 299 RUB вручную, "
            "до 2 устройств, без рекламы и автопродления.\n",
            encoding="utf-8",
        )
        secure_file(readme)

        manifest_path = temporary / "manifest.json"
        manifest = {
            "kind": "greenvpn-paid-beta-first20-owner-package",
            "containsInviteSecrets": True,
            "createdAt": utc_now_iso(),
            "apiBase": api_base,
            "source": source,
            "count": len(invites),
            "inviteIds": [item["inviteId"] for item in invites],
            "expiresAt": sorted(
                {str(item.get("expiresAt") or "") for item in invites}
            ),
            "files": {},
        }
        for path in (secret_csv, tracker_csv, readme):
            manifest["files"][path.name] = {
                "sizeBytes": path.stat().st_size,
                "sha256": file_sha256(path),
            }
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        secure_file(manifest_path)
        temporary.rename(output_dir)
        os.chmod(output_dir, 0o700)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> int:
    args = parse_args()
    api_base, output_dir = validate_plan(args)
    plan = {
        "mode": "apply" if args.apply else "dry-run",
        "apiBase": api_base,
        "count": args.count,
        "source": args.source,
        "outputDir": str(output_dir),
        "codesPrinted": False,
        "productionChanged": False,
    }
    if not args.apply:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return 0
    if api_base != LOCAL_PRIMARY_API_BASE:
        raise ValueError("--apply is allowed only through the local paid beta primary")
    if os.name == "posix":
        try:
            output_dir.relative_to(POSIX_OUTPUT_ROOT.resolve())
        except ValueError as error:
            raise ValueError(
                f"POSIX output must stay under {POSIX_OUTPUT_ROOT}"
            ) from error
    if not args.admin_token_file:
        raise ValueError("--admin-token-file is required with --apply")
    token_path = pathlib.Path(args.admin_token_file).expanduser().resolve()
    token = token_path.read_text(encoding="utf-8").strip()
    if len(token) < 24:
        raise ValueError("admin token file is not ready")

    current = api_request(api_base, token, "/api/v1/admin/paid-beta/invites?limit=500")
    existing = [
        item
        for item in list(current.get("invites") or [])
        if str(item.get("source") or "") == args.source
    ]
    if existing:
        raise RuntimeError(
            "invites with this source already exist; refusing to create unrecoverable duplicate codes"
        )

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "posix":
        os.chmod(POSIX_OUTPUT_ROOT, 0o700)
        os.chmod(output_dir.parent, 0o700)
    recovery_path = output_dir.parent / f".{output_dir.name}.invite-response.recovery.json"
    if recovery_path.exists():
        raise RuntimeError(f"recovery file already exists: {recovery_path}")

    payload: dict[str, Any] = {
        "count": args.count,
        "labelPrefix": args.label_prefix,
        "source": args.source,
        "maxUses": 1,
    }
    if args.expires_at:
        payload["expiresAt"] = args.expires_at
    response = api_request(
        api_base,
        token,
        "/api/v1/admin/paid-beta/invites/batch",
        method="POST",
        payload=payload,
    )
    write_recovery_response(recovery_path, response)
    try:
        invites = validate_created_invites(response, args.count)
        write_package(
            output_dir,
            api_base=api_base,
            source=args.source,
            invites=invites,
        )
    except Exception:
        raise RuntimeError(
            f"package creation failed; one-time codes remain in {recovery_path}"
        )
    securely_remove(recovery_path)
    plan["created"] = True
    plan["inviteCount"] = len(invites)
    plan["expiresAt"] = sorted(
        {str(item.get("expiresAt") or "") for item in invites}
    )
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
