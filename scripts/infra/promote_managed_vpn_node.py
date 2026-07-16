#!/usr/bin/env python3
"""Inspect, prepare and publish one managed Green VPN node safely."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request


ENTRY_FIELDS = {
    "serverId": "serverId",
    "title": "title",
    "subtitle": "subtitle",
    "country": "country",
    "city": "city",
    "provider": "provider",
    "host": "host",
    "port": "port",
    "protocol": "protocol",
    "transport": "transport",
    "clientConfigProfile": "clientConfigProfile",
    "status": "status",
    "healthScore": "healthScore",
    "latencyMs": "latencyMs",
    "priority": "priority",
    "isActive": "isActive",
    "isPublic": "isPublic",
    "plannedBandwidthMbps": ("capacity", "plannedBandwidthMbps"),
    "reservedBandwidthMbps": ("capacity", "reservedBandwidthMbps"),
    "currentLoadMbps": ("capacity", "currentLoadMbps"),
    "activeClients": ("capacity", "activeClients"),
    "assignedUsers": ("capacity", "assignedUsers"),
    "loadUpdatedAt": ("capacity", "loadUpdatedAt"),
    "notes": "notes",
}
SERVER_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base", required=True)
    parser.add_argument(
        "--token-file",
        default="/opt/bluevpn/backend/data/admin_token.txt",
    )
    parser.add_argument("--server-id", required=True)
    parser.add_argument(
        "--action",
        choices=("inspect", "prepare", "publish", "unpublish"),
        default="inspect",
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--reason", default="")
    parser.add_argument("--title")
    parser.add_argument("--country")
    parser.add_argument("--city")
    parser.add_argument("--status", choices=("healthy", "maintenance"))
    parser.add_argument("--health-score", type=int)
    parser.add_argument("--latency-ms", type=int)
    parser.add_argument("--clear-subtitle", action="store_true")
    parser.add_argument("--clear-provider", action="store_true")
    parser.add_argument("--notes-append", default="")
    return parser.parse_args()


class Api:
    def __init__(self, base: str, token_file: str) -> None:
        self.base = base.rstrip("/")
        if not self.base.startswith("https://"):
            raise SystemExit("--api-base must use HTTPS")
        self.token = pathlib.Path(token_file).read_text(encoding="utf-8").strip()
        if not self.token:
            raise SystemExit("Admin token file is empty")

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        data = None
        headers = {"Accept": "application/json", "X-Admin-Token": self.token}
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            self.base + path,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as error:
            raw = error.read().decode("utf-8", errors="replace")
            try:
                detail = json.loads(raw).get("detail")
            except (ValueError, AttributeError):
                detail = raw[:300]
            raise SystemExit(f"HTTP {error.code}: {detail}") from None


def catalog_entry(api: Api, server_id: str) -> dict:
    payload = api.call(
        "GET",
        "/api/v1/admin/server-catalog?status=all&active=all&public=all&limit=500",
    )
    entries = payload.get("managedEntries") or []
    entry = next(
        (item for item in entries if item.get("serverId") == server_id),
        None,
    )
    if entry is None:
        raise SystemExit("Managed server entry was not found")
    return entry


def public_ids(api: Api) -> list[str]:
    payload = api.call(
        "GET",
        "/api/v1/catalog/servers?channel=stable&appVersion=0.3.2",
    )
    servers = ((payload.get("catalog") or {}).get("servers") or [])
    return [str(item.get("id") or "") for item in servers]


def gate(api: Api, server_id: str) -> dict:
    return api.call(
        "GET",
        f"/api/v1/admin/server-catalog/{server_id}/publication-gate",
    )


def entry_value(entry: dict, source: str | tuple[str, str]):
    if isinstance(source, tuple):
        return (entry.get(source[0]) or {}).get(source[1])
    return entry.get(source)


def update_payload(entry: dict) -> dict:
    return {
        target: entry_value(entry, source)
        for target, source in ENTRY_FIELDS.items()
    }


def safe_entry_summary(entry: dict) -> dict:
    return {
        "found": bool(entry),
        "serverId": entry.get("serverId"),
        "title": entry.get("title"),
        "country": entry.get("country"),
        "city": entry.get("city"),
        "status": entry.get("status"),
        "healthScore": entry.get("healthScore"),
        "latencyMs": entry.get("latencyMs"),
        "isActive": bool(entry.get("isActive")),
        "isPublic": bool(entry.get("isPublic")),
        "clientConfigReady": bool(entry.get("clientConfigReady")),
    }


def safe_gate_summary(payload: dict) -> dict:
    candidate = payload.get("candidate") or {}
    return {
        "canPublish": bool(payload.get("canPublish")),
        "blockerCodes": [
            item.get("code") for item in payload.get("blockers") or []
        ],
        "latestObservationAt": candidate.get("latestObservationAt"),
        "latestObservationStatus": candidate.get("latestObservationStatus"),
        "healthyObservations24h": candidate.get("healthyObservations24h"),
        "failedObservations24h": candidate.get("failedObservations24h"),
    }


def require_apply(args: argparse.Namespace) -> None:
    if not args.apply:
        raise SystemExit("Mutation blocked: pass --apply after reviewing inspect output")
    if len(args.reason.strip()) < 12:
        raise SystemExit("Mutation blocked: --reason must contain at least 12 characters")


def main() -> int:
    args = parse_args()
    if not SERVER_ID_PATTERN.fullmatch(args.server_id):
        raise SystemExit("--server-id contains unsupported characters")
    api = Api(args.api_base, args.token_file)
    before = catalog_entry(api, args.server_id)

    if args.action == "inspect":
        output = {
            "ok": True,
            "action": "inspect",
            "entry": safe_entry_summary(before),
            "gate": safe_gate_summary(gate(api, args.server_id)),
            "inStableCatalog": args.server_id in public_ids(api),
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return 0

    require_apply(args)

    if args.action == "prepare":
        if before.get("isActive") or before.get("isPublic"):
            raise SystemExit("Prepare is allowed only while the node is hidden")
        payload = update_payload(before)
        if args.title is not None:
            payload["title"] = args.title.strip()
        if args.country is not None:
            payload["country"] = args.country.strip().upper()
        if args.city is not None:
            payload["city"] = args.city.strip()
        if args.status is not None:
            payload["status"] = args.status
        if args.health_score is not None:
            payload["healthScore"] = max(0, min(args.health_score, 100))
        if args.latency_ms is not None:
            payload["latencyMs"] = max(0, args.latency_ms)
        if args.clear_subtitle:
            payload["subtitle"] = ""
        if args.clear_provider:
            payload["provider"] = ""
        if args.notes_append.strip():
            existing_notes = str(payload.get("notes") or "").strip()
            payload["notes"] = "\n".join(
                item for item in (existing_notes, args.notes_append.strip()) if item
            )
        payload["isActive"] = False
        payload["isPublic"] = False
        response = api.call(
            "POST",
            f"/api/v1/admin/server-catalog/{int(before['id'])}",
            payload,
        )
        after = response.get("entry") or catalog_entry(api, args.server_id)
        output = {
            "ok": True,
            "action": "prepare",
            "before": safe_entry_summary(before),
            "after": safe_entry_summary(after),
            "gate": safe_gate_summary(gate(api, args.server_id)),
            "inStableCatalog": args.server_id in public_ids(api),
        }
    elif args.action == "publish":
        gate_before = gate(api, args.server_id)
        if not gate_before.get("canPublish"):
            raise SystemExit(
                "Publication gate blocked: "
                + ",".join(safe_gate_summary(gate_before)["blockerCodes"])
            )
        response = api.call(
            "POST",
            f"/api/v1/admin/server-catalog/{args.server_id}/publish",
            {},
        )
        after = response.get("entry") or catalog_entry(api, args.server_id)
        in_stable = args.server_id in public_ids(api)
        if not (after.get("isActive") and after.get("isPublic") and in_stable):
            raise SystemExit("Publication verification failed")
        output = {
            "ok": True,
            "action": "publish",
            "entry": safe_entry_summary(after),
            "gate": safe_gate_summary(gate(api, args.server_id)),
            "inStableCatalog": in_stable,
        }
    else:
        response = api.call(
            "POST",
            f"/api/v1/admin/server-catalog/{args.server_id}/unpublish",
            {},
        )
        after = response.get("entry") or catalog_entry(api, args.server_id)
        in_stable = args.server_id in public_ids(api)
        if after.get("isPublic") or in_stable:
            raise SystemExit("Unpublish verification failed")
        output = {
            "ok": True,
            "action": "unpublish",
            "entry": safe_entry_summary(after),
            "inStableCatalog": in_stable,
        }

    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
