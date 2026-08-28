#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reconcile expired Green VPN subscriptions."
    )
    parser.add_argument("--api-base", default="http://127.0.0.1:8000")
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    token = pathlib.Path(args.token_file).read_text(encoding="utf-8").strip()
    if not token:
        raise SystemExit("admin token file is empty")

    body = json.dumps(
        {
            "dryRun": bool(args.dry_run),
            "limit": max(1, min(int(args.limit), 1000)),
            "reason": "scheduled_subscription_expiry",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{args.api_base.rstrip('/')}/api/v1/admin/subscriptions/expiry/run",
        method="POST",
        headers={"X-Admin-Token": token, "Content-Type": "application/json"},
        data=body,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print(f"subscription expiry request failed: HTTP {exc.code}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(
            f"subscription expiry request failed: {type(exc).__name__}",
            file=sys.stderr,
        )
        return 1

    cleanup = payload.get("peerCleanup")
    cleanup = cleanup if isinstance(cleanup, dict) else {}
    failed = int(cleanup.get("failed") or 0)
    print(
        "subscription-expiry "
        f"dry_run={bool(payload.get('dryRun'))} "
        f"candidates={int(payload.get('candidateCount') or 0)} "
        f"changed={int(payload.get('changedCount') or 0)} "
        f"peer_failed={failed}"
    )
    return 0 if payload.get("ok", False) and failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
