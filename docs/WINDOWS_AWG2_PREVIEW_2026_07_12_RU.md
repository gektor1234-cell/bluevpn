# Green VPN Windows AWG2 transport preview

Дата: 2026-07-12.

## Изоляция

- Product: `Green VPN Transport Preview`.
- Target app path after the pending protected reinstall: `%ProgramFiles%\Green VPN Transport Preview\greenvpn_transport_preview.exe`.
- Service binary and privileged task are protected from modification by standard users; the legacy `%LOCALAPPDATA%` preview path is removed during migration.
- Privileged service: `GreenVPNTransportPreviewService`, automatic, loopback `127.0.0.1:48739`.
- Tunnel: `GreenVPNTransportPreview`; AWG service: `AmneziaWGTunnel$GreenVPNTransportPreview`.
- State: `%ProgramData%\BlueVPNTransportPreview`; отдельные user state и service token.
- Stable Green VPN, Green VPN Beta, public downloads and server catalog are not replaced by this package.

## Runtime and license

- Official upstream: `amnezia-vpn/amneziawg-windows-client` release `2.0.0`, commit `54fa022e2c40ed6d51f757e0871158372fb14977`.
- License: MIT; full notice is bundled and stored in `docs/licenses/AMNEZIAWG_WINDOWS_CLIENT_MIT.txt`.
- The official `amneziawg.exe`, `awg.exe` and `wintun.dll` hashes and Authenticode signatures are pinned by `build_windows_awg2_preview.ps1`.
- Own Flutter and service executables are unsigned, therefore this remains an isolated preview and must not be published as stable.

## Safety model

- Client capability is disabled by default and enabled only with `GREENVPN_AWG2_PREVIEW_ENABLED=true`.
- Mutating local API calls require the per-install service token and POST.
- A competing VPN returns HTTP `409`; the preview does not silently disconnect another product.
- Only the two exact preview tunnel service names are stopped or removed.
- Full-tunnel mode pins the remote IPv4 endpoint with a temporary `/32` route through the pre-tunnel physical gateway.
- The route-state file is SYSTEM/Administrators only. Cleanup validates the current managed endpoint and unique route metric `42731` before deleting the preview route.
- The physical smoke uses `try/finally` to disconnect the preview and restore the previously running `AmneziaWGTunnel$device20_full`.

## Evidence so far

- Installer completed with UAC; preview service reached `Running`, app started, loopback bound only to `127.0.0.1:48739`.
- Competitor guard returned HTTP `409` and did not create a preview tunnel service.
- Physical narrow-route diagnostic passed with the original canary profile:
  - interface present;
  - fresh AWG2 handshake;
  - `659` bytes sent and `124` bytes received during the first run;
  - endpoint route remained on physical Ethernet;
  - original egress `5.129.237.163` was restored.
- The first full-tunnel diagnostic exposed endpoint recursion: the route to `5.129.216.42` selected the preview adapter. This was rejected rather than reported as success.
- The host-route fix is implemented, parser-checked, release-gated and rebuilt. Final full-tunnel physical proof still requires one UAC-confirmed smoke.
- Security review found that the first installed preview service ran from user-writable `%LOCALAPPDATA%` as `LocalSystem`. The rebuilt installer removes that legacy path and installs the service under protected `%ProgramFiles%` ACLs. The currently installed legacy service must not be used and remains unproven until the UAC-confirmed migration completes.
- Flutter analyze/test and Windows build passed. Release gate: `0` warnings, `0` errors.

Current rebuilt artifact:

- `C:\BlueVPN_Builds\windows_transport_preview_20260711\GreenVPN_Windows_Transport_Preview_0.3.0-preview1.zip`
- size `16,316,388` bytes;
- SHA-256 `FB015C8BDE23FB7B03C2D361DC7DF92B63D9A97D7FDBD57578B47325FDF5C689`;
- manifest: `22` files, `0` mismatches;
- packaged task SHA-256 `83AB2923200A9484198BDBEB842A8513D4CD644519982ACEC5BF7CCF245A72BF`.

## Rollback

Run `uninstall_windows_transport_preview.ps1` as Administrator. It removes only the preview app, service, two preview tunnel services and `%ProgramData%\BlueVPNTransportPreview`. The stable/beta apps and `device20_full` are outside the allowlist.
