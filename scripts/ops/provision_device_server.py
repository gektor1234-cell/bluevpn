import hashlib
import json
import sys


def fingerprint(value: str) -> str:
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()[:12] if value else ""


def row_value(row, key: str, default=None):
    try:
        return row[key]
    except Exception:
        return default


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: provision_device_server.py <device_id> <server_id>", file=sys.stderr)
        return 2

    device_id = int(sys.argv[1])
    server_id = sys.argv[2]

    import app.main as app

    with app.db() as conn:
        device = conn.execute("SELECT * FROM devices WHERE id = ?", (device_id,)).fetchone()
        if device is None:
            raise SystemExit(f"device not found: {device_id}")
        user = conn.execute("SELECT * FROM users WHERE id = ?", (int(device["user_id"]),)).fetchone()
        previous = conn.execute(
            "SELECT * FROM client_endpoint_assignments WHERE user_id = ? AND device_uid = ?",
            (int(device["user_id"]), str(device["device_uid"])),
        ).fetchone()

    device_uid = str(device["device_uid"])
    app_version = str(device["app_version"] or "")
    catalog = app.build_server_catalog(release_channel="preview", app_version=app_version)
    lookup = app.public_server_lookup(catalog)
    selected = lookup.get(server_id)
    if not selected:
        raise SystemExit(f"server not visible for device/app version: {server_id}")

    updated = app.ensure_device_keys_and_ip(device_uid)
    provision = app.provision_wireguard_peer_for_selected_server(
        selected,
        device_uid=device_uid,
        public_key=str(updated["client_public_key"]),
        psk=str(updated["preshared_key"]),
        ip=str(updated["assigned_ip"]),
        previous_server_id=row_value(previous, "server_id", None),
    )

    with app.db() as conn:
        assignment = app.upsert_sticky_endpoint_assignment(
            conn,
            int(updated["user_id"]),
            device_uid,
            server_id,
            "wireguard_udp",
            "support",
            "support_london_public_key_repaired_device53",
        )
        conn.execute(
            "UPDATE devices SET last_config_at = ?, updated_at = ? WHERE device_uid = ?",
            (app.utc_now_iso(), app.utc_now_iso(), device_uid),
        )
        conn.commit()

    remote_config = app.load_remote_vpn_node_config(server_id)
    peer_status = app.remote_vpn_node_peer_status(remote_config, str(updated["client_public_key"]))

    print(
        json.dumps(
            {
                "deviceId": device_id,
                "userId": int(updated["user_id"]),
                "userEmail": str(user["email"] if user else ""),
                "deviceUid": device_uid,
                "assignedIp": str(updated["assigned_ip"]),
                "selectedServerId": server_id,
                "previousServerId": row_value(previous, "server_id", ""),
                "serverPublicKeyFingerprint": fingerprint(str(provision.get("serverPublicKey") or "")),
                "profile": provision.get("profile"),
                "endpointHost": provision.get("endpointHost"),
                "endpointPort": provision.get("endpointPort"),
                "stickyAssignment": assignment,
                "remotePeerExists": bool(peer_status.get("exists")),
                "remotePeerCount": peer_status.get("peerCount"),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
