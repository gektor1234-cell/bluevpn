# Windows process router provenance

Green VPN uses these files only for the Windows application-only routing mode.
The ordinary full-tunnel mode does not load them.

## ProxyBridge

- Project: https://github.com/InterceptSuite/ProxyBridge
- Base version: v4.0.0
- Base commit: `22e53445e44481fad0f63c2a088aa91c0deda3af`
- License: MIT; see `PROXYBRIDGE_LICENSE.txt`.
- Fork source: `source\`; the GUI is not included.
- Green VPN changes: socket PID attribution with normalized IPv4-mapped/IPv6
  tuples and direction-less SOCKET-layer CONNECT/BIND capture, selected-process
  BIND ownership keyed by the assigned local port, remote-tuple-bound
  ambiguity-safe socket fallback, and a bounded selected-rule CONNECT cache.
  An unresolved first packet is removed from the capture thread and held in a
  bounded FIFO while WinDivert delivers the causally later socket/flow metadata;
  a dedicated worker then resolves and redirects it or drops it fail-closed.
  Direct and unselected processes never enter a selected-only attribution
  fallback. The fork also provides
  verified local relay startup, privacy-safe durable attribution and relay
  diagnostics, exact SOCKS5 framing, long executable paths, immutable active
  config, orderly worker shutdown, and fail-closed selected traffic when
  attribution or the exact proxy route is unavailable. No global `svchost.exe`
  DNS rule is installed.
- Build: x64 release with MSVC using `source\build.ps1`.

## WinDivert

- Project: https://github.com/basil00/WinDivert
- Archive: WinDivert-2.2.2-A.zip
- Archive SHA-256:
  `63CB41763BB4B20F600B6DE04E991A9C2BE73279E317D4D82F237B150C5F3F15`
- License: see `WINDIVERT_LICENSE.txt`.
- `WinDivert64.sys` retains the valid upstream Authenticode signature. The
  installer verifies that signature before packaging a release.

## Packaged file hashes

| File | SHA-256 |
| --- | --- |
| `ProxyBridge_CLI.exe` | `6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569` |
| `ProxyBridgeCore.dll` | `335E294B03A62106455B9C0AD22B043A0CA7651F82C9EC4C21EF87A232794A85` |
| `WinDivert.dll` | `C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2` |
| `WinDivert64.sys` | `8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2` |

Do not replace these binaries without reviewing the pinned source, rebuilding,
updating all four expected hashes, and rerunning the Windows physical smoke.
