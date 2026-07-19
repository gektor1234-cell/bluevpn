# Windows process router provenance

Green VPN uses these files only for the Windows application-only routing mode.
The ordinary full-tunnel mode does not load them.

## ProxyBridge

- Project: https://github.com/InterceptSuite/ProxyBridge
- Version: v3.2.0
- Commit: `7dd955f8e726cd113146984858ba11bf7202bff9`
- License: MIT; see `PROXYBRIDGE_LICENSE.txt`.
- Build: x64 release from the pinned source with MSVC and the upstream .NET CLI
  project. The GUI is not included.

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
| `ProxyBridge_CLI.exe` | `71AE1A872B49F795BB9E341FF910C5B303AFCE0BAB1E54CFC5436032EB7E08C9` |
| `ProxyBridgeCore.dll` | `736B75A06AD748254D711446E0D4239189A991C7AABCE739EF7DD7B9CA7EBF7E` |
| `WinDivert.dll` | `C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2` |
| `WinDivert64.sys` | `8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2` |

Do not replace these binaries without reviewing the pinned source, rebuilding,
updating all four expected hashes, and rerunning the Windows physical smoke.
