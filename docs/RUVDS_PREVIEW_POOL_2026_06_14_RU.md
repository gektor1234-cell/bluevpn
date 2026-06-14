# RUVDS preview pool - 2026-06-14

## Status

- The public stable catalog is unchanged.
- Stable clients see only proven public nodes.
- Preview/adgate clients additionally see allowlisted test nodes from `GREENVPN_PREVIEW_SERVER_IDS`.
- Origin preview allowlist includes `ruvds-2584554-ld8`.
- RUVDS London is preview/test only until the owner explicitly decides to promote it to stable.

## Node

- Backend server id: `ruvds-2584554-ld8`.
- Provider server id: `2584554`.
- Endpoint: `88.218.250.86:443`.
- Location: London / United Kingdom.
- Profile: `remote_ssh_wg0`.
- Interface: `wg0`.

## Verified checks

- Backend version during check: `0.9.103`.
- `remote-provisioning-check`: `ok=true`, `sshReachable=true`, `wireGuardReady=true`.
- `remote-peer-smoke`: `ok=true`, peer is created and removed.
- `client-config-smoke`: `ok=true`, temporary client config is valid and smoke peer is removed.
- Stable catalog: `intelligent_smew`, `tw-7879598-nl1`; RUVDS is not visible.
- Preview catalog: `intelligent_smew`, `tw-7879598-nl1`, `ruvds-2584554-ld8`; RUVDS is visible.

## Android preview

- Preview APK URL: `https://greenvpn.pro/downloads/GreenVPN_Android_preview_latest.apk`.
- Preview page: `https://greenvpn.pro/release-preview-20260517-private/`.

## Important

- Main site and no-ads stable builds were not changed.
- Secrets, admin token, SSH keys, WireGuard private keys, and provider API keys were not added to the repo.
- To move RUVDS to stable later, remove the preview-only assumption, explicitly publish/promote the node, and run real Android and Windows smoke tests first.
