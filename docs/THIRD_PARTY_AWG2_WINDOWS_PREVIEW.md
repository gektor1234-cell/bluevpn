# Third-party notice: AmneziaWG Windows preview

Green VPN Windows transport preview packages the official AmneziaWG Windows client runtime 2.0.0 from:

- Source: https://github.com/amnezia-vpn/amneziawg-windows-client
- Release: https://github.com/amnezia-vpn/amneziawg-windows-client/releases/tag/2.0.0
- License: MIT
- Official amd64 MSI SHA-256: `8A6B4EB62A0BB8663EE50BA4253F5221DA87F5B750640DDCF42F414DBEF79933`

Pinned packaged files:

- `amneziawg.exe`: `5B00905ED02619FE149CEAFC898E79993D4455A0CDFA92072B3BB9AEE7B2D537`
- `awg.exe`: `26AC0BE14A8353EACF2F933736F6F7912F89EC7C59C4190CC990492934C74537`
- `wintun.dll`: `E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE`

The MSI and AmneziaWG executables have a valid Authenticode signature from Privacy Technologies OU. `wintun.dll` has a valid WireGuard LLC signature. The runtime is included only in the isolated preview package and is not added to the stable installer.

The complete upstream MIT notice is packaged as `AMNEZIAWG_WINDOWS_CLIENT_MIT.txt` and must remain included in every redistributed package.
