# Green VPN Release State

Updated: 2026-07-17.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.121-admin.1` |
| Fallback API | RUVDS Moscow, backend `0.9.121-admin.1` |
| Android | `0.3.4+2026071701`, package `pro.greenvpn.app`, mandatory |
| Android SHA-256 | `F97D26A4B62E7704517C1EF0BAE394D963151BFB09297872AED67A77B3879CE7` |
| Windows | `0.3.5+1707`, mandatory, unsigned |
| Windows SHA-256 | `70450F03F0B1DFE2DFDB5D5D1BBF017A44B3AAFD5752C684422A049C62344F3B` |
| Ads/session timer | disabled |

Android 0.3.4 is published on Timeweb and RUVDS Moscow. Both stable manifests
have `required=true` and `fileReady=true`; the previous APK is retained in the
root-only deployment backups listed under Rollback.

## Published Admin Console

| Component | Version/state |
| --- | --- |
| URL | `https://admin.greenvpn.pro/`, Basic Auth plus staff session/RBAC |
| Production backend | `0.9.121-admin.1` on Timeweb and RUVDS Moscow |
| Backend SHA-256 | `CF5AFB259E8D80059409A01F663F6E818E15E5494EE94AF8C6049D36090F214B` |
| Static index SHA-256 | `1CD3EAA8A027C13400417DD1E96CECA3C61553D806F7EEBD5EF75168EC59FCCB` |
| Static JavaScript SHA-256 | `9A87CAA3EF2F5CAD1ADB9FC22E925E522D411FE0FC90EE715558BBEEAEB711F9` |
| Static CSS SHA-256 | `680AF9D1F48F8A042A0C592A987EB9077E8264EFE3C26AA7629ADD8CDB344A82` |

The owner console now has a single operational dashboard, Android/Windows
activity and version metrics, attention queues, global account search,
server-side pagination and filters, audited CSV exports, bulk device/session
actions, and a complete account card with subscription, devices, orders,
support history and access controls. Large lists no longer load a fixed first
page or perform one subscription query per user. New database indexes cover the
main account, device, subscription, billing, support, auth and audit paths.

Production smoke covered both control planes, SQLite quick-check, required
indexes, analytics, platform filtering, pagination and formula-safe CSV. The
static site passed desktop and 390 px mobile rendering checks with no page-wide
horizontal overflow or browser-console errors. The public admin origin remains
`noindex`, frame-denied and protected by Nginx Basic Auth before application
staff authentication.

## Paid Public Candidate

| Component | Version/state |
| --- | --- |
| Primary/fallback backend | `0.9.120-public.1` |
| Android | `0.3.4+2026071701`, package `pro.greenvpn.app.beta`, mandatory |
| Android SHA-256 | `9F1357E3CB02196CDC8A351A2D6F995A27BF75ACC0017275465E6DD6254E0675` |
| Windows | `0.3.5-paid-beta.1707`, optional, unsigned |
| Windows SHA-256 | `D5396C4A54ECBFE69750759AF0090E194BC4187397FE54DC5A3A11AF2700955E` |
| Plans | trial 3 days; 249/649/1099 RUB for 30/90/180 days |
| Auto-renew | recurring card binding approved; real save-method and unlink smoke passed on both control planes |
| Billing writer | Timeweb only |
| DB replication | active-active state merge with tombstones |

The candidate is isolated at `/paid-beta` and `/paid-beta-api`. It is not a
closed-first-20 product anymore, but those paths remain the safe staging contour
until public promotion.

## Published Android Product Release

| Component | Version/state |
| --- | --- |
| Customer location model | one row per location; `Авто / Нидерланды / Лондон`; physical routes hidden |
| Latency model | every picker row, including `Авто`, shows `N мс`; missing measurement becomes `0 мс` |
| Source base | `001db00`, label-only London release on the verified Android runtime |
| Android production | `0.3.4+2026071701`, package `pro.greenvpn.app`, release signed |
| Android production SHA-256 | `F97D26A4B62E7704517C1EF0BAE394D963151BFB09297872AED67A77B3879CE7` |
| Android test | `0.3.4+2026071701`, package `pro.greenvpn.app.beta`, release signed |
| Android test SHA-256 | `9F1357E3CB02196CDC8A351A2D6F995A27BF75ACC0017275465E6DD6254E0675` |
| Windows production | `0.3.5+1707`, mandatory, unsigned |
| Windows production SHA-256 | `70450F03F0B1DFE2DFDB5D5D1BBF017A44B3AAFD5752C684422A049C62344F3B` |
| Windows test | `0.3.5-paid-beta.1707`, optional, unsigned |
| Windows test SHA-256 | `D5396C4A54ECBFE69750759AF0090E194BC4187397FE54DC5A3A11AF2700955E` |
| YooKassa | real 249 RUB payment, saved-method verification and unlink smoke complete |
| London | existing VPS `2584554` restored in place; production and paid-beta catalogs publish one logical `Лондон` location |

