# Green VPN Hysteria2 client engine decision

Date: 2026-07-12.

## Decision

The preview client uses the official Hysteria `app/v2.9.3` binary only as a
local SOCKS5 client. It does not enable Hysteria's built-in TUN mode.
Full-device packet forwarding is provided by `hev-socks5-tunnel` `2.14.4`.

This split keeps the client engine redistributable under permissive terms:

- Hysteria app: MIT, commit `2d973f9513ef661d1922d6d14acb37945caef47d` from release `app/v2.9.3`.
- HEV Socks5 Tunnel: MIT, commit `4d6c334dbfb68a79d1970c2744e62d09f71df12f`.
- HEV Socks5 Core: MIT, commit `4be2e621813ba0315cfacd995bf501bde91d6996`.
- HEV Task System: MIT, commit `8d83bbbf79557138726c8ee5a5fae99cbb978d61`.
- HEV lwIP fork: BSD-style, commit `07dbf162c718cc78ddedb9e67c6ebd17065eaf13`.
- HEV YAML: MIT, commit `efa36117a8646d26d12b58e05bac472d7854a70d`.
- Wintun prebuilt binary: its upstream binary license permits distribution
  alongside software that uses only the permitted Wintun API.

The exact notices are stored in `docs/licenses` and must be packaged unchanged.

## Rejected alternatives

Hysteria's built-in TUN mode links `github.com/apernet/sing-tun` at commit
`299f04629986`, whose repository is GPL-3.0. Shipping that TUN-enabled binary
would require a separate GPL compliance path and corresponding source offer.
The preview therefore does not use or package that mode.

`xjasonlyu/tun2socks` `v2.6.0` is MIT and remains a viable Windows fallback,
but it does not provide the same direct Android `VpnService` file-descriptor
API in this integration. `outline-go-tun2socks` is Apache-2.0 but is primarily
coupled to Outline/Shadowsocks APIs. HEV supplies one small engine for both
Windows and Android, including TCP and UDP forwarding.

## Pinned Windows artifacts

- Hysteria `hysteria-windows-amd64.exe`:
  `BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F`.
- HEV upstream archive `hev-socks5-tunnel-win64.zip`:
  `D9C49AC7CE5658BF3BAC2798F98D73B86998C7E684A2E68E13D252929CF79359`.
- HEV executable:
  `46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E`.
- HEV MSYS runtime:
  `6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18`.
- Wintun DLL:
  `E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE`.

The Hysteria and HEV executables are not Authenticode-signed. They are allowed
only in the isolated paid-beta transport preview and are pinned by SHA-256.
They must not be promoted to the stable installer until the product signing
gate and physical compatibility tests pass.

## Runtime contract

1. The Russian control plane returns a root-owned Hysteria base profile only
   to a client advertising the `hysteria2` capability.
2. The client stores that profile with owner/SYSTEM/Administrators ACLs.
3. The privileged preview task validates an IPv4-literal endpoint, trusted TLS,
   Salamander obfuscation and absence of local listener sections.
4. The task creates a private runtime profile with a loopback-only SOCKS5
   listener, pins the remote endpoint through the pre-tunnel physical gateway,
   then starts Hysteria and HEV from protected `%ProgramFiles%`.
5. HEV owns a distinct preview adapter and split-default routes. State and PID
   files are SYSTEM/Administrators only. A watchdog removes routes and stops the
   other engine if either child exits.
6. Disconnect and every failed connect remove only allowlisted preview routes,
   processes, adapter state and runtime files. Stable WireGuard services and
   the user's existing VPN are outside the allowlist.

## Android contract

Android will use the same HEV engine through its `tun_fd` JNI API. Hysteria's
`quic.sockopts.fdControlUnixSocket` is used with `VpnService.protect()` so the
QUIC socket stays outside the VPN and cannot recurse into its own TUN. Android
packaging and physical-device proof remain a separate rollout gate.
