# Green VPN Windows VLESS REALITY/XHTTP Preview

Date: 2026-07-12.

## Scope and isolation

- This is an internal transport canary, not a public release.
- Production, paid-beta downloads, auth, billing, databases and the public server catalog were not changed.
- Friendly Linnet `5.129.237.163` was not modified.
- The canary runs only on NL2 `5.129.216.42` as `greenvpn-vless-reality-canary.service` on TCP/443. Existing WireGuard remains on UDP/443.
- The root-only server config is `/etc/greenvpn-transport/vless-reality-xhttp-canary.json`.

## Pinned engine and license

- Xray-core `v26.7.11`, commit `50231ea`, MPL-2.0.
- Official Linux archive SHA-256: `AA11C3685C71DA0FFC71E511DB50404609E7E963BB914B048F59A6A00AF8930E`.
- Official Linux binary SHA-256: `5200ED9B358CF380B2D9F1FE28C7E56220C0159ADCD86A64592246D8257A043C`.
- Official Windows binary SHA-256: `4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB`.
- The preview package contains the exact MPL-2.0 license and source notice pointing to `https://github.com/XTLS/Xray-core/tree/v26.7.11`.

## Server result

- Bootstrap is guarded to the exact NL2 host and preserves hashes/service activity for WireGuard, AWG2 and Hysteria2.
- REALITY key material, client ID, short ID and XHTTP path are root-only and never printed by scripts or readiness output.
- `www.microsoft.com` was rejected because its Akamai edge reset XHTTP POST. Apple worked but Xray warned against using Apple as a REALITY target. The tested target is `www.amazon.com:443`.
- Readiness reports active service, TCP/443 listener and route candidate `nl2-vless-reality-xhttp-canary` with no blockers.
- Bootstrap now performs a real local SOCKS data-plane smoke and requires NL2 egress before succeeding.
- Invalid-client fallback presents ordinary target HTTPS. A direct owner-network probe completed TLS and received HTTP `503`; this is accepted as a valid camouflage response, not as application health.

## Windows design

- Build flag: `GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=true`. It is false by default.
- Xray exposes only loopback SOCKS `127.0.0.1:1981`; HEV `2.14.4` creates `GreenVPNVlessPreview`.
- Xray and HEV binaries are hash-pinned before every start.
- Runtime config, PID and route state files are hidden and ACL-limited to SYSTEM and Administrators.
- The server endpoint receives a physical `/32` bypass route. Xray is additionally bound to the physical adapter with `sockopt.interface` and `sendThrough`.
- HEV uses UDP-over-TCP. Client routing drops private/link-local/multicast traffic and UDP/443 locally, forcing QUIC clients to fall back to TCP and preventing background UDP from occupying XHTTP sessions.
- Full tunnel uses four split routes with metric `42733`. The watchdog fail-closes if Xray or HEV exits and removes both processes, routes, endpoint bypass and plaintext runtime configs.
- The protected preview service refuses connection while another VPN is active.

## Physical proof

Windows artifact:

- Path: `C:\BlueVPN_Builds\windows_transport_preview_20260712_vless\GreenVPN_Windows_Transport_Preview_0.3.0-preview2.zip`.
- Size: `41,606,258` bytes.
- SHA-256: `F6615248AE756477DFAE40153B0D819DFBAC17AC47C734B475D7B7DD2E944BCA`.
- Manifest: 39 files, including Xray, HEV, watchdog, MPL license and source notice.

SOCKS report:

- Path: `C:\Users\gekto\GreenVPN_Checkpoints\windows_vless_reality_socks_physical_20260712.json`.
- SHA-256: `2B2318D715F5FD8CCECCB240CB221E42212570D3EBBAAA2DC8051055549D566E`.

Full-tunnel report:

- Path: `C:\Users\gekto\GreenVPN_Checkpoints\windows_vless_reality_preview_physical_20260712.json`.
- SHA-256: `7B83B1C75EC15B7675688207D06E478B960AE0C0981C995E4763FD05D7B9037A`.
- Direct REALITY through the owner ISP: NL2 egress `5.129.216.42`.
- Full TUN: NL2 egress, DNS and TCP passed.
- Production API, Timeweb paid-beta API, RUVDS paid-beta API and YouTube returned HTTP `200`.
- Exact Xray/HEV paths, adapter, endpoint isolation and four route entries passed.
- Killing HEV triggered watchdog cleanup successfully.
- Stable `AmneziaWGTunnel$device20_full` was restored, and egress returned exactly to `5.129.237.163`.

## Rollback

Server rollback is restricted to the same NL2 tuple:

```bash
/root/greenvpn-vless-stage/remove_transport_canary_service.sh \
  --protocol vless_reality \
  --service-name greenvpn-vless-reality-canary \
  --config-file /etc/greenvpn-transport/vless-reality-xhttp-canary.json \
  --expected-public-ip 5.129.216.42 \
  --approved-existing-host 5.129.216.42 \
  --apply
```

Windows rollback uses `uninstall_windows_transport_preview.ps1`. It is allowlisted to the preview service, preview app directory and `%ProgramData%\BlueVPNTransportPreview`; it does not remove stable or beta Green VPN installations.

## Remaining before rollout

- Publish the profile only through the isolated paid-beta control planes with explicit `vless_reality` capability negotiation.
- Android preview engine is built and physically proven; see `docs/ANDROID_VLESS_REALITY_PREVIEW_2026_07_12_RU.md`.
- Add health-aware fallback and monitoring before any public cohort receives this route.
