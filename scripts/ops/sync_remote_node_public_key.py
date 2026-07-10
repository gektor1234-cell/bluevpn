import hashlib
import json
import pathlib
import subprocess
import sys


def fingerprint(value: str) -> str:
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()[:12] if value else ""


def parse_env(path: pathlib.Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def update_env_value(path: pathlib.Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    seen = False
    prefix = key + "="
    for raw in lines:
        if raw.strip().startswith(prefix):
            if not seen:
                out.append(prefix + value)
                seen = True
            continue
        out.append(raw)
    if not seen:
        out.append(prefix + value)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> int:
    server_id = sys.argv[1] if len(sys.argv) > 1 else "ruvds-2584554-ld8"
    path = pathlib.Path(f"/etc/bluevpn/vpn_nodes/{server_id}.env")
    env = parse_env(path)
    interface = env.get("GREENVPN_NODE_WG_INTERFACE", "wg0")
    cmd = [
        "ssh",
        "-i",
        env["GREENVPN_NODE_SSH_KEY"],
        "-p",
        str(env.get("GREENVPN_NODE_PORT", "22")),
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        f"{env.get('GREENVPN_NODE_USER', 'root')}@{env['GREENVPN_NODE_HOST']}",
        "wg",
        "show",
        interface,
        "public-key",
    ]
    actual = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=20).stdout.strip()
    old = env.get("GREENVPN_NODE_WG_PUBLIC_KEY", "").strip()
    update_env_value(path, "GREENVPN_NODE_WG_PUBLIC_KEY", actual)
    new = parse_env(path).get("GREENVPN_NODE_WG_PUBLIC_KEY", "").strip()
    print(
        json.dumps(
            {
                "serverId": server_id,
                "oldFingerprint": fingerprint(old),
                "actualFingerprint": fingerprint(actual),
                "newFingerprint": fingerprint(new),
                "matchesActual": new == actual,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
