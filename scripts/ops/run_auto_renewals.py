#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(description="Run guarded Green VPN auto-renewals.")
    parser.add_argument("--api-base", default="http://127.0.0.1:8000")
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--limit", type=int, default=5)
    args = parser.parse_args()

    token_path = pathlib.Path(args.token_file)
    token = token_path.read_text(encoding="utf-8").strip()
    if not token:
        raise SystemExit("admin token file is empty")

    base = args.api_base.rstrip("/")
    query = urllib.parse.urlencode({"limit": max(1, min(args.limit, 25))})
    request = urllib.request.Request(
        f"{base}/api/v1/admin/billing/renewals/run?{query}",
        method="POST",
        headers={"X-Admin-Token": token, "Content-Type": "application/json"},
        data=b"{}",
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print(f"auto-renewal request failed: HTTP {exc.code}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"auto-renewal request failed: {type(exc).__name__}", file=sys.stderr)
        return 1

    results = payload.get("results") if isinstance(payload.get("results"), list) else []
    failed = len([item for item in results if not item.get("ok")])
    print(
        "auto-renewals "
        f"enabled={bool(payload.get('enabled'))} "
        f"executed={int(payload.get('executed') or 0)} "
        f"failed={failed}"
    )
    return 0 if payload.get("ok", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