Production and test APKs are published on both Russian control planes. The
customer-facing stable and paid-beta update manifests force 0.3.4 and all four
public APK aliases are ready.

## Published Windows 0.3.5 Installer Repair

| Component | Version/state |
| --- | --- |
| Production | `0.3.5+1707`, mandatory, unsigned |
| Production installer | `C:\BlueVPN_Builds\green_vpn_windows_0.3.5_public_20260717_01\GreenVPN_Setup_0.3.5.exe` |
| Production SHA-256 | `70450F03F0B1DFE2DFDB5D5D1BBF017A44B3AAFD5752C684422A049C62344F3B` |
| Test | `0.3.5-paid-beta.1707`, optional, unsigned |
| Test installer | `C:\BlueVPN_Builds\green_vpn_windows_0.3.5_paid_beta_20260717_01\GreenVPN_Beta_Setup_0.3.5-paid-beta.1707.exe` |
| Test SHA-256 | `D5396C4A54ECBFE69750759AF0090E194BC4187397FE54DC5A3A11AF2700955E` |

The 0.3.4 IExpress entry point invoked an extracted unsigned PowerShell file
directly with `RemoteSigned`. A browser-applied Internet zone marker therefore
caused Windows to reject the script before the branded installer UI, transcript,
application files or shortcuts existed. This exactly matched the reported
silent no-install behavior and was reproduced locally with `ZoneId=3`.

The package now starts a small native .NET Framework bootstrap. It removes the
Internet zone alternate stream only from the four extracted Green VPN installer
payload files, keeps `RemoteSigned` for PowerShell and never uses an execution
policy bypass. The install script also treats the application EXE, desktop
shortcut and Start menu shortcut as mandatory postconditions and validates both
shortcut targets before reporting success.

The source bootstrap and the exact compiled production/test bootstrap binaries
passed the MOTW smoke: exit code zero, branded UI script started and zero zone
streams remained. The standard release gate passed with zero warnings/errors.
Both Russian nodes were deployed sequentially after dry-run validation. All
four public Windows files are byte-identical to their expected production/test
artifacts, all eight Android/Windows manifest checks pass and the independent
public surface probe is 31/31.

Rollback directories:

- RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T201752Z-ruvds-0.3.5-1707`;
- Timeweb Moscow: `/root/greenvpn-windows-release-backups/20260717T201835Z-timeweb-0.3.5-1707`.

Authenticode remains intentionally unresolved. A privileged end-to-end install
on the owner PC still requires accepting its UAC prompt; the current Codex shell
is not elevated, so this release record does not claim that separate physical
confirmation.

## Published Windows 0.3.4

| Component | Version/state |
| --- | --- |
| Product/build | `0.3.4+1706` |
| Installer | `C:\BlueVPN_Builds\green_vpn_windows_0.3.4_rc_20260717_06\GreenVPN_Setup_0.3.4.exe` |
| SHA-256 | `49C7D098ED7E3980EDE7742ED6AF03EB7F3CEFAFC1EAC6E543C69C890A818E47` |
| Authenticode | not signed; published temporarily by explicit owner decision |
| Public state | production mandatory; test optional; mirrored on both RU nodes |
| Source checkpoint | parity `649214d`; recovery `b4ac12f`; publication commit containing this handoff |

The Windows public client now opens a valid saved session directly, restores
the same window after tray hiding, executes authenticated tray connect and
disconnect commands asynchronously, validates HTTPS update URLs, launches an
installer without a command shell, and uses public Russian product copy. The
server picker exposes only `Auto`, `Netherlands` and `London` with numeric
latency; provider, node and transport details remain hidden. Windows selective
routing is described as services instead of Android applications, and tariff
periods are shown as one, three or six months.

This candidate deliberately does not enable the isolated transport cascade and
does not change server catalogs or anti-blocking deployments. Analyzer, 31
Flutter tests with two intentional skips, 42 backend tests, the Windows C++
build and the release gate pass. A Windows device automatically retired by the
device-limit policy now rotates its local identity once and fetches a fresh
config; administrator-disabled devices remain disabled. The hidden state file
is made writable only for the replacement and is protected again afterwards.

The authenticated local-service path and competing-VPN protection were
rechecked while the owner's Amnezia tunnel was active. The final elevated
network transition then passed from the exact recovered paid-beta contour:
fresh handshake, positive RX/TX before and after the 20-second hold, all three
external probes, DNS resolution, no direct DNS leak and 10/10 network-protection
checks. Cleanup removed the temporary Green VPN tunnel and restored Amnezia,
ordinary Internet access and both production API ingress paths. Evidence is in
`C:\BlueVPN_Builds\green_vpn_windows_0.3.4_rc_20260717_06\windows-network-transition-report.json`.

Production and test installers were published atomically on Timeweb and RUVDS
Moscow after dry-runs. Public downloads are byte-identical across mirrors and
match the hashes above. Eight Android/Windows update manifests, eight HEAD
download checks, the paid-beta static download manifest and the independent
31/31 public-surface probe pass. This does not make the unsigned installer
trusted: SmartScreen/reputation warnings remain expected until Authenticode.

## Verified

- Both RU control planes run production backend `0.9.121-admin.1` and pass health,
  schema and SQLite quick-check.
- Admin/backend validation: 98 backend unit tests, Python and JavaScript syntax,
  unique HTML ids, desktop/mobile UI, live analytics/pagination/CSV and CORS.
- Production and candidate sync timers are active. Latest explicit production
  cycles on both nodes: zero inserts/updates, zero conflicts/errors.
- Public site, legal pages, downloads, manifests and all three API surfaces pass
  the independent 31-target probe.
- Login/bootstrap/config failover, session persistence, Android background and
  custom per-app routing were physically proven.
- Windows side-by-side install, reboot persistence, VPN/DNS transition,
  competing-VPN restoration, uninstall recovery and clean reinstall were proven.
- Android/Flutter/backend/native tests, analyzer, dependency audit, release gate
  and full Git-history secret scan are green.
- Public-product auto-renew UI has passing Flutter tests. Physical Android 9
  QA confirms one Settings entry, a dedicated card/auto-renew page, no cancel
  action in Tariff, and no layout overlap.
- The final Android picker was physically rechecked on Samsung Android 9 in
  production and test: `Авто`, `Нидерланды` and `Лондон` are the only logical
  rows and every row displays numeric latency. Two physical Netherlands nodes
  remain grouped behind one customer location.
- The restored London VPS passed isolated WireGuard data-plane smoke from both
  Russian control planes: handshake, positive RX/TX, matching London egress and
  3/3 production API, Google and YouTube checks. Temporary peers, namespaces,
  firewall rules, forwarding changes and key files were all removed.
- Production Android connected to the London location, exposed a `CONNECTED` and
  `VALIDATED` VPN network and played a YouTube video to completion. Removing
  the Green VPN activity stack left the foreground service and tunnel running;
  reopening restored the live state. Test Android independently connected to
  the same location through the paid-beta catalog. Both packages were returned
  to `Автовыбор` with no active VPN.
- Stable catalog exposes only stable transports. Five anti-blocking previews are
  hidden and isolated to NL2.
- Production and test 0.3.3 were installed side-by-side on Samsung Android 9.
  Both completed a real VPN connect with an Android `CONNECTED` and `VALIDATED`
  network, loaded YouTube, stayed connected after their task was swiped from
  recent apps, restored the live state when reopened, and disconnected cleanly.
- The exact production APK downloaded from `https://greenvpn.pro/downloads/GreenVPN_Android.apk`
  was clean-installed after removing the old package on Samsung Android 9 and
  Android 16. Login, delayed idle, every primary screen, server selection,
  connection, API/YouTube traffic, background, recent-task removal, reopen and
  disconnect completed with empty crash buffers. Primary and fallback APKs are
  byte-identical and match the production hash above.
- The Android 16 crash was a native-process collision between the standard
  tunnel Go runtime and the AWG2 Go runtime. Version diagnostics were removed,
  AWG2 now runs in the isolated `:greenvpn_awg2` process, and all standard
  tunnel owners share one runtime instance. Automatic AWG2-to-Hysteria2
  failover was physically proven after an injected engine stop.
- Release optimization keeps the reflected optional tunnel API intact, while
  `wireguard_udp` is always routed through the standard backend and
  `amneziawg` alone uses the optional backend.
- Android 0.3.4 is a label-only release: production was updated in place on
  physical Android 9 and Android 16, retained the authenticated session, stayed
  alive after launch and interaction, and showed exactly `Авто`, `Нидерланды`
  and `Лондон` with numeric latency. Crash buffers remained empty. The signed
  test APK launched on both devices without a crash. All four manifests and
  downloads passed, followed by the independent 31/31 public-surface probe.

## Remaining Launch Gates

1. Obtain an Authenticode code-signing certificate and build a higher-version
   signed successor to the temporary public 0.3.5 release.
2. Reverify the signed hash, then replace Windows atomically on main and test
   with rollback backups and public probes.

Android and the server-side location pool are published. No confirmed Android,
London or Russian control-plane defect remains.

## Rollback

