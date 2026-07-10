import json
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: verify_device_remote_peer.py <device_id> <server_id>", file=sys.stderr)
        return 2

    device_id = int(sys.argv[1])
    server_id = sys.argv[2]

    import app.main as app

    with app.db() as conn:
        device = conn.execute("SELECT * FROM devices WHERE id = ?", (device_id,)).fetchone()
        if device is None:
            raise SystemExit(f"device not found: {device_id}")

    remote = app.load_remote_vpn_node_config(server_id)
    cmd = [
        "ssh",
        "-i",
        str(remote["sshKeyPath"]),
        "-p",
        str(int(remote.get("sshPort") or 22)),
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        f"{remote.get('sshUser') or 'root'}@{remote['sshHost']}",
        "wg",
        "show",
        str(remote["interface"]),
        "dump",
    ]
    dump = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=20).stdout
    public_key = str(device["client_public_key"])
    found = None
    for line in dump.splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) >= 8 and parts[0] == public_key:
            found = {
                "allowedIps": parts[3],
                "latestHandshake": int(parts[4] or 0),
                "rxBytes": int(parts[5] or 0),
                "txBytes": int(parts[6] or 0),
                "persistentKeepalive": parts[7],
            }
            break
    expected_ip = str(device["assigned_ip"]) + "/32"
    print(
        json.dumps(
            {
                "deviceId": device_id,
                "serverId": server_id,
                "assignedIp": str(device["assigned_ip"]),
                "peerExists": found is not None,
                "allowedIpMatches": bool(found and found["allowedIps"] == expected_ip),
                "peer": found,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
