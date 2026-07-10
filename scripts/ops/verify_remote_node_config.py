import asyncio
import hashlib
import inspect
import json
import sys


def fingerprint(value: str) -> str:
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()[:12] if value else ""


def value(obj, key: str, default=None):
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def first_value(obj, keys: list[str], default=""):
    for key in keys:
        found = value(obj, key)
        if found:
            return found
    return default


async def main() -> int:
    server_id = sys.argv[1] if len(sys.argv) > 1 else "ruvds-2584554-ld8"
    import app.main as app

    node = app.load_remote_vpn_node_config(server_id)
    probe_result = app.remote_vpn_node_probe(node)
    probe = await probe_result if inspect.isawaitable(probe_result) else probe_result
    print(
        json.dumps(
            {
                "serverId": server_id,
                "loaded": bool(node),
                "nodeKeys": sorted(node.keys()) if isinstance(node, dict) else [],
                "configuredFingerprint": fingerprint(
                    first_value(
                        node,
                        [
                            "wg_public_key",
                            "wgPublicKey",
                            "wireguard_public_key",
                            "public_key",
                            "server_public_key",
                            "GREENVPN_NODE_WG_PUBLIC_KEY",
                        ],
                    )
                ),
                "probeOk": bool(value(probe, "ok", False)),
                "probePublicKeyMatches": bool(
                    value(probe, "public_key_matches", value(probe, "publicKeyMatches", False))
                ),
                "probeLatencyMs": value(probe, "latency_ms"),
                "probeKeys": sorted(probe.keys()) if isinstance(probe, dict) else [],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