- Admin backend 0.9.121 deployment backups:
  - Timeweb: `/root/greenvpn-admin-release-backups/20260717T181919Z-timeweb-0.9.121-admin.1`;
  - RUVDS Moscow: `/root/greenvpn-admin-release-backups/20260717T181612Z-ruvds-0.9.121-admin.1`.
  Each contains the previous `main.py`, production environment and a verified
  online SQLite backup. Restore code/environment one node at a time and restart
  `bluevpn-backend.service`; use the DB image only for a separately confirmed
  database rollback.
- Admin static backup on Timeweb:
  `/root/greenvpn-admin-static-backups/20260717T182028Z-admin-console`.
  Restore its three files to `/var/www/greenvpn-admin` with `www-data:www-data`
  ownership and mode `0644`, then run `nginx -t`.

- Android 0.3.4 deployment backups:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260717T090025Z-timeweb-0.3.4-2026071701`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260717T085953Z-ruvds-0.3.4-2026071701`.
  They retain the previous APK aliases and environment files with root-only
  permissions.
- Backend 0.9.120 production deployment backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260717T114255Z-timeweb-0.9.120-public.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260717T114344Z-ruvds-0.9.120-public.1`.
- Backend 0.9.120 paid-candidate deployment backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260717T114249Z-paid-beta-backend-windows-device-recovery-20260717-r24`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260717T114333Z-paid-beta-backend-windows-device-recovery-20260717-r24`.
- Previous backend 0.9.119 production backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260716T175852Z-timeweb-0.9.119-public.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260716T175914Z-ruvds-0.9.119-public.1`.
- Previous backend 0.9.119 paid-candidate backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260716T175858Z-paid-beta-backend-fallback-peer-20260716-r23`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260716T175919Z-paid-beta-backend-fallback-peer-20260716-r23`.
- Windows 0.3.4 pre-release rollback backups:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260717T122847Z-timeweb-0.3.4-1706`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T122919Z-ruvds-0.3.4-1706`.
- Windows static-manifest correction backups:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260717T123644Z-timeweb-0.3.4-1706`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T123748Z-ruvds-0.3.4-1706`.
- London preserved-state recovery backup:
  `/root/greenvpn-london-recovery-backups/20260716T100956Z`.
- Production catalog DB backups before London publication:
  - Timeweb: `/root/greenvpn-london-catalog-backups/20260716T103621Z-timeweb`;
  - RUVDS Moscow: `/root/greenvpn-london-catalog-backups/20260716T103621Z-ruvds-moscow`.
- Paid-beta catalog DB backups before London publication:
  - Timeweb: `/root/greenvpn-london-catalog-backups/20260716T104858Z-timeweb-paid-beta`;
  - RUVDS Moscow: `/root/greenvpn-london-catalog-backups/20260716T104858Z-ruvds-moscow-paid-beta`.
- Temporarily public unsigned Windows 0.3.4 production installer:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.4_rc_20260717_06\GreenVPN_Setup_0.3.4.exe`,
  SHA-256 `49C7D098ED7E3980EDE7742ED6AF03EB7F3CEFAFC1EAC6E543C69C890A818E47`.
  The pre-release backups above contain the previously published Windows
  installer and env state.
- Windows final-smoke source commit:
  `b4ac12f837a896637687d3d860ce56e2e5ba8d81`.
- Current final-candidate tag:
  `greenvpn-final-candidate-autorenew-20260716`.
- Final-candidate tag: `greenvpn-final-candidate-20260716`.
- Verified encrypted final-candidate checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_final_candidate_20260716_010736`.
- Final-candidate server/local SHA-256:
  `B376020D3E28663C798CE65ED337D439A4E00CA7DFBB7B429AE722EA15197FEE` /
  `2D77820204CAE220610ABE7C8027AB14B3BA3D1479C2239E99125D6329AC9699`.
- Technical-final handoff tag: `greenvpn-technical-final-20260713`.
- Verified encrypted technical-final checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_technical_final_green_ci_20260713_185901`.
- Technical-final server/local SHA-256:
  `86847313267BFCD2F06E11CF064AA5D8F2A77C403AB9C8997569577DCD139C68` /
  `FA0B97F32F1323E092B9C5E042C46E48FC1FE6167534CEC5EC2DDB4363B3A39F`.
- Stable Git tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Multiprotocol checkpoint tag:
  `greenvpn-multiprotocol-preview-complete-20260713`.
- Verified encrypted full-project checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_pre_cleanup_20260713_124114`.
- KZ retirement recovery image:
  `2d3d1ae6-899f-48f0-ba1e-985eb5e0344d`.
- Every server deploy retains a root-only online DB/app rollback directory named
  in `CURRENT_HANDOFF.md` or the operation report.

## Non-Blocking Maintenance

- Migrate FastAPI startup hooks from deprecated `on_event` to lifespan during a
  later backend release, with no reason to alter the current r22 runtime now.
- Third-party Gradle Groovy-assignment warnings originate in Pub cache packages;
  resolve by dependency upgrades, never by editing generated cache files.
