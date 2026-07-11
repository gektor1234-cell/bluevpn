# AWG2 preview dependency

The Android transport preview uses the official AmneziaWG Android 2.0.1 tunnel API.

- Source: https://github.com/amnezia-vpn/amneziawg-android
- Tag: `2.0.1`
- Commit: `fb64e74ba5a0a54e9185b8776bcb8088afb772c9`
- Official APK SHA256: `313A42014BD54C487E4592CEB64F023C588817F8C4EAEB465163F25C1E70AD33`
- Android tunnel Java API license: Apache-2.0
- `amneziawg-go` userspace engine license: MIT

`scripts/windows/prepare_android_awg2_preview.ps1` materializes a generated local Android
library. It packages only the userspace engine, renamed to `libawg2-go.so` so it can coexist
with the standard WireGuard engine; the GPL-2.0 command-line helpers `libwg.so` and
`libwg-quick.so` are deliberately excluded. The generated directory is ignored by Git and is
included only when `GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED=true`.

This dependency must remain disabled in stable builds until real-device tests and the staged
release gate pass.
