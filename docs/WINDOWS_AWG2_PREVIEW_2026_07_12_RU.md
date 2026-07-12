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

## Physical evidence

- The protected UAC migration completed: the service runs from `%ProgramFiles%`, the legacy `%LOCALAPPDATA%` tree is absent, and no standard-user write ACL remains on privileged binaries or ProgramData state.
- The competitor guard returned HTTP `409` and did not create a preview tunnel service.
- The first full-tunnel diagnostic correctly rejected endpoint-route recursion. The `/32` physical host-route fix is now parser-checked and release-gated.
- A second diagnostic found a server provisioning collision: Android and Windows peers both had `10.202.0.2/32`. Windows could handshake but had no effective live `AllowedIPs` and therefore no return traffic.
- `set_amneziawg2_canary_peer_address.sh` moved only the Windows peer to `10.202.0.3/32`, synchronized only `awgcanary0`, retained a root-only rollback copy and proved the stable `wg0` config hash and active state unchanged.
- Final physical AWG2 full-tunnel smoke passed on this Windows host:
  - config SHA-256 `AF255FD87B23066F49C881EA0882ADF21ED7F55770AF4FB659773B5125DD497D`;
  - fresh handshake, gateway `10.202.0.1` reachable, bidirectional traffic observed;
  - endpoint route remained on physical Ethernet;
  - canary egress was exactly `5.129.216.42`;
  - production API, both paid-beta control planes and YouTube returned HTTP `200`;
  - `AmneziaWGTunnel$device20_full` and original egress `5.129.237.163` were restored.
- Authoritative report: `C:\Users\gekto\GreenVPN_Checkpoints\windows_awg2_preview_full_pass_20260712.json`.
- The independent Windows Hysteria2/HEV full-device smoke also passed, including watchdog fail-safe cleanup; its evidence is recorded in `HYSTERIA2_CLIENT_ENGINE_LICENSE_AND_DESIGN_2026_07_12.md`.
- Flutter analyze/test and Windows build passed. Release gate: `0` warnings, `0` errors.

Current rebuilt artifact:

- `C:\BlueVPN_Builds\windows_transport_preview_20260711\GreenVPN_Windows_Transport_Preview_0.3.0-preview1.zip`
- size `26,315,389` bytes;
- SHA-256 `2B8A4D0EB2DD78A57CB979012A5881ABB0F2A4D6A18E09D8E858053DF1B9D6A2`;
- manifest: `32` files, `0` mismatches;
- packaged task SHA-256 `48A6E09DBD07C955CB255BB44C0B6FBA6373775965795490B69D5BBEAA8EDE93`;
- packaged Hysteria2 watchdog SHA-256 `A3D96F78EF103DADD4F7756737E060F97A9E4ED1B76812CF7481C2B793D844EA`.

## Rollback

Run `uninstall_windows_transport_preview.ps1` as Administrator. It removes only the preview app, service, two preview tunnel services and `%ProgramData%\BlueVPNTransportPreview`. The stable/beta apps and `device20_full` are outside the allowlist.
