# Windows process router provenance

Green VPN uses these files only for the Windows application-only routing mode.
The ordinary full-tunnel mode does not load them.

## ProxyBridge

- Project: https://github.com/InterceptSuite/ProxyBridge
- Base version: v4.0.0
- Base commit: `22e53445e44481fad0f63c2a088aa91c0deda3af`
- License: MIT; see `PROXYBRIDGE_LICENSE.txt`.
- Fork source: `source\`; the GUI is not included.
- Green VPN changes: full flow-tuple PID attribution, exact SOCKS5 framing,
  long executable paths, IPv4/IPv6 process routing, immutable active config,
  orderly worker shutdown, and fail-closed selected traffic when attribution
  or the exact proxy route is unavailable. No global `svchost.exe` DNS rule is
  installed.
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
| `ProxyBridge_CLI.exe` | `806B3F6326F3D90C3029D179F458F6BF41970D21107A6729A44D7693C580523B` |
| `ProxyBridgeCore.dll` | `30E3D20DFD44A06CE52F5F3566863A54D5832C4490FB210704B976D7ED5A2D2F` |
| `WinDivert.dll` | `C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2` |
| `WinDivert64.sys` | `8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2` |

Do not replace these binaries without reviewing the pinned source, rebuilding,
updating all four expected hashes, and rerunning the Windows physical smoke.
