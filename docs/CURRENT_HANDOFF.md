# Green VPN Current Handoff

Последнее обновление: 2026-05-09

Этот файл нужен, чтобы новый Codex мог продолжить разработку без чтения старого длинного диалога.

Контекстная экономия: в новой сессии сначала читать `C:\Users\gekto\projects\bluevpn\docs\CODEX_CONTEXT_COMPACT_RU.md`. Этот подробный handoff открывать только точечно, если compact context не хватает.

## Project

- Workspace: `C:\Users\gekto\projects\bluevpn`
- App type: Flutter Windows-first VPN client.
- Visible product name: `Green VPN`.
- Internal historical/project names still present: `BlueVPN`, `BlueVPNDev1`.
- Do not rename internal tunnel/config/service paths casually.
- Development must follow `C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`: stabilize one roadmap step, freeze rollback, then move to the next step.

## Critical Paths

- Main Flutter file: `C:\Users\gekto\projects\bluevpn\lib\main.dart`
- Windows runner: `C:\Users\gekto\projects\bluevpn\windows\runner`
- Installer script: `C:\Users\gekto\projects\bluevpn\scripts\windows\build_installer.ps1`
- Release gate: `C:\Users\gekto\projects\bluevpn\scripts\windows\bluevpn_release_gate.ps1`
- Backend source: `C:\Users\gekto\projects\bluevpn\backend_live`
- Existing docs: `C:\Users\gekto\projects\bluevpn\docs`
- Development protocol: `C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`

## Machine Paths

- Runtime state/config root: `C:\ProgramData\BlueVPN`
- Private state: `C:\ProgramData\BlueVPN\state`
- Managed config: `C:\ProgramData\BlueVPN\BlueVPNDev1.conf`
- Base config: `C:\ProgramData\BlueVPN\BlueVPNDev1.base.conf`
- Backend log: `C:\ProgramData\BlueVPN\backend.log`
- Auth/UI log: `C:\ProgramData\BlueVPN\auth.log`
- WireGuard exe: `C:\Program Files\WireGuard\wireguard.exe`
- WireGuard tunnel service: `WireGuardTunnel$BlueVPNDev1`

## Servers

- Development/production VPN/backend server: `37.220.85.211`
- Do not use or touch Friendly Linnet/personal server.
- Do not store SSH password or tokens in repo. Ask user if access is needed.

## Current Build Artifacts

Latest known installer build:

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`
- Candidate copy: `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`
- Last known SHA256: `5F88E078B4E8EE4519D29F6A92FF58A738CA1DD5F1E26ED108864390BAE39D01`

Older BlueVPN/GreenVPN installer files were removed from `C:\BlueVPN_Builds`; use `GreenVPN_Setup.exe` or `GreenVPN_Setup_LATEST.exe`.

## Beton Rollback Anchor

If a later change breaks the app again, restore/test this exact frozen build first:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_171555_auth_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `E84E0B9691498D33AC8F5CEFA3B53C0EB8A0DFC43DB856EDEDEB54AE5921AF7D`
- This is the stable auth build: branded Green VPN installer, `GreenVPNService` installed once under LocalSystem, normal UI launch without per-launch UAC, close button hides to tray, tray menu opens/connects/disconnects/exits, HKCU Run starts `greenvpn.exe --background` at Windows login, fresh login/register opens the main app directly, SYSTEM scheduled tasks remain as fallback, backend config fetch unblocked for MVP Trial users, and active Amnezia/WireGuard/WARP guarded.
- Newer accepted stable anchor: `C:\BlueVPN_Builds\ROLLBACK_20260430_1730_dev_admin_cleanup_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `A13C945BB1A88EAF45779398258063A645A03A324827C3A1A2203557278C788B`. This includes auth plus removed visible dev/admin entry points.
- Previous stable anchor: `C:\BlueVPN_Builds\ROLLBACK_20260430_1928_internal_service_checks_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `F261CC3613D3FA730F38F2EBCE0A3FA2F6B4E6C98B432E1C326D80CB825048AA`. This includes support report, installer logo fix, Settings -> Updates, server catalog, basic monitoring status, internal-only YouTube/Discord/Telegram service checks, and the current Green VPN service/tray/autostart/auth foundation.
- Previous stable anchor: `C:\BlueVPN_Builds\ROLLBACK_20260430_2005_payments_hardening_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `0C504DD845E04B15EE36FC912C5F885DC59FB52F5E60241AF74FEA9CB265C8A3`. This includes the previous baseline plus removed user-facing monitoring/order-history clutter and safe YooKassa order/payment validation before tariff activation.
- Previous stable anchor: `C:\BlueVPN_Builds\ROLLBACK_20260430_2015_production_payments_readiness_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `4594ADC55FB813764296AE68C6491731F431C0FFBDE8BFFF67E5BD649D26C9A3`. This includes payments hardening plus production HTTPS/YooKassa readiness checks and authoritative payment lookup in webhook handling.
- Current stable anchor: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`. This includes production-payment readiness plus the hosted payment return page and automatic pending-order polling in the client.

## Testing Workflow Rule

Latest user instruction: do not rebuild or issue a new test installer after every intermediate task. Build the next `GreenVPN_Setup.exe` only at the final handoff point, or when the user explicitly asks to stop and test. Immediately before handing over that final installer, clean the previous installed Green VPN build first with the project cleanup script or equivalent safe cleanup.

Cleanup must remove only Green VPN artifacts:

- Stop `greenvpn.exe` / `bluevpn.exe`.
- Remove Green VPN scheduled tasks: `GreenVPNConnect`, `GreenVPNDisconnect`, `GreenVPNGuard`.
- Remove old BlueVPN task names if present.
- Remove only the Green VPN WireGuard tunnel `BlueVPNDev1` / `WireGuardTunnel$BlueVPNDev1`.
- Remove Green VPN shortcuts and installed folders.
- Remove Green VPN state under `C:\ProgramData\BlueVPN` unless explicitly preserving logs/state for debugging.
- Do not remove WireGuard itself, Amnezia, WARP, or the user's personal/Friendly VPN setup.

## Current App State

Working/mostly working:

- Windows app builds.
- VPN connect/disconnect works after ACL/config repairs.
- Social Only works.
- Auth UX source now uses phone-first login, email-code fallback, and legacy password fallback; final installer/test pass is still pending.
- Tariffs UI was visually improved and simplified; current candidate restores the user traffic slider under clean package chips.
- Backend admin code still exists internally for future separate admin app, but it is no longer reachable from the normal user settings UI.
- Installer exists and is branded as Green VPN.
- Windows-service experiment from the other chat was rolled back; current MVP uses installer-created SYSTEM scheduled tasks for privileged VPN actions, so normal app launch should not request admin rights.
- 2026-04-30 hotfix build hides the installer PowerShell self-elevation window where possible, prevents `subscription_inactive` from blocking MVP VPN connect, and keeps the WSL backend relay alive as a real hidden child process while the app is open.
- 2026-04-30 backend `0.6.1` is deployed on `37.220.85.211`; `/healthz` returns `subscriptionEnforced: false`, and current Trial users can fetch config again even if the old trial date is expired. Public `/api/v1/subscription/apply` still cannot activate paid tariffs directly.
- 2026-04-30 public UI cleanup removed `Backend Admin` from normal settings and simplified the user tariff traffic picker to package chips without numbered icons/slider.
- 2026-04-30 public installed names cleanup changed installed files to `greenvpn.exe`, `uninstall_greenvpn.ps1`, `doctor_greenvpn.ps1`, and `greenvpn_network_recover.ps1`.
- 2026-04-30 boot-conflict fix makes `WireGuardTunnel$BlueVPNDev1` manual/demand-start after connect so it should not auto-start on Windows reboot and fight Amnezia/WARP. Existing old installations must run `greenvpn_boot_repair.ps1` or reinstall this build.
- 2026-04-30 single-active-VPN guard blocks Green VPN connect when another active VPN adapter/service is detected, instead of overlaying full-tunnel routes over Amnezia/WARP/WireGuard.
- 2026-04-30 user-preflight strengthening: normal UI detection now uses `Get-NetAdapter -IncludeHidden` plus CIM adapter/service checks and returns labels like `adapter:device20_full` / `service:AmneziaWGTunnel$device20_full` before launching the SYSTEM connect task.
- 2026-04-30 no-launch-UAC task guard removes Run-as-admin shortcuts and app self-relaunch. Installer creates `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard` tasks; `GreenVPNGuard` disconnects Green VPN if another VPN becomes active.
- The installer exe embeds a `requireAdministrator` manifest, so install-time UAC should belong to `GreenVPN_Setup.exe`; normal app launch should not show UAC.
- 2026-04-30 full uninstaller adds `uninstall_greenvpn.cmd` and strengthens `uninstall_greenvpn.ps1` so one click removes tasks, startup entries, shortcuts, app files, old local app-data, and `C:\ProgramData\BlueVPN` by default while leaving WireGuard/Amnezia/WARP installed.
- 2026-04-30 clean rebuild removed old local install remnants and stale setup exe files, then rebuilt the installer with hidden `install.vbs` bootstrap instead of visible `install.cmd`.
- 2026-04-30 system task registration fix replaced broken `schtasks.exe /TR` creation with `Register-ScheduledTask`; the old approach split the `Green VPN\tools\...` path at the space and left the app without `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard`.
- 2026-04-30 compatibility fix removed unsupported `New-ScheduledTaskSettingsSet -DisallowStartIfOnBatteries` from the installer after it caused `Green VPN install failed. Exit code: 1` on the test Windows PowerShell.
- 2026-04-30 installer logging added `%TEMP%\GreenVPN_Setup.log` and includes that path in future installer failure dialogs.
- 2026-04-30 installer task cleanup fix removed fragile `schtasks.exe /Delete` calls from the install path; missing old tasks no longer abort installation before new `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard` tasks are registered.
- 2026-04-30 task ACL fix: the installer now grants non-admin read/execute rights to `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard`. Previous SYSTEM-only tasks existed and `GreenVPNGuard` ran, but the normal UI got `Access is denied` from `schtasks.exe` and displayed "system component not installed".
- 2026-04-30 native service: added `greenvpn_service.exe` / `GreenVPNService`, installed once by the installer under LocalSystem. The UI now tries local service `http://127.0.0.1:48737` first for connect/disconnect and falls back to `GreenVPNConnect` / `GreenVPNDisconnect` scheduled tasks if the service is unavailable. Install-test passed with `GreenVPNService=Running`, `/ping` OK, `/status` OK; user confirmed app launch/login/VPN flow works, so this is now the rollback-stable anchor.
- 2026-04-30 backend `0.6.2` deployed on `37.220.85.211`: device-limit cleanup for MVP test installs. If a user exceeds `maxDevices`, backend auto-disables the oldest enabled device for that same user and lets the current device fetch config. Healthz includes `autoReplaceOldestDeviceOnLimit: true`.
- 2026-04-30 WSL SSH key configured locally for deploys: `~/.ssh/greenvpn_ed25519`, with `~/.ssh/config` matching host `37.220.85.211`. Do not store or write the server password in repo/docs/scripts; deploys should now run without password prompts.
- 2026-04-30 tray/background stable: native Windows runner now adds a tray icon without adding Flutter tray/window plugins. Close button hides the window; tray left/double click restores it; tray right-click menu has `Open Green VPN`, `Connect VPN`, `Disconnect VPN`, and `Exit`. Tray connect/disconnect calls existing `GreenVPNConnect` / `GreenVPNDisconnect` tasks, leaving the VPN path unchanged. User confirmed it works; rollback anchor is `ROLLBACK_20260430_165617_tray_ok`.
- 2026-04-30 autostart stable: native Windows runner supports `--background` / `--tray`; installer writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\GreenVPN` to start `"greenvpn.exe" --background` at Windows login. This starts only UI/tray, not auto-connect VPN. Rollback anchor is `ROLLBACK_20260430_170548_autostart_ok`.
- 2026-04-30 auth rewrite stable: fresh login/register opens the main app directly; saved-session gate still remains for app restarts; auth errors are normalized to user-friendly Russian messages; existing-email registration switches to login tab with the same email/password filled. Rollback anchor is `ROLLBACK_20260430_171555_auth_ok`.
- 2026-04-30 dev/admin UI cleanup stable: visible `Backend Admin` entry point is removed from normal settings, the debug/dev login button is removed from auth, and the old user-facing `DEV:` config toast is replaced with a normal Russian message. Rollback anchor is `ROLLBACK_20260430_1730_dev_admin_cleanup_ok`, SHA256 `A13C945BB1A88EAF45779398258063A645A03A324827C3A1A2203557278C788B`.
- 2026-04-30 boot/slider polish candidate: startup now shows a branded Green VPN loading card with stage text instead of a bare spinner; tariff page has the traffic slider back under clean 5/20/50/100 GB chips. Build and release gate passed. Candidate installer is `GreenVPN_Setup_BootSliderCandidate_20260430.exe`, SHA256 `DA239DFDE26DB62D0D9045BDCFB66C15A24FBC39C67F9E3417C1F2F6D005DBE5`.
- 2026-04-30 installer UI candidate: the IExpress default grey success/error dialogs are replaced by a custom WinForms `Green VPN Installer` window with green/blue branding, real app icon, live progress/status, and no extra `Open log` button. `FinishMessage` is blank, generated `install_ui.ps1` parses cleanly, and both source/payload release gates passed. Superseded by the support-report candidate.
- 2026-04-30 cleanup hardening: project cleanup script now self-elevates when needed, verifies service/task/tunnel/folder removal, and stops stale WSL relay with `wsl --shutdown` if the old install folder is locked. Manual cleanup verification passed on the test machine.
- 2026-04-30 support report candidate: settings now shows `Поддержка` instead of raw diagnostics. The support screen hides endpoint/path/route technical details and exposes one coded report copy action. The report uses `GVPN1.` + gzip/base64url JSON and excludes passwords, tokens, private keys, and config contents. Candidate installer is `GreenVPN_Setup_SupportReportCandidate_20260430.exe`, SHA256 `0FEF4326F81F58002C229B026B991F0A172EF89E2872E22C6C8A642D58FCEFBC`.
- 2026-04-30 update manifest candidate: the noisy corrupted installer logo square is fixed by drawing the Green VPN key mark directly in the custom installer UI instead of converting the `.ico` through `PictureBox` / `ToBitmap`. Settings now has `Обновления`, the client calls `/api/v1/updates/windows`, and backend `0.6.3` is deployed with a basic update manifest. Current manifest intentionally reports the same version and no download URL until update hosting is configured. Candidate installer is `GreenVPN_Setup_UpdateManifestCandidate_20260430.exe`, SHA256 `96CA9FD1F02A4EE2BE135F8E99A9F8105A4B074DE2022DD2797D684DDB3178F8`.
- 2026-04-30 catalog/monitoring candidate: backend `0.6.4` is deployed. `/api/v1/catalog/servers` returns the first simple server catalog with one healthy `intelligent_smew` endpoint. `/api/v1/monitoring/status` returns backend/database/WireGuard/catalog/updates/payments checks. The client refreshes server picker from the backend catalog, sends `serverId` to config fetch, and adds Settings -> `Состояние сервисов`. Candidate installer is `GreenVPN_Setup_CatalogMonitoringCandidate_20260430.exe`, SHA256 `CBC8996D08A8FD4DB0F9270DF5C24E0E1CD32A0E95F8369FF5D6A61447586611`.
- 2026-04-30 internal service checks candidate: backend `0.6.5` is deployed. `/api/v1/monitoring/services` checks YouTube, Discord, and Telegram via DNS/TCP/TLS/HTTP from the current backend/VPN-server egress point. This is explicitly internal/support/admin monitoring groundwork and must not be exposed as a normal user-facing app screen. The bad intermediate `GreenVPN_Setup_ServiceAvailabilityCandidate_20260430.exe` was deleted. Candidate installer is `GreenVPN_Setup_InternalServiceChecksCandidate_20260430.exe`, SHA256 `F261CC3613D3FA730F38F2EBCE0A3FA2F6B4E6C98B432E1C326D80CB825048AA`.
- 2026-04-30 payment-history/autorenew candidate: backend `0.6.6` was deployed. User order history and auto-renew cancel were implemented, but the user-facing `История заказов` block was removed in the next candidate because it cluttered the tariff screen.
- 2026-04-30 payments-hardening stable: backend `0.6.7` was deployed. User-facing Settings -> `Состояние сервисов` was removed; tariff `История заказов` was removed; YooKassa webhook handling validates order metadata, payment id, amount, and currency before activating a tariff; public order responses still do not leak provider ids. Live synthetic backend checks passed, including successful activation and amount mismatch rejected with HTTP `409`. Frozen rollback is `ROLLBACK_20260430_2005_payments_hardening_ok`, SHA256 `0C504DD845E04B15EE36FC912C5F885DC59FB52F5E60241AF74FEA9CB265C8A3`.
- 2026-04-30 production-payments readiness stable: backend `0.6.8` was deployed. Added admin readiness endpoint `/api/v1/admin/billing/readiness`, `paymentsProductionReady` in `/healthz`, production HTTPS/YooKassa config checks, and authoritative YooKassa payment fetch in webhook handling when credentials are configured. Frozen rollback is `ROLLBACK_20260430_2015_production_payments_readiness_ok`, SHA256 `4594ADC55FB813764296AE68C6491731F431C0FFBDE8BFFF67E5BD649D26C9A3`.
- 2026-04-30 payment-confirmation candidate: backend `0.6.9` is deployed. Added `/payment/return` checkout return page; client auto-polls pending billing orders after create/load/open payment; canceled/expired orders are cleared locally; manual `Проверить оплату` remains as fallback. Candidate installer is `GreenVPN_Setup_PaymentConfirmationCandidate_20260430.exe`, SHA256 `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`.
- 2026-04-30 payment-confirmation stable: frozen rollback is `ROLLBACK_20260430_2028_payment_confirmation_ok`, SHA256 `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`.
- 2026-04-30 email-confirmation candidate: backend `0.7.0` is deployed. Added email confirmation DB tables/columns, `/api/v1/auth/email/status`, `/api/v1/auth/email/resend`, GET/POST `/api/v1/auth/email/verify`, and `/api/v1/admin/email/readiness`. Registration queues/sends confirmation email; without SMTP it stays in safe `not_configured` mode and does not block login/VPN. Settings now shows small email confirmation status/action under Account. Candidate installer is `GreenVPN_Setup_EmailConfirmationCandidate_20260430.exe`, SHA256 `1099C4254E137CFEB7F5611CD0F44526DD8807D5CFF16A218D65925FA5A01AC5`.
- 2026-05-04 SMS/phone readiness candidate: backend `0.7.2` was deployed on `37.220.85.211`. Added phone/SMS DB tables/columns, `/api/v1/auth/phone/status`, `/api/v1/auth/phone/start`, `/api/v1/auth/phone/verify`, and `/api/v1/admin/sms/readiness`. The backend supports safe manual MVP mode plus SMS.ru production mode through server-only environment variables. SMS codes are hashed with `GREENVPN_SMS_CODE_PEPPER`; queued outbox records mask the code body and do not store the real code text. Without SMS.ru credentials, phone UI stays prepared/not-configured and does not break login/VPN.
- 2026-05-04 external-services readiness: added `scripts\configure_backend_env_wsl.sh` plus `scripts\windows\configure_backend_env_wsl.ps1` flow for server-only SMTP/SMS/YooKassa secrets. The script writes secrets only to `/etc/bluevpn/backend.env` on the server and a systemd drop-in, never to repo/docs. Added `docs\EXTERNAL_SERVICES_CHECKLIST_RU.md` with exact user checklist for Yandex 360 mail, SMS.ru, YooKassa, DNS/HTTPS, and post-setup checks.
- 2026-05-04 account/support-report candidate: backend `0.7.3` is deployed on `37.220.85.211`. Added `/api/v1/support/reports` and `support_reports` table for encoded user support reports. Settings -> Account now shows only simple `Почта` and `Телефон` rows; noisy separate `Подтвердить почту` / `Привязать телефон` rows are removed from normal settings. Settings -> Support now sends a coded `GVPN1.` report to backend instead of only copying it. Report excludes passwords, tokens, private keys, and config contents. Language selector is locked to `Русский` until real i18n. New installer candidate is `GreenVPN_Setup_AccountSupportReport_20260504.exe`, SHA256 `FD94A3B9B02161EF40392F441B748053E720A0B233EBA603B5313FB2C452C0DF`.
- 2026-05-04 live backend check: `/healthz` returns `version: 0.7.3`, `paymentsProductionReady: false`, `emailProductionReady: false`, `smsProductionReady: false` until real external credentials are configured. This is expected.
- 2026-05-04 build checks: `python -m py_compile backend_live\app\main.py`, `dart format lib\main.dart`, `flutter build windows --release -t .\lib\main.dart`, and `bluevpn_release_gate.ps1 -StrictPaymentGate` passed. A live synthetic support-report smoke test returned `status: received`.
- 2026-05-04 admin/support backend candidate: backend source is now `0.8.1`. Added `GET /api/v1/admin/users/{user_id}`, support report filters by `status`/`userId`/`email`/`deviceUid`, fixed admin order filter `all`, and expanded the separate `admin_support_app` with a user card showing account, subscription, devices, orders and support reports. Support can disable/enable devices from that card. Admin UI string rendering was hardened with HTML escaping. Local checks passed: `python -m py_compile backend_live\app\main.py` and `node --check admin_support_app\app.js`. Deploy status must be checked before assuming live server is `0.8.1`.
- 2026-05-04 admin/support workflow candidate: backend source is now `0.8.2` and deployed on `37.220.85.211`. Added support report comments, admin audit log, admin audit endpoint, user search by email/phone/device id, support report search UI, user search UI, comments in report dialog, and `Аудит` section in the separate `admin_support_app`. Mutating admin actions now write audit events. Local checks passed: `python -m py_compile backend_live\app\main.py` and `node --check admin_support_app\app.js`. Live smoke passed: `/healthz`, admin users, support reports, audit, and report comments endpoints respond.
- 2026-05-04 admin staff/roles candidate: backend source is now `0.8.3` and deployed on `37.220.85.211`. Added prepared internal role matrix (`owner`, `admin`, `support`, `finance`, `readonly`), `admin_staff` table, staff list/upsert/update endpoints, optional `X-Admin-Actor` attribution for audit, and `Команда` section in the separate `admin_support_app`. Role enforcement is intentionally `prepared_not_enforced` so the current shared admin token cannot lock the team out before real staff auth exists. Live smoke passed: `/healthz` returned `0.8.3`, roles returned, staff upsert worked, and audit recorded actor `codex-smoke-0.8.3`. The first placeholder staff row is `support@greenvpn.pro`.
- 2026-05-04 support triage/SLA candidate: backend source is now `0.8.4` and deployed on `37.220.85.211`. Added support workflow endpoint, report categories, report priorities, SLA due time, first-response time, auto-triage by keywords, priority/category/assigned filters, and editable workflow fields in the separate `admin_support_app`. This is internal support tooling only and must not become a normal user-facing screen. Local check passed: `python -m py_compile backend_live\app\main.py`; `node.exe` is blocked by Windows `Access is denied` in this session, so JS was checked with a static Python id/reference scan instead. Live smoke passed: `/healthz` returned `0.8.4`, workflow endpoint returned statuses/priorities/categories, and support report payloads include `category`, `triageReason`, `slaDueAt`, and `firstResponseAt`.
- 2026-05-04 internal incidents candidate: backend source is now `0.8.5` and deployed on `37.220.85.211`. Added `admin_incidents` storage, incident workflow/severity metadata, monitoring/service-to-incident synchronization, admin incident endpoints, open incident count in overview, and `Инциденты` section in the separate `admin_support_app`. Red/yellow monitoring checks create or reopen incidents; green checks auto-resolve matching open incidents. Incident updates write audit entries with optional `X-Admin-Actor`. This is internal admin/support monitoring only and must not be exposed as a normal user-facing app screen. Local check passed: `python -m py_compile backend_live\app\main.py`; `node.exe` is still blocked by Windows `Access is denied`, so the admin JS/HTML was checked with a static Python id/reference scan. Live smoke passed: `/healthz` returned `0.8.5`, incidents endpoint returned workflow/payload, incident update worked, and audit recorded actor `codex-smoke-0.8.5b`.
- 2026-05-04 managed server catalog candidate: backend source is now `0.8.7` and deployed on `37.220.85.211`. Added `server_catalog_entries` storage, prepared statuses/protocols/transports for future resilience/fallback work, admin server catalog endpoints, role permissions `servers.read` / `servers.manage`, and `Серверы` section in the separate `admin_support_app`. Public `/api/v1/catalog/servers` deliberately still exposes only the proven `intelligent_smew` endpoint; managed entries stay internal until we intentionally publish real multi-server config. Local checks passed: `python -m py_compile backend_live\app\main.py` and static admin JS/HTML scan. Live smoke passed: `/healthz` returned `0.8.7`, admin catalog returned workflow/public/managed payloads, and disabled internal smoke entry `codex_disabled_smoke` did not appear in the public client catalog.
- 2026-05-04 admin analytics candidate: backend source is now `0.8.8` and deployed on `37.220.85.211`. Added `GET /api/v1/admin/analytics/summary`, business/support/incidents/updates/server-catalog/auth/readiness metrics, 14-day trend series, and `Аналитика` section in the separate `admin_support_app`. Analytics refresh syncs monitoring incidents, but this remains internal admin/support functionality only. Live smoke passed: `/healthz` returned `0.8.8` and analytics returned users/revenue/support/incidents/orders/trends.
- 2026-05-04 server health observations candidate: backend source is now `0.8.9` and deployed on `37.220.85.211`. Added `server_health_observations`, `GET /api/v1/admin/server-health`, `POST /api/v1/admin/server-health/observations`, admin UI health table in `Серверы`, and analytics counters for endpoint health. A health observation can update the matching managed catalog entry health/status/latency, but public `/api/v1/catalog/servers` still only exposes the proven `intelligent_smew` endpoint until safe rollout rules exist. Live smoke passed with a sanitized healthy observation for `intelligent_smew`.
- 2026-05-04 managed service monitoring candidate: backend source is now `0.9.0` and deployed on `37.220.85.211`. Added `monitoring_targets`, `service_availability_observations`, admin monitoring target CRUD, service availability observation create/list endpoints, default targets for YouTube/Discord/Telegram/API/update/payment, and an internal `Мониторинг` section in the separate `admin_support_app`. This is strictly admin/support functionality and must not appear in the normal user client. Live smoke passed: `/healthz` returned `0.9.0`, seeded targets loaded, `codex_service_smoke` target upserted, green observation created, and failed checks over 24h remained `0`.
- 2026-05-05 admin/support alerts readiness candidate: backend source and live server are now `0.9.2`. Added admin external-action checklist, protected server-side readiness self-checks, monitoring probe inventory, Telegram incident alert readiness/test endpoints, and incident last-alert metadata. Added `scripts\monitoring\install_probe_systemd.sh` for a controlled monitoring VPS probe and hardened `scripts\windows\check_external_services_readiness.ps1` with `-ServerAdminSelfCheck`, which reads the admin token only on the server and returns sanitized readiness summaries. Separate `admin_support_app` now shows external owner actions, alert readiness/test action, probe readiness and incident alert status. This remains internal admin/support functionality only.
- 2026-05-05 release candidate rebuilt after cleaning the previous installed test build. Current installer aliases are `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`; named candidate copy is `C:\BlueVPN_Builds\GreenVPN_Setup_AdminSupportAlertsReadiness_20260505.exe`; SHA256 `0B9BA08343444DF23F8A01FD47A52F3A3779F3CD93A75EF752D89FD664AC8F82`. Checks passed: Python compile, monitoring/config shell syntax, `flutter build windows --release -t .\lib\main.dart`, source release gate, installer payload release gate, live `/healthz` `0.9.2`, and readiness checker with `-ServerAdminSelfCheck`.
- 2026-05-05 admin staff sessions/RBAC candidate: backend source is now `0.9.3`. Added proper staff login/session endpoints (`/api/v1/admin/auth/login`, `/api/v1/admin/auth/me`, `/api/v1/admin/auth/logout`), `admin_sessions` storage, password hash fields for `admin_staff`, temporary staff password setup, role-based permission enforcement on admin endpoints, and audit attribution from the resolved staff context. Bootstrap `admin_token` remains as owner/emergency access but staff sessions are now the intended admin/support app path.
- 2026-05-05 separate `admin_support_app` now supports email/password staff login, logout, session restore, role-aware navigation, permission-aware data loading, and default-off `Запомнить на этом компьютере`. Staff password entry is only a temporary password field in the `Команда` form; open passwords are not stored or rendered. `node.exe` from the Codex WindowsApps bundle is blocked by Windows with `Access is denied` in this desktop session, so JS syntax checking cannot currently use `node --check`; backend Python compile still passes.
- 2026-05-05 admin feature flags/runbooks candidate: backend source and live server are now `0.9.4`. Added `admin_feature_flags` and `admin_runbooks` storage, default seeded internal feature flags/runbooks on startup, admin endpoints `/api/v1/admin/feature-flags` and `/api/v1/admin/runbooks`, RBAC permissions `flags.read` / `flags.manage` / `runbooks.read` / `runbooks.manage`, overview counters, and matching separate `admin_support_app` sections `Флаги` and `Инструкции`. This is internal admin/support/ops tooling only; it must not appear in the normal user Green VPN client. Local backend compile, static admin content checks, and `quickjs` syntax parse for `admin_support_app\app.js` passed. Live smoke passed on `37.220.85.211`: `/healthz` returned `0.9.4`, feature flags returned 8 seeded records, runbooks returned 7 seeded records, and overview returned matching counters.
- 2026-05-05 admin support actions candidate: backend source and live server are now `0.9.5`. Added `admin_support_actions`, device support config-refresh markers, RBAC permissions `support_actions.read` / `support_actions.manage`, admin endpoints `/api/v1/admin/support/actions/workflow`, `/api/v1/admin/support/actions`, and `/api/v1/admin/users/{user_id}/support-actions`. Supported actions are reset user sessions, request/clear config refresh marker, disable/enable device, and add internal support note. User detail now includes support action history; device payloads include support refresh markers. Separate `admin_support_app` now shows the quick support action panel inside the user card. This is internal support/admin tooling only and must not appear in the normal user Green VPN client. Local checks passed: `python -m py_compile backend_live\app\main.py` and `quickjs` syntax parse for `admin_support_app\app.js` up to expected browser-global boundary. Live smoke passed: `/healthz` returned `0.9.5`, support action workflow returned 6 actions, support action list endpoint returned, and admin overview returned support action counters.
- 2026-05-05 external owner-action workflow candidate: backend source is now `0.9.6`. Added `admin_owner_action_statuses`, RBAC permission `readiness.manage`, and `POST /api/v1/admin/external-actions/{action_code}` so owner/admin can track external setup items as `todo`, `in_progress`, `waiting_owner`, `waiting_provider`, `ready_to_apply`, `done`, `blocked`, or `not_needed`. Separate `admin_support_app` now lets allowed roles update owner status and safe notes directly in the external-actions checklist. Manual owner status does not override real readiness; production readiness still depends on actual DNS/env/HTTPS/provider checks. This is internal admin/support tooling only and must not appear in the normal user Green VPN client.
- 2026-05-05 staged update rollout candidate: backend source is now `0.9.7`. Public update manifest endpoints accept `clientId` and return `updateAvailable`, `baseUpdateAvailable`, `rolloutEligible`, `rolloutBucket`, and `rolloutReason`. The Windows client sends its stable device id to `/api/v1/updates/windows` and trusts server `updateAvailable`, so release records can be published to a limited rollout percent without showing the installer to every device. Separate `admin_support_app` preview now displays rollout eligibility/reason for the admin update manifest. This is the safe foundation for future updater/staged rollout/rollback work.
- 2026-05-05 safe server catalog publication gate candidate: backend source and live server are now `0.9.9`. Public `/api/v1/catalog/servers` still deliberately exposes only the proven builtin `intelligent_smew` endpoint. Managed server catalog entries now include `publicEligibility`, explicit blockers, latest health observation metadata, and 24h health/failure counters. Added internal admin endpoint `/api/v1/admin/server-catalog/publication-readiness`; it explains whether managed endpoints can be published, why they are blocked, and the next action. Separate `admin_support_app` shows this publication gate in `Серверы`. This is internal/admin-only resilience groundwork and must not change user routing until managed endpoint peer/config provisioning exists. Rebuilt installer candidate is `C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`, SHA256 `E0A861DE4B486E5FFC037C9D850B5E0F30C702F876DEAD536AB7BA43E53E7A54`.
- 2026-05-05 managed endpoint config-readiness candidate: backend source and live server are now `0.9.10`. Managed server catalog entries now have `clientConfigProfile` and `clientConfigReadiness`; only `builtin_wg0` is considered client-config-ready for the current `37.220.85.211:443` WireGuard endpoint. Added internal admin endpoint `POST /api/v1/admin/server-catalog/seed-current`, which creates/updates internal managed entry `current_wg0` as config-ready but not public. Separate `admin_support_app` can seed this current endpoint and shows its config profile/readiness. Public `/api/v1/catalog/servers` is intentionally unchanged and still exposes only builtin `intelligent_smew`; managed entries remain blocked until health/provisioning rollout rules are safe.
- 2026-05-05 current endpoint health scoring candidate: backend source and live server are now `0.9.11`. Added admin-only `POST /api/v1/admin/server-health/probe-current`; it checks server-local `wg0`, config/profile readiness, peer/handshake signs and UDP endpoint signs, then stores safe health observations with score `0-100`. Live probe for `current_wg0` returned `status: healthy`, `score: 90`. Public `/api/v1/catalog/servers` remains the correct client URL and still exposes zero managed entries to users.
- 2026-05-05 monitoring details hardening: backend source and live server now sanitize arbitrary `details` JSON for both `server_health_observations` and `service_availability_observations` on write and on read. This protects admin/support monitoring from accidentally storing or rendering private keys, tokens, passwords, raw WireGuard configs or provider secrets if a probe/admin payload is malformed. Version remains `0.9.11`.
- 2026-05-05 production domain status: server-side nginx is active for `api.greenvpn.pro`, Let's Encrypt certificate exists and certbot timer is active. WSL/server checks can reach `https://api.greenvpn.pro/healthz` with forced resolve. If Windows host cannot reach `37.220.85.211:8000`, treat it as local routing/VPN-stack state first, not as proof the backend is down.
- 2026-05-05 auth challenge groundwork: backend source and live server are now `0.9.12`. Added `POST /api/v1/auth/challenge/start` and `POST /api/v1/auth/challenge/verify` wrappers over existing phone SMS and email-code login. Normal client auth screen now presents `Телефон`, `Email-код`, and legacy `Пароль`; phone/email code verification sends device metadata and then runs the existing VPN warmup. `flutter build windows --release -t .\lib\main.dart`, `python -m py_compile`, and `bluevpn_release_gate.ps1 -StrictPaymentGate` passed. No new installer was built for this step because installer issuance is now final-only.
- 2026-05-05 admin auth event filters: backend source and live server are now `0.9.14`. `GET /api/v1/admin/auth/events` supports `eventType`, `status`, and `contact` filters; returned event details pass through server-side redaction. Separate `admin_support_app` adds filters for SMS/email auth type, status, and contact/user id search in `Входы`. Auth analytics no longer counts normal `created` code-start events as failures. No installer was built.

Known fragile areas:

- App still has large `lib/main.dart`; avoid big rewrite unless planned.
- Some internal BlueVPN strings are expected because tunnel/config names stay `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1`, and `C:\ProgramData\BlueVPN`.
- Auth challenge UI is freshly changed and still needs a clean final installer test: phone code, email code, and legacy password fallback.
- Privileged VPN control now has a native service candidate, but scheduled tasks remain as fallback until user testing confirms service connect/disconnect is stable.
- Do not reintroduce per-launch UI admin/UAC.

## Important Recent Fix History

The app previously broke because `C:\ProgramData\BlueVPN\BlueVPNDev1.base.conf` got locked to the wrong ACL/current user and normal/elevated app launches could not both write it. The working model is:

- Shared WireGuard config files under `C:\ProgramData\BlueVPN` must be machine-shared.
- Private session/device/prefs state can stay in `C:\ProgramData\BlueVPN\state`.
- Do not harden config files to current-user-only ACL.
- If connect fails with `PathAccessException` on `BlueVPNDev1.base.conf`, inspect config ACL and repair shared config permissions rather than rewriting the app.

## Branding State

Visible user-facing brand should be:

- `Green VPN`
- Installer: `GreenVPN_Setup.exe`
- Desktop shortcut: `Green VPN.lnk`
- Start menu folder/shortcut: `Green VPN`
- Installed executable: `greenvpn.exe`
- Installed uninstall script: `uninstall_greenvpn.ps1`
- One-click uninstall wrapper: `uninstall_greenvpn.cmd`
- Installed support tools: `doctor_greenvpn.ps1`, `greenvpn_network_recover.ps1`
- Boot-conflict repair: `greenvpn_boot_repair.ps1`
- Privileged VPN task tool: `greenvpn_vpn_task.ps1`
- Scheduled tasks: `GreenVPNConnect`, `GreenVPNDisconnect`, `GreenVPNGuard`
- Native service candidate: `GreenVPNService` / `greenvpn_service.exe`

Internal technical names to preserve:

- `BlueVPNDev1`
- `WireGuardTunnel$BlueVPNDev1`
- `C:\ProgramData\BlueVPN`

## Recommended Next Task

Follow `DEVELOPMENT_PROTOCOL.md`. The payment-confirmation build is still the stable rollback baseline. Current live backend/admin-support/client-source work is `0.9.43`: external endpoint probe readiness plus server-health incident sync are deployed, while phone-first auth UI and filtered auth-event support tooling remain in source. The current public Windows installer aliases still point to the support-report fallback build; do not rebuild another installer until final handoff or explicit user stop/test request.

## 2026-05-09 Site/Admin Hosting Update

- Owner changed DNS for root/www:
  - `greenvpn.pro -> 72.56.32.197`;
  - `www.greenvpn.pro -> 72.56.32.197`.
- `72.56.32.197` now hosts the public static site and download page:
  - `https://greenvpn.pro/`;
  - `https://www.greenvpn.pro/`;
  - `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`.
- The same server hosts the current static admin/support app temporarily at:
  - `https://greenvpn.pro/admin/`;
  - `https://www.greenvpn.pro/admin/`.
- A separate nginx site for `admin.greenvpn.pro` is prepared, but HTTPS cannot be issued until owner adds:
  - `A admin -> 72.56.32.197`.
- Admin static UI is now protected at the nginx layer:
  - `https://greenvpn.pro/admin/` returns HTTP `401` without Basic Auth;
  - authenticated Basic Auth smoke returns HTTP `200`;
  - credentials are stored only in root-only files on `72.56.32.197`: `/root/greenvpn-admin-basic-auth-onetime.txt` and `/root/greenvpn-admin-owner-login-onetime.txt`.
- Backend staff login is usable for the owner account:
  - owner staff role is `owner`;
  - password is server-generated and stored only in `/root/greenvpn-admin-owner-login-onetime.txt` on `72.56.32.197` and the origin root account;
  - live login smoke returned `authType=staff_session` and a session token was issued, but the token was not printed.
- Admin email 2FA is implemented in backend/admin UI and server-only pepper is configured, but it is temporarily not enforced because the existing Yandex 360 SMTP app password is invalid:
  - origin `37.220.85.211` could not reach Yandex SMTP directly over IPv4 SMTP ports;
  - a restricted Timeweb TCP forward `greenvpn-yandex-smtp-relay.service` is active on `72.56.32.197`, source-limited to `37.220.85.211`;
  - origin now resolves `smtp.yandex.ru` to `72.56.32.197` and uses port `2587`, STARTTLS reaches Yandex, but Yandex returns `535 authentication failed`;
  - owner must rotate/apply the Yandex SMTP app password through the safe server env flow before re-enabling mandatory admin 2FA.
- `api.greenvpn.pro` remains a separate nginx site/server block and still proxies to origin backend `37.220.85.211`.
- Capacity check on `72.56.32.197` after deployment: load `0.00`, memory about `344 MiB` used / `1.6 GiB` available, disk `2.1 GiB` used of `38 GiB`. This is enough for public site, admin static app, installer download and API reverse proxy. The actual VPN endpoint/traffic remains on `37.220.85.211`.

Suggested sequence:

1. Preserve `ROLLBACK_20260430_2028_payment_confirmation_ok` as the known-good build.
2. Test `C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`.
3. Confirm the installer shows the custom branded progress window with a normal Green VPN key mark, not a noisy square, and no `Open log` button.
4. Confirm the installed app still shows the branded loading screen during app startup.
5. Confirm settings has `Поддержка`, and `Отправить отчёт` submits a `GVPN1.` report without exposing technical data.
6. Confirm settings has `Обновления`, and the update screen says the current version is up to date.
7. Confirm settings does not show `Состояние сервисов` or a separate `Доступность сервисов` user screen.
8. Confirm server picker still opens and shows Netherlands #1 / WireGuard UDP from backend catalog.
9. Confirm tariff page has the traffic slider and clean package chips.
10. Confirm tariff page does not show `История заказов` and stays focused on current tariff/payment.
11. Confirm `Отключить автопродление` appears only when relevant and does not remove the current paid period.
12. Confirm pending payment block says payment is checked automatically, and manual `Проверить оплату` still works.
13. Confirm Settings -> Account is simple: only `Почта`, `Телефон`, and `Выйти`, without duplicated confirmation/binding rows.
14. Confirm `Поддержка` sends the report and shows a human success/error message.
15. Confirm phone binding dialog can still be opened from the `Телефон` row when needed; until SMS.ru is configured it should not crash.
16. Confirm VPN connect/disconnect, tray/background, autostart, auth, tariff screen, and Social Only still work.
17. If the current public installer passes user testing, freeze a new rollback anchor before rebuilding a new user-facing installer.
18. Continue separate admin/support app work: staff password change/2FA, owner-only bulk controls, finance analytics, deeper support workflow and endpoint rollout tooling.
19. Next internal/admin step: finish the external-services activation path. User actions still needed later are DMARC, SMTP mailbox/app password, SMS.ru API key, YooKassa production keys/webhook, Telegram alert bot/chat id, and a small monitoring VPS. Code is prepared so these secrets go only into server env, not repo/docs.
20. Continue update layer: publish real release records only after upload hosting is ready, include SHA256, and use rollout percent below `100` for first production users.
21. Continue toward safe endpoint rollout rules: managed endpoint publication gating, client-config readiness, server-local health scoring, external endpoint probe readiness and server-health incident sync are prepared in backend/admin `0.9.43`; next missing pieces are installing the real external monitoring VPS/probe runner and real managed endpoint peer/config provisioning before any new endpoint appears in `/api/v1/catalog/servers`.

## Commands

Build Flutter release:

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
```

Run release gate:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
```

Build installer:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

Deploy backend from WSL script wrapper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\deploy_backend_wsl.ps1
```

Diagnostics:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Programs\Green VPN\tools\doctor_greenvpn.ps1"
```

Network recovery helper for testers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Programs\Green VPN\tools\greenvpn_network_recover.ps1"
```

Boot conflict repair for testers who rebooted after old builds and lost networking:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Programs\Green VPN\tools\greenvpn_boot_repair.ps1" -FlushDns
```

## Worktree Warning

The working tree is dirty and contains user/assistant changes. Do not run destructive commands:

- no `git reset --hard`;
- no `git checkout --`;
- no deleting backups/configs unless user explicitly approves.

Before large edits:

```powershell
git -C C:\Users\gekto\projects\bluevpn status --short
```

## Current Production Domain State

- Public domain: `greenvpn.pro`.
- API domain: `api.greenvpn.pro`.
- DNS: REG.RU zone with `A api -> 37.220.85.211`.
- HTTPS: Let's Encrypt certificate installed via certbot/nginx on `37.220.85.211`.
- nginx vhost: `/etc/nginx/sites-enabled/greenvpn-api.conf` proxies `api.greenvpn.pro` to backend `127.0.0.1:8000`.
- Backend env drop-in: `/etc/systemd/system/bluevpn-backend.service.d/greenvpn-domain.conf`.
- Backend bootstrap catalog now advertises `https://api.greenvpn.pro` first and raw IP `http://37.220.85.211:8000` as fallback.
- Next external item: configure real mail provider/SMTP for production email confirmation. Do not block code work on this; continue with readiness/fallbacks until credentials exist.

## 2026-05-05 Current Candidate

- Backend `0.9.7` is deployed on `37.220.85.211`.
- Staged update manifests accept a stable `clientId` and return rollout fields: `baseUpdateAvailable`, `rolloutEligible`, `rolloutBucket`, `rolloutReason`, `rolloutPercent`.
- Windows client sends its stored device id to `/api/v1/updates/windows`.
- Admin/support app shows rollout eligibility/reason in the updates panel.
- Latest installer candidate:
  - `C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`
  - SHA256: `E0A861DE4B486E5FFC037C9D850B5E0F30C702F876DEAD536AB7BA43E53E7A54`
- Local installed Green VPN artifacts were cleaned before this installer build.
- Passed checks:
  - `python -m py_compile backend_live\app\main.py`
  - `dart format lib\main.dart`
  - `admin_support_app\app.js` syntax smoke via Python + QuickJS
  - `flutter build windows --release -t .\lib\main.dart`
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`
  - live `/healthz`, public `/api/v1/catalog/servers`, forced-resolve `https://api.greenvpn.pro/healthz`, and sanitized admin publication-readiness smoke on `37.220.85.211`

## 2026-05-05 Current Endpoint Health Scoring

- Backend `0.9.11` is deployed on `37.220.85.211`.
- Public client catalog URL is `GET /api/v1/catalog/servers`.
- Deprecated/incorrect `/api/v1/server-catalog` must not be used for the normal Windows client.
- Public `/api/v1/catalog/servers` remains safe for users:
  - `ok: true`;
  - builtin `intelligent_smew` is still the client-visible server;
  - managed endpoint publication stays blocked;
  - `clientVisibleManagedEntries: 0`.
- Internal admin health flow is now live:
  - `GET /api/v1/admin/server-catalog`;
  - `GET /api/v1/admin/server-health`;
  - `POST /api/v1/admin/server-health/probe-current`.
- `probe-current` runs a safe server-local check for `current_wg0` / `BlueVPNDev1` readiness:
  - checks `wg0` visibility/readiness;
  - checks WireGuard config/profile signals;
  - checks peer/handshake signs when available;
  - checks UDP endpoint reachability signs;
  - stores only safe technical observations and score `0-100`;
  - never stores or returns private keys, admin tokens, user passwords or private WireGuard configs.
- Live admin smoke passed without printing admin token:
  - `probe-current` returned `ok: true`, `status: healthy`, `score: 90`;
  - `server-health` returned observations with Russian labels/data groups for checks, endpoint, score and wireguard details;
  - `server-catalog` returned managed entries for admin view while public clients still see zero managed entries.
- Separate `admin_support_app` uses Russian health wording:
  - `Наблюдения здоровья`;
  - `Оценка здоровья`;
  - `Проверить текущий endpoint`;
  - `Задержка`, `потери`, `статус`, `score`.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax check for `admin_support_app\app.js`.
- No new user `GreenVPN_Setup.exe` was rebuilt for this step because only backend/admin-support internals changed.
- Progress marker after this step:
  - overall master plan: ~39%;
  - Windows MVP: ~85%;
  - monitoring/resilience layer: ~52%.

## 2026-05-05 Monitoring Details Hardening

- Backend source and live server remain `0.9.11`.
- Before issuing this candidate, local installed Green VPN artifacts were fully cleaned with `scripts\windows\greenvpn_clean_previous_install.ps1`; verification found no `GreenVPNService`, `WireGuardTunnel$BlueVPNDev1`, Green VPN scheduled tasks, installed folder, or `C:\ProgramData\BlueVPN`.
- Added server-side sanitization for arbitrary monitoring `details` payloads:
  - `server_health_observations`;
  - `service_availability_observations`.
- Sanitization now runs before storing new observations and again before returning old observations through admin APIs.
- Sensitive-looking keys and raw value patterns are redacted:
  - private/preshared keys;
  - admin/session/device tokens;
  - passwords/secrets;
  - raw WireGuard config text;
  - SMTP/SMS/YooKassa secret-like fields.
- Safe technical fields such as `score`, latency, status, host, port, protocol, probe id and check steps remain visible for admin/support diagnostics.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax check for `admin_support_app\app.js`.
- Deployed to `37.220.85.211` with `scripts\windows\deploy_backend_wsl.ps1`.
- Live checks passed:
  - forced-resolve `https://api.greenvpn.pro/healthz` returns `version: 0.9.11`;
  - forced-resolve `https://api.greenvpn.pro/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - server-local Python smoke confirms monitoring details sanitizer redacts dummy private-key/raw-config fields while preserving safe score/latency fields.
- Fresh installer was rebuilt for clean-install testing:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_MonitoringDetailsHardening_20260505.exe`;
  - SHA256 `BBB5E0E8CAFDD1465DEBED2537580B799FAFC5AABFA24F8F94DAA22D9233A387`.
- Admin/support app is served locally at `http://127.0.0.1:8090/`.

## 2026-05-05 Support Report Send-First Fallback

- User support screen keeps the primary flow as `Отправить отчёт`.
- If backend submission fails, the screen now shows `Скопировать код отчёта` as a fallback.
- Successful submission hides the encoded report code; normal users still do not see technical diagnostics by default.
- Backend support report storage and admin decode flow were already present:
  - `POST /api/v1/support/reports`;
  - `GET /api/v1/admin/support/reports`;
  - `GET /api/v1/admin/support/reports/{report_id}/decoded`.
- Local installed Green VPN remained fully cleaned before this installer build.
- Checks passed:
  - `dart format lib\main.dart`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax check for `admin_support_app\app.js`;
  - source and payload `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `scripts\windows\build_installer.ps1`.
- Latest installer:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`;
  - SHA256 `5F88E078B4E8EE4519D29F6A92FF58A738CA1DD5F1E26ED108864390BAE39D01`.
- Admin/support app local URL: `http://127.0.0.1:8090/`.

## 2026-05-05 Auth Challenge / Phone-First Login Source Candidate

- Backend source and live server are now `0.9.12`.
- Added neutral auth challenge endpoints:
  - `POST /api/v1/auth/challenge/start`;
  - `POST /api/v1/auth/challenge/verify`.
- These endpoints route to the existing phone SMS login or email-code login and return method/channel metadata without exposing codes.
- Normal user auth screen now has three tabs:
  - `Телефон` as primary;
  - `Email-код` as fallback;
  - `Пароль` as legacy fallback.
- Password registration/login still exists as a fallback, but is no longer the first visible flow.
- Code verification sends safe device metadata (`deviceUid`, `deviceName`, `platform`, `appVersion`) and then runs the existing VPN config warmup.
- User-facing code errors now map invalid/expired codes to a normal Russian message.
- Checks passed:
  - `dart format lib\main.dart`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `flutter build windows --release -t .\lib\main.dart`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL live `/healthz` returns `version: 0.9.12`;
  - WSL live public `/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - OpenAPI includes both auth challenge endpoints;
  - invalid-email smoke returns HTTP `400` on both challenge start and verify, confirming the route is live without creating a test user.
- `node --check admin_support_app\app.js` still cannot run from this Codex desktop session because bundled `node.exe` returns `Access is denied`; no admin app JS was changed in this step.
- No installer was rebuilt for this step per the latest user instruction. Build the next test installer only at final handoff or explicit stop/test request.
- Admin/support app local URL remains `http://127.0.0.1:8090/`.

## 2026-05-05 Admin Auth Event Filters

- Backend source and live server are now `0.9.14`.
- `GET /api/v1/admin/auth/events` now accepts:
  - `eventType`;
  - `status`;
  - `contact`.
- Contact search matches email, phone, or exact user id.
- Auth event `details` are sanitized before response to avoid accidental sensitive data exposure in admin/support tooling.
- `admin_support_app` -> `Входы` now has filters for contact/user id, event type, and status.
- Admin analytics no longer counts normal `created` code-start events as failed auth events.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax check for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.14`;
  - WSL forced-resolve `/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - server-local smoke called filtered `list_auth_events` without printing contact data.
- No installer was rebuilt.

## 2026-05-05 Controlled Monitoring Probe Readiness

- Backend source and live server are now `0.9.15`.
- Added admin-only service-probe readiness:
  - `GET /api/v1/admin/monitoring/readiness`;
  - `probeReadiness` inside monitoring summaries;
  - product readiness now has a separate `monitoring_probes` check.
- Readiness reports whether controlled probes are fresh, whether required targets are covered, and why production monitoring still needs a separate monitoring VPS.
- Required targets default to `green_api_healthz`, `production_api_healthz`, `youtube_web`, `discord_web`, and `telegram_web`.
- `admin_support_app` -> `Мониторинг` now shows probe readiness and required-target coverage in the probe-agent cards.
- Release gate now checks the admin server catalog, server health, monitoring targets, monitoring probes, and monitoring readiness endpoints.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax check for `admin_support_app\app.js`;
  - `bash -n scripts/monitoring/install_probe_systemd.sh` through WSL;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.15`;
  - WSL forced-resolve `/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - OpenAPI lists `/api/v1/admin/monitoring/readiness`;
  - server-local readiness smoke returned `productionReady: false` with no secrets printed, because the external monitoring VPS is still an owner-action item.
- No installer was rebuilt. Next installer remains final-only or explicit stop/test-only.
- Admin/support app local URL remains `http://127.0.0.1:8090/`.

## 2026-05-05 Support Action Safety Guard

- Backend source and live server are now `0.9.16`.
- Dangerous support actions now require a clear reason server-side:
  - `reset_user_sessions`;
  - `disable_device`.
- `support_action_workflow_options()` now exposes `requiresReason` and `confirmationText` so admin/support UI can handle dangerous actions consistently.
- `admin_support_app` now asks for confirmation before dangerous support actions and blocks reason-required actions until a usable reason is entered.
- `admin_support_app` -> `Техподдержка` now also shows the latest support actions with filters by action, status, and user id, so support can review recent resets/device changes without opening a specific user first.
- Release gate now checks support action workflow and per-user support action endpoints.
- `scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck` now also checks protected admin readiness, monitoring readiness, server catalog publication readiness, support action workflow, and auth-event filters without printing the admin token.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax check for `admin_support_app\app.js`;
  - local admin app still responds at `http://127.0.0.1:8090/`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.16`;
  - WSL forced-resolve `/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - OpenAPI lists support action workflow/action endpoints;
  - server-local smoke confirmed `reset_user_sessions` without reason returns HTTP `400` and does not execute.
  - `check_external_services_readiness.ps1 -SkipServerSelfCheck -ServerAdminSelfCheck -Json` returns protected admin self-check green; it still reports owner-action gaps for DMARC and external HTTPS reachability from this local Windows/WSL path.
- No installer was rebuilt.

## 2026-05-05 Monitoring Default Targets Refresh

- Backend source and live server are now `0.9.17`.
- Added admin-only endpoint:
  - `POST /api/v1/admin/monitoring/targets/seed-defaults`.
- It refreshes built-in monitoring targets for YouTube, Discord, Telegram, API health, production API domain, Windows update manifest, and payment return page.
- The refresh upserts built-in targets and does not delete custom monitoring targets.
- `admin_support_app` -> `Мониторинг` now has `Обновить базовые цели`.
- Release gate now checks the seed-defaults endpoint.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax check for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.17`;
  - WSL forced-resolve `/api/v1/catalog/servers` still returns builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`;
  - OpenAPI lists `/api/v1/admin/monitoring/targets/seed-defaults`;
  - server-local smoke refreshed 7 built-in targets without printing secrets.
- No installer was rebuilt.

## 2026-05-05 Update Release Readiness Guard

- Backend source and live server are now `0.9.18`.
- Added admin-only update readiness endpoint:
  - `GET /api/v1/admin/updates/readiness`.
- Public update manifests now expose safe artifact flags:
  - `fileReady`;
  - `publicHttpsReady`;
  - `configuredRequired`;
  - `releaseBlocked`;
  - `blockingReason`.
- If a required update is configured without a valid download URL and SHA256, backend suppresses the effective client `required` flag and marks the manifest blocked instead of risking a dead-end mandatory update.
- Published stable releases now require a public HTTPS download URL and SHA256 before they can be saved as `published`.
- `admin_support_app` -> `Обновления` now shows release readiness above the manifest preview.
- `admin_support_app` -> `Серверы` -> `Мониторинг endpoint` now has filters by endpoint id and health status; backend already supports those filters through `GET /api/v1/admin/server-health`.
- `scripts\windows\check_external_services_readiness.ps1` now checks protected update readiness during server-side admin self-check and downgrades local Windows/WSL HTTPS false negatives to yellow when server-side HTTPS/admin checks are green.
- Release gate now checks:
  - `GET /api/v1/admin/updates/readiness`;
  - `GET /api/v1/admin/updates/releases`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.18`;
  - OpenAPI lists update readiness/releases/public update manifest endpoints;
  - server-side protected update readiness returns `productionReady: false`, `fileReady: false`, `publicHttpsReady: false`, as expected until the final installer artifact is issued;
  - server-side protected `/api/v1/admin/server-health?endpointId=current_wg0&status=all&limit=5` and `/api/v1/admin/server-health?status=healthy&limit=5` return filtered observations;
  - local admin app HTTP `200` at `http://127.0.0.1:8090/`;
  - external readiness script now reports one real red owner-action (`_dmarc.greenvpn.pro`) and keeps local HTTPS path as yellow if server-side checks are green.
- No installer was rebuilt. The current instruction is final-only installer cadence.

## 2026-05-05 Support Trial Action

- Backend source and live server are now `0.9.19`.
- Added safe support action:
  - `grant_support_trial_3d`.
- The action:
  - requires a support reason;
  - grants or extends `support_trial` by 3 days;
  - does not overwrite an active paid subscription and returns `noop` instead;
  - writes to `admin_support_actions` and admin audit;
  - never exposes passwords, tokens, payment secrets or WireGuard private keys.
- `admin_support_app` support-action workflow fallback includes the new action and asks for confirmation when an action has `confirmationText`, even if it is not marked dangerous.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.19`;
  - protected support action workflow returns `actions: 7`, `hasSupportTrial3d: true`, `reasonRequired: 4`;
  - temp-DB smoke confirmed `grant_support_trial_3d` creates `support_trial` for a trial user and preserves an active paid subscription with `noop`;
  - `check_external_services_readiness.ps1 -SkipServerSelfCheck -ServerAdminSelfCheck -Json` shows protected admin self-check green; only DMARC remains a real red owner-action in this mode.
- No installer was rebuilt.

## 2026-05-05 Release Gate Safety Invariants

- No backend deploy was needed; live backend remains `0.9.19`.
- `scripts\windows\bluevpn_release_gate.ps1` now explicitly verifies key backend safety invariants, not just endpoint presence:
  - update artifact guard exists;
  - required update without artifact is blocked/suppressed;
  - published stable release requires public HTTPS download URL and SHA256;
  - `grant_support_trial_3d` exists;
  - active paid subscription preservation for support trial exists;
  - reason-required support action guard exists.
- Checks passed:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - server-local `/healthz` returns `version: 0.9.19`.
- No installer was rebuilt.

## 2026-05-05 Admin Support Assigned Filter

- No backend source version bump and no backend deploy were needed; live backend remains `0.9.19`.
- Separate `admin_support_app` support reports now have an `исполнитель` filter.
- The filter sends `assignedTo` to the existing protected `GET /api/v1/admin/support/reports` endpoint; backend filtering for `assigned_to` was already present.
- Checks passed:
  - local `admin_support_app` index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - local `admin_support_app\app.js` returns HTTP 200 from the same server;
  - static source check confirms `supportAssignedFilter` exists in HTML, request params and input reload listener;
  - static source check confirms backend route accepts `assignedTo` and passes it to `list_support_reports`.
- Full JS parser check was not rerun in this heartbeat shell because local `python` is not on PATH and the available WindowsApps `node.exe` returns access denied.
- No installer was rebuilt.

## 2026-05-05 Monitoring Service Observation Filters

- No backend source version bump and no backend deploy were needed; live backend remains `0.9.19`.
- Separate `admin_support_app` `Мониторинг -> Последние проверки сервисов` now has filters for:
  - `target id`;
  - observation status: green/yellow/red/unknown.
- The filters reuse the existing protected `GET /api/v1/admin/monitoring/service-observations` query params: `targetId`, `status`, `limit`.
- Checks passed:
  - local `admin_support_app` index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - local `admin_support_app\app.js` returns HTTP 200 from the same server;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No installer was rebuilt.

## 2026-05-05 Server Catalog Publication Filter

- No backend source version bump and no backend deploy were needed; live backend remains `0.9.19`.
- Separate `admin_support_app` `Серверы -> Управляемые серверы` now has an explicit publication filter:
  - all publication states;
  - public candidates;
  - internal endpoints.
- The filter reuses the existing protected `GET /api/v1/admin/server-catalog` query param `public`.
- Checks passed:
  - local `admin_support_app` index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No installer was rebuilt.

## 2026-05-05 Update Readiness Channel Filter

- No backend source version bump and no backend deploy were needed; live backend remains `0.9.19`.
- Separate `admin_support_app` update readiness now requests the selected release channel explicitly.
- The readiness cards reuse the existing protected `GET /api/v1/admin/updates/readiness` query params:
  - `platform=windows`;
  - `channel=<selected channel>`, falling back to `stable` when the release table filter is `all`.
- Checks passed:
  - local `admin_support_app` index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No installer was rebuilt.

## 2026-05-05 Support Report Redaction Hardening

- Backend source and live server are now `0.9.20`.
- Server-side `GVPN1.` support-report decode now uses broader redaction:
  - sensitive-looking keys are redacted through the shared telemetry key detector;
  - sensitive-looking text values are redacted through the shared telemetry value patterns;
  - nested dict/list payloads are depth/size bounded before support/admin display.
- Safe diagnostic fields such as user note, score, latency/status style values remain visible for support triage.
- Release gate now checks support-report client/backend invariants:
  - `POST /api/v1/support/reports`;
  - `GET /api/v1/admin/support/reports/{report_id}/decoded`;
  - user-app send-first flow;
  - fallback-copy code path after backend send failure;
  - backend decode redaction safety fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - local stubbed import smoke for support-report redaction;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.20`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - server-local support-report redaction smoke passed without printing secrets;
  - external readiness protected admin self-check remains green; `_dmarc.greenvpn.pro` is still the real red owner-action.
- `dart analyze lib\main.dart` was run and returned only existing warning/info debt, not a new compile error from this step.
- No installer was rebuilt.

## 2026-05-05 Server Catalog Auto-Pause Safety Gate

- Backend source and live server are now `0.9.21`.
- Managed server catalog now has an automatic public-candidate safety gate:
  - if a managed endpoint is marked `isPublic=true` and a fresh server-health observation is `down`/`degraded`;
  - or its computed health score falls below `GREENVPN_SERVER_PUBLIC_MIN_HEALTH_SCORE` (default `80`);
  - backend automatically clears `is_public`, stores `publication_paused_at`, `publication_paused_reason`, `publication_paused_by=health_gate`, and writes admin audit.
- This does not change the public Windows client catalog. `/api/v1/catalog/servers` still returns only the builtin `intelligent_smew` and `clientVisibleManagedEntries: 0`.
- Separate `admin_support_app` now shows `auto-paused` and the pause reason in the managed server table.
- Release gate now checks the auto-pause safety fragments so this guard cannot disappear silently.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.21`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - server-local temp-DB smoke confirmed a bad observation auto-pauses a public candidate and keeps public catalog unchanged;
  - external readiness protected admin self-check remains green; `_dmarc.greenvpn.pro` is still the real red owner-action.
- No installer was rebuilt.

## 2026-05-05 Support Config Refresh Apply

- Backend source and live server are now `0.9.22`.
- Support action `request_config_refresh` is now applied by the next successful `POST /api/v1/client/config`:
  - rotates the device client private/public keypair and preshared key;
  - keeps the assigned client IP when possible;
  - replaces the managed peer block for the same `deviceUid`;
  - applies the new live peer;
  - best-effort removes the old live peer by public key;
  - clears `support_config_refresh_requested_*`;
  - records `support_config_refresh_applied_at` and `support_config_refresh_applied_reason`;
  - writes admin audit event `support_config_refresh_applied` without exposing keys.
- Client config response now includes safe boolean `supportConfigRefreshApplied`.
- Separate `admin_support_app` user/device card now shows the last applied config-refresh time/reason.
- Release gate now checks support config-refresh apply fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.22`;
  - server-local temp-DB smoke confirmed first config fetch, support refresh request, second config fetch with key/PSK rotation, marker cleanup, old-peer removal call, and audit;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - external readiness protected admin self-check remains green; `_dmarc.greenvpn.pro` is still the real red owner-action.
- No installer was rebuilt.

## 2026-05-05 Admin Staff Session Management

- Backend source and live server are now `0.9.23`.
- Added owner/admin staff-session management:
  - `GET /api/v1/admin/staff/{staff_id}/sessions`;
  - `POST /api/v1/admin/staff/{staff_id}/sessions/revoke`;
  - `POST /api/v1/admin/staff/{staff_id}/sessions/revoke-all`.
- `GET /api/v1/admin/staff` now includes active/revoked/expired session counts and last session activity.
- Revoke-all preserves the current operator session when the operator revokes their own other sessions.
- Staff session operations write audit events:
  - `admin_staff_session_revoked`;
  - `admin_staff_sessions_revoked`.
- Separate `admin_support_app` `Команда` now shows staff session counts, session inventory, single revoke, and revoke-all controls. Raw session tokens are never returned; only short public session ids are shown.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.23`;
  - server-local temp-DB smoke confirmed session list, single revoke, revoke-all, current-session preservation, and audit;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-05 Readiness Self-Check Staff Sessions Coverage

- No backend deploy was needed; live backend remains `0.9.23`.
- `scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck` now also verifies:
  - protected `GET /api/v1/admin/staff`;
  - safe `GET /api/v1/admin/staff/{staff_id}/sessions` for the first staff record when present;
  - OpenAPI route inventory for staff-session revoke/revoke-all endpoints without mutating live sessions.
- The check confirms raw session tokens are not exposed in staff session payloads.
- Checks passed:
  - `check_external_services_readiness.ps1 -SkipServerSelfCheck -ServerAdminSelfCheck -Json`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`.
- External readiness still has the same owner-action blockers: `_dmarc.greenvpn.pro`, monitoring VPS/fresh probe coverage, final update artifact URL/SHA256, provider credentials.
- No installer was rebuilt.

## 2026-05-05 Incident Runbook Suggestions

- Backend source and live server are now `0.9.24`.
- Internal incident payloads now include safe `suggestedRunbooks`:
  - suggestions are selected from active admin runbooks by incident title/source/service/endpoint/summary;
  - matching categories cover payments, auth, VPN/WireGuard, servers/API/catalog, monitoring/service probes, updates, and fallback incident/general;
  - only runbook metadata/checklists already stored in admin runbooks are returned, no secrets or raw tokens.
- Separate `admin_support_app` now shows suggested runbook pills directly under incident title/summary in `Инциденты`.
- Release gate now checks that incident runbook suggestion support remains present.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.24`;
  - server-local temp-DB smoke confirmed payment, monitoring, and API/server incidents receive relevant runbook suggestions;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-05 Incident Staff Assignment

- Backend source and live server are now `0.9.25`.
- Incidents now support structured staff assignment:
  - `assigneeStaffId`;
  - `assignedAt`;
  - `assignedBy`;
  - assignment history in sanitized incident `details`.
- Added protected endpoint `GET /api/v1/admin/incidents/assignees`, requiring `incidents.read`, so support roles can see safe active assignee options without needing full `staff.manage`.
- `GET /api/v1/admin/incidents` now supports `assignee` filter and returns safe `assignees` options for the admin UI.
- Separate `admin_support_app` incident table now has:
  - assignee filter;
  - per-incident assignment dropdown;
  - `В работу` / `Решено` / `Открыть` actions that assign to the current staff session when available.
- Release/readiness gates now cover the assignee endpoint and `assigneeStaffId` invariant.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.25`;
  - server-local temp-DB smoke confirmed active owner/support assignees, readonly/inactive exclusion, assignment, clear, assignment history, and assignee filter;
  - protected readiness self-check confirmed `/api/v1/admin/incidents/assignees` returns staff ids and no raw token exposure;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-05 Incident Alert Outbox/History

- Backend source and live server are now `0.9.26`.
- Added internal `admin_alert_events` storage for incident alert attempts.
- New high/critical incidents now record a sanitized alert event even when Telegram is not configured:
  - current no-secret mode records `status=skipped`, `provider=manual_mvp`, `error=telegram_alerts_not_configured`;
  - when Telegram env is configured later, the same path records `sent` or `failed`;
  - low-severity noise below the configured alert threshold does not create alert events.
- Added protected endpoint `GET /api/v1/admin/alerts/events`, requiring `incidents.read`.
- Separate `admin_support_app` readiness section now shows recent incident alert history.
- Readiness self-check now verifies the alert-events endpoint without exposing admin token.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.26`;
  - server-local temp-DB smoke confirmed skipped/manual MVP event for critical incident and no event for low-severity noise;
  - protected readiness self-check confirmed `/api/v1/admin/alerts/events?limit=5` responds and no raw token is exposed;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-05 Updater Release Publication Gate

- Backend source and live server are now `0.9.27`.
- Added per-release `releaseReadiness`:
  - `canPublish`;
  - artifact readiness;
  - public HTTPS readiness;
  - blockers;
  - warnings.
- Published releases are now blocked by a single publication gate with explicit blockers such as `artifact_missing`, `stable_requires_public_https`, and `required_update_without_artifact`.
- `GET /api/v1/admin/updates/readiness` now includes `latestReleaseReadiness` and a `release_publication_gate` check.
- Separate `admin_support_app` update/release table now shows gate ready/blocked state and first blockers/warnings for each release; blocked publish buttons are disabled client-side, with backend still authoritative.
- Release gate now checks the publication-gate fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.27`;
  - server-local temp-DB smoke confirmed draft without artifact is allowed but blocked for publish, publish without artifact returns HTTP `400`, publish with public HTTPS URL + SHA256 gets `releaseReadiness.canPublish=true`, and manifest can expose the release;
  - protected readiness self-check remains green for admin endpoints; update readiness still waits for final artifact URL/SHA256;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-05 Server Catalog Provisioning Readiness

- Backend source and live server are now `0.9.28`.
- Added protected admin-only `GET /api/v1/admin/server-catalog/provisioning-readiness`.
- The new gate documents and checks the `serverId` contract for `/api/v1/client/config`:
  - accepted client ids are only `auto` and public catalog ids, currently `intelligent_smew`;
  - managed `current_wg0` can be config-ready internally but remains blocked from direct client selection;
  - public catalog remains unchanged and still reports `clientVisibleManagedEntries: 0`;
  - multi-endpoint provisioning remains explicitly locked until separate peer/config rules, probes and rollout gates exist.
- Separate `admin_support_app` now shows a `Provisioning gate` card and blocked `serverId` selection cases in the Server Catalog summary.
- Release/readiness gates now cover the new provisioning readiness endpoint and contract fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.28`;
  - server-local temp-DB smoke confirmed `current_wg0` seeds as `clientConfigReady=true`, stays `isPublic=false`, and is not accepted by client `serverId`;
  - protected readiness self-check confirmed provisioning readiness with `safeForCurrentClient=true`, `currentEndpointConfigReady=true`, `multiEndpointProvisioningReady=false`, accepted ids `auto,intelligent_smew`, and no managed client visibility;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-06 Support Report Review Workflow

- Backend source and live server are now `0.9.29`.
- Support reports now have explicit review/first-response metadata:
  - `reviewedAt`;
  - `reviewedBy`;
  - `reviewPending`.
- Added protected endpoint `POST /api/v1/admin/support/reports/{report_id}/review`, requiring `support.manage`.
- Review action:
  - moves `new`/`triage` reports to `in_progress`;
  - sets `firstResponseAt` safely once;
  - assigns the current support operator if no assignee exists;
  - writes `support_report_reviewed` audit without report contents or secrets.
- Existing status update now preserves `assignedTo` when quick actions such as `Решено` do not send an assignee.
- Separate `admin_support_app` support report list/detail now shows review state and has a quick `В работу` action.
- Release/readiness gates now cover the review endpoint and OpenAPI route.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.29`;
  - server-local temp-DB smoke confirmed review metadata, first response, assignee preservation after resolve, and decoded-report redaction;
  - protected readiness self-check confirmed the review route is present and no admin token is exposed;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-06 Auth Code Verify Lockout

- Backend source and live server are now `0.9.30`.
- Email-code and phone/SMS-code verification now have bounded attempts:
  - `GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS`, default `5`;
  - `GREENVPN_AUTH_CODE_LOCKOUT_MINUTES`, default `15`;
  - per-code `attempts_count`, `last_attempt_at`, and `locked_until`.
- After too many wrong attempts backend returns `too_many_attempts` with HTTP `429`; even the correct code is rejected until lockout expires.
- Lockout does not expose the real code, provider secrets, SMTP/SMS secrets, tokens, or private keys.
- `auth_code_readiness()` now reports max verify attempts and lockout minutes.
- Separate `admin_support_app` `Входы` filter now includes `Лимит попыток` / `too_many_attempts`.
- Release gate now checks auth-code lockout fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.30`;
  - server-local temp-DB smoke confirmed email-code and phone-code lockout after repeated invalid codes;
  - protected readiness self-check remains green for admin endpoints;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No installer was rebuilt.

## 2026-05-06 External Owner Setup Bundle

- Backend source and live server are now `0.9.31`.
- `GET /api/v1/admin/external-actions` now includes a safe `setupBundle` for owner handoff:
  - server-only apply command for `configure_backend_env_wsl.ps1`;
  - readiness command for `check_external_services_readiness.ps1 -ServerAdminSelfCheck`;
  - expected non-secret DNS records, including `_dmarc.greenvpn.pro`;
  - safe default env values for public API URLs, YooKassa URLs and auth-code lockout settings.
- Each external owner action now includes structured `ownerInputs`, `applySteps` and `verifySteps` so the admin app can show exactly what data is needed without storing secrets.
- `configure_backend_env_wsl.sh` now applies auth-code lockout env defaults when rotating the auth-code pepper:
  - `GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS=5`;
  - `GREENVPN_AUTH_CODE_LOCKOUT_MINUTES=15`.
- `check_external_services_readiness.ps1` now includes expected DNS details for missing/mismatched DNS records and verifies the external-actions setup metadata during server-side admin self-check.
- Separate `admin_support_app` owner checklist now renders the setup bundle, owner input chips, apply steps and verify steps.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.31`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - protected server-side self-check confirmed setup bundle, 8 owner-input action groups, 8 verify-step action groups and 5 DNS records without exposing admin token.
- External readiness remains blocked only by owner-action items: DMARC TXT, final update artifact/SHA256, real monitoring VPS probe, Telegram bot/chat id, SMTP/SMS/YooKassa production data.
- No installer was rebuilt.

## 2026-05-06 Monitoring Probe Install Bundle

- Backend source and live server are now `0.9.32`.
- `GET /api/v1/admin/monitoring/readiness` now includes `readiness.installBundle` for the external monitoring VPS:
  - default `probe-eu-1` / `eu` install command;
  - `--token-stdin` token handoff;
  - server-only token path `/etc/greenvpn-monitoring/admin_token`;
  - required target ids for API/YouTube/Discord/Telegram coverage;
  - owner inputs, apply steps and verify steps.
- Separate `admin_support_app` monitoring agents panel now renders the external probe install bundle and required targets.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now verifies the monitoring install bundle and that the install command uses `--token-stdin`.
- Release gate now checks the monitoring probe install bundle fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.32`;
  - protected server-side smoke confirmed `installBundle`, 5 required targets, `--token-stdin`, `/etc/greenvpn-monitoring/admin_token`, and `productionReady=false` until owner provides a separate VPS;
  - live public `/api/v1/catalog/servers` remains builtin-only and hides managed endpoints.
- No monitoring VPS was installed because owner must provide host/SSH access/admin-token handoff.
- No installer was rebuilt.

## 2026-05-06 Billing Reconciliation Guard

- Backend source and live server are now `0.9.33`.
- Added protected `GET /api/v1/admin/billing/reconciliation`, requiring `billing.read`.
- `GET /api/v1/admin/billing/orders` now returns `reconciliation` summary alongside the order list.
- Reconciliation flags safe admin-only attention cases:
  - `paid_not_activated`;
  - `paid_at_without_activation`;
  - `activated_status_without_timestamp`;
  - `activation_timestamp_status_mismatch`;
  - `stale_pending_order`;
  - `yookassa_payment_not_created`;
  - `terminal_order_has_payment_markers`.
- Manual `mark-paid` activation now refuses `failed` / `canceled` / `cancelled` orders with HTTP `409`; normal pending manual activation still works and remains audited.
- Separate `admin_support_app` payments section now shows a billing reconciliation card with issue counts and attention order preview.
- External readiness protected self-check now covers billing reconciliation and verifies that a manual activation policy is present.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed paid-not-activated/stale-pending detection, canceled-order activation guard, and normal pending activation;
  - live `/healthz` returns `version: 0.9.33`;
  - live `/api/v1/admin/billing/reconciliation` responds without exposing secrets; current real DB shows 8 orders and 4 medium attention items, mostly old pending orders;
  - live public `/api/v1/catalog/servers` remains builtin-only and hides managed endpoints.
- No installer was rebuilt.

## 2026-05-06 Update Rollback Publication Guard

- Backend source and live server are now `0.9.34`.
- Added updater rollback readiness for admin-managed releases:
  - `releaseReadiness.rollbackReadiness` is included on release payloads;
  - `GET /api/v1/admin/updates/readiness` now includes top-level `rollbackReadiness`;
  - stable `rolloutPercent >= 100` or `isRequired=true` publication is blocked with `rollback_artifact_missing` until a previous published stable release or `GREENVPN_ROLLBACK_*` public HTTPS artifact is ready;
  - staged stable rollout below 100% can still publish, but gets `rollback_missing_for_staged_rollout` and is not production-ready.
- `configure_backend_env_wsl.sh` can now apply final update artifact env and rollback artifact env when the owner has final URLs/SHA256 values.
- Separate `admin_support_app` update cards now show rollback status in update readiness, manifest summary and release table.
- External readiness protected self-check now verifies the updater rollback readiness block without exposing admin token.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed full/required stable release is blocked without rollback, staged rollout is allowed with warning, and full rollout succeeds after a previous published rollback candidate exists;
  - live `/healthz` returns `version: 0.9.34`;
  - live protected `/api/v1/admin/updates/readiness` reports `rollbackReady=false`, `source=none`, `published_release_missing` until final release/rollback artifact exists;
  - live public `/api/v1/catalog/servers` remains builtin-only and hides managed endpoints.
- No installer was rebuilt.

## 2026-05-06 Owner Action Audit Guard

- Backend source and live server are now `0.9.35`.
- External owner-action workflow now has an explicit note policy:
  - `waiting_owner`, `waiting_provider`, `ready_to_apply`, `blocked`, and `not_needed` require a safe owner note;
  - manual `done` before backend readiness is green also requires a safe owner note;
  - notes must not contain secrets, admin tokens, passwords or provider keys.
- `GET /api/v1/admin/external-actions` now returns:
  - `ownerActionPolicy`;
  - `blockingSummary`;
  - `doneButBackendNotReadyCodes`;
  - `missingOwnerNoteCodes`;
  - `safeToProceed`.
- Separate `admin_support_app` owner checklist now shows owner-action audit summary and note policy.
- External readiness protected self-check now verifies owner-action policy and blocking summary metadata.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed note-required guard for manual `done`/waiting statuses and detection of `done` while backend readiness is still not green;
  - live `/healthz` returns `version: 0.9.35`;
  - live protected `/api/v1/admin/external-actions` returns policy/blocking summary with pending codes `email`, `sms`, `payments`, `updates`, `admin_alerts`;
  - live public `/api/v1/catalog/servers` remains builtin-only and hides managed endpoints.
- No installer was rebuilt.

## 2026-05-06 Support SLA Queue

- Backend source and live server are now `0.9.36`.
- Added protected `GET /api/v1/admin/support/sla`, requiring `support.read`.
- Support report payloads now include derived admin fields:
  - `slaStatus` (`overdue`, `due_soon`, `ok`, `missing`, `closed`);
  - `firstResponseMissing`.
- SLA dashboard returns:
  - open/overdue/due-soon/missing-SLA counts;
  - first-response-missing count;
  - review-pending count;
  - `attentionQueue` for the operator's first triage pass.
- Separate `admin_support_app` support section now shows compact SLA queue cards above the support report table.
- External readiness protected self-check now covers `/api/v1/admin/support/sla`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed overdue/due-soon/ok SLA status derivation, first-response-missing counts and attention queue;
  - live `/healthz` returns `version: 0.9.36`;
  - live protected `/api/v1/admin/support/sla` responds and currently shows 2 open reports requiring attention due missing SLA/first-response metadata;
  - live public `/api/v1/catalog/servers` remains builtin-only and hides managed endpoints.
- No installer was rebuilt.

## 2026-05-06 Support SLA Backfill

- Backend source and live server are now `0.9.37`.
- Added startup backfill for legacy support reports that were created before the current workflow fields existed.
- Backfill fills only empty fields and does not overwrite operator decisions:
  - `priority`;
  - `category`;
  - `triage_reason`;
  - `sla_due_at`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed a legacy support report gets priority/category/SLA without overwriting existing values;
  - live `/healthz` returns `version: 0.9.37`;
  - live protected `/api/v1/admin/support/sla` now reports `missingSla=0`; the two old open reports are correctly visible as `overdue`, `firstResponseMissing`, and `reviewPending`;
  - protected server-side readiness self-check remains green for admin endpoints except expected external owner blockers.
- No installer was rebuilt.

## 2026-05-06 Billing Renewal Readiness Guard

- Backend source and live server are now `0.9.38`.
- Added protected `GET /api/v1/admin/billing/renewals/readiness`, requiring `billing.read`.
- The new renewal readiness dashboard is dry-run only:
  - shows auto-renew subscriptions due in the configured window;
  - flags missing saved provider payment method;
  - flags existing pending auto-renew orders to prevent duplicate renewal attempts;
  - blocks auto-renew charges while YooKassa production readiness is not green;
  - returns only `hasProviderPaymentMethod` and does not expose provider payment method ids.
- Separate `admin_support_app` payments section now shows an auto-renewal readiness card next to billing reconciliation.
- External readiness protected self-check now covers `/api/v1/admin/billing/renewals/readiness` and verifies that payment method ids are not exposed.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed missing-method and pending-order blockers, dry-run mode, and no method id exposure;
  - live `/healthz` returns `version: 0.9.38`;
  - live protected `/api/v1/admin/billing/renewals/readiness` reports 3 auto-renew subscriptions, 0 due within the window, 1 pending-order conflict, production payments not ready, and no payment method id exposure;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json` reports protected admin self-check green.
- During the first renewal smoke, the backend's fixed `DATA_DIR` meant two `example.test` rows were created in the live DB. They were immediately removed with an exact-match cleanup: 2 users, 2 subscriptions, 1 test order. The successful smoke was then rerun with an explicit temp `DB_PATH`.
- No installer was rebuilt.

## 2026-05-06 Subscription Expiry Readiness Guard

- Backend source and live server are now `0.9.39`.
- Added safe backend data-dir override for tests:
  - default remains `/opt/bluevpn/backend/data`;
  - tests can now set `BLUEVPN_DATA_DIR` before importing the backend, preventing accidental writes to the live DB.
- Added protected `GET /api/v1/admin/subscriptions/expiry-readiness`, requiring `billing.read`.
- The endpoint is readiness-only and does not enforce subscription expiry:
  - reports latest subscriptions;
  - flags active subscriptions whose `expires_at` is already in the past;
  - flags paid subscriptions expiring soon without auto-renew;
  - flags expiring subscriptions without verified email/phone for retention contact;
  - flags expiring auto-renew subscriptions blocked by payment readiness, missing method, or pending renewal order;
  - returns only `hasProviderPaymentMethod`, never raw provider payment method ids.
- Separate `admin_support_app` users/subscriptions section now shows a subscription expiry readiness card.
- External readiness protected self-check now covers `/api/v1/admin/subscriptions/expiry-readiness`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed `BLUEVPN_DATA_DIR` isolation, expired-active detection, expiring-manual detection, auto-renew payment readiness block, and no method id exposure;
  - live `/healthz` returns `version: 0.9.39`;
  - live protected expiry readiness reports 29 latest subscriptions, 10 active now, 19 expired with active flag, 3 expiring in the window, 3 missing retention contact, `safeToEnableExpiryEnforcement=false`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json` reports protected admin self-check green and includes expiry readiness.
- No installer was rebuilt.

## 2026-05-06 Expired Trial Subscription Backfill

- Backend source and live server are now `0.9.41`.
- Added startup `backfill_expired_non_paid_subscriptions()`:
  - sets `is_active=0` only for expired non-paid plan codes (`trial`, `support_trial`, and the default non-paid plan);
  - does not touch paid plans such as `pro`, even if they are expired;
  - keeps the production default data path unchanged and remains compatible with `BLUEVPN_DATA_DIR` temp smokes.
- Subscription expiry readiness semantics were tightened:
  - `summary.expired` now means expired subscriptions that still have `is_active=1`;
  - `summary.expiredTotal` shows historical inactive expired rows for context;
  - inactive expired trial rows no longer force attention by themselves.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed expired trial rows are deactivated while expired paid rows remain active for manual review;
  - live `/healthz` returns `version: 0.9.41`;
  - live protected expiry readiness now reports `expired=0`, `expiredTotal=19`, `expiringWithinWindow=3`, `blockedExpiring=3`, `missingRetentionContact=3`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json` reports protected admin self-check green.
- No installer was rebuilt.

## 2026-05-06 External Endpoint Probe Readiness

- Backend source and live server are now `0.9.42`.
- Added external server-health probe readiness:
  - `GET /api/v1/admin/server-health` now includes `externalProbeReadiness`;
  - required endpoint coverage is based on active config-ready managed endpoints, currently `current_wg0`;
  - backend separates server-local `backend-local` probes from external monitoring VPS probes;
  - production endpoint readiness stays blocked until a separate external probe sends fresh healthy observations for `current_wg0`.
- Updated controlled monitoring probe tooling:
  - `scripts/monitoring/service_probe.py` supports `--server-health`;
  - the probe still posts service availability observations, and can also post safe endpoint health observations to `POST /api/v1/admin/server-health/observations`;
  - endpoint observations include DNS/API/UDP-route/config-readiness signals only, with no tokens, passwords, WireGuard private keys or configs;
  - `scripts/monitoring/install_probe_systemd.sh` enables server-health observations by default and supports `--no-server-health` if needed.
- Updated separate `admin_support_app`:
  - `Серверы -> Наблюдения здоровья` shows external endpoint probe count and required endpoint coverage.
- Updated readiness/release checks:
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck` verifies `/api/v1/admin/server-health` and confirms the probe install bundle contains both `--token-stdin` and `--server-health`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate` guards the new endpoint-observation path and external probe readiness fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bash -n scripts/monitoring/install_probe_systemd.sh`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.42`;
  - live protected server-health summary reports required endpoint `current_wg0`, missing external coverage as expected, and public catalog unchanged;
  - `service_probe.py --server-health --dry-run` checked `production_api_healthz` and `current_wg0` without posting live observations;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json` reports protected admin self-check green; remaining blockers are still owner/external items such as DMARC and real monitoring VPS.
- No installer was rebuilt.

## 2026-05-06 Server Health Incident Sync

- Backend source and live server are now `0.9.43`.
- Server health observations now synchronize internal incidents:
  - degraded/down or `ok=false` endpoint observations open/reopen `server-health:<endpointId>` incidents;
  - `down` becomes high severity, `degraded` becomes medium severity;
  - healthy observations resolve the matching server-health incident.
- This connects endpoint health scoring with the existing incident dashboard, runbook suggestions and alert outbox without exposing it in the normal VPN client.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed degraded endpoint observation opens a medium `server_health_observation` incident and a later healthy observation resolves it;
  - live `/healthz` returns `version: 0.9.43`;
  - live protected check shows no open server-health incidents and external endpoint readiness still correctly blocked until a real monitoring VPS covers `current_wg0`.
- No installer was rebuilt.

## 2026-05-06 Admin Staff Password/Session Guard

- Confirmed existing staff self-service security flow:
  - `POST /api/v1/admin/auth/password/change`;
  - `GET /api/v1/admin/auth/sessions`;
  - `POST /api/v1/admin/auth/sessions/revoke`;
  - `POST /api/v1/admin/auth/sessions/revoke-others`.
- The separate `admin_support_app` already has the current-password/new-password form and other-session revoke action on the overview screen.
- Hardened checks so this does not regress:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate` now requires the self-service password/session endpoints and audit fragments;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now verifies these routes are present in OpenAPI route inventory.
- Checks passed:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - protected external readiness route inventory reports `routesPresent=true`.
- No backend redeploy was needed beyond live `0.9.43`, and no installer was rebuilt.

## 2026-05-06 SMTP/Yandex 360 Owner Setup

- Owner created Yandex 360 mailboxes `no-reply@greenvpn.pro`, `support@greenvpn.pro`, and `postmaster@greenvpn.pro`.
- Owner created a Yandex application password for `no-reply@greenvpn.pro`.
- Applied SMTP env to the server via `scripts\windows\configure_backend_env_wsl.ps1`; the secret was entered only into the local hidden prompt and was not written to repo/docs/chat.
- Backend restarted successfully and `/healthz` reports:
  - `emailProductionReady=true`;
  - `emailConfirmationRequired=false`;
  - `smsProductionReady=false`;
  - `paymentsProductionReady=false`.
- External readiness check reports `red=0`, with DNS MX/SPF/DKIM/DMARC green and protected server-side admin checks green.
- Real email-code send test to `support@greenvpn.pro` returned `deliveryStatus=failed`; server DB error for the latest outbox row is `[Errno 113] No route to host`.
- Server connectivity test shows outbound TCP to `smtp.yandex.ru` on ports `25`, `465`, and `587` fails with `No route to host`, while ping/HTTPS to Yandex works and local server firewall output policy is `ACCEPT`.
- Owner created Timeweb support ticket `11901262`; waiting for provider to unblock outbound SMTP submission to `smtp.yandex.ru` on ports `465` and `587`, or provide an approved SMTP relay/API over an allowed port.
- No installer was rebuilt.

## 2026-05-06 SMS.ru Owner Setup

- Owner copied SMS.ru `api_id` through the safe env prompt; the value was not written to repo/docs/chat.
- `scripts\configure_backend_env_wsl.sh` was hardened:
  - `SMS.ru api_id` is now required and cannot be accidentally accepted as empty;
  - backend restart health check now retries for up to 20 seconds instead of failing on the first post-restart moment.
- Applied SMS env to `/etc/bluevpn/backend.env`, restarted backend, and cleaned the accidental sender-name value `y`; `GREENVPN_SMS_FROM` is intentionally unset until a real `GreenVPN` sender is approved.
- Backend `/healthz` now reports:
  - `smsProductionReady=true`;
  - `authCodeProductionReady=true`.
- Protected `/api/v1/admin/sms/readiness` reports `provider=smsru`, `deliveryReady=true`, `productionReady=true`, `testMode=false`, and no required actions.
- External actions checklist marks `SMS.ru для входа по телефону` as done. Real paid delivery/balance test remains an operational owner check because the SMS.ru dashboard currently shows zero balance.
- No installer was rebuilt.

## 2026-05-06 Business/Pricing Strategy

- Added `C:\Users\gekto\projects\bluevpn\docs\BUSINESS_PRICING_STRATEGY_RU.md`.
- This is now the release-facing business reference for:
  - public positioning as protected/stable connection and app-route quality, not "block bypass";
  - YooKassa/product description wording;
  - starter legal/tax path through self-employed status, with IP transition before scale;
  - server economics for 200 Mbps and 1 Gbps VPN nodes;
  - public tariff recommendation before release.
- Important: current backend tariff prices are still a technical/test catalog. Before public launch, prefer:
  - trial 1-3 days or 3-5 GB;
  - `Старт` 149 RUB/month;
  - `Стандарт` 299 RUB/month as the main plan;
  - `Плюс` 449 RUB/month;
  - `Максимум` 699 RUB/month with fair-use instead of unlimited-without-limits.
- Do not sell or market "обход блокировок", "разблокировка", "анонимайзер" or named blocked-service access. Use security, stability, protected connection, public Wi-Fi protection, app-route quality, diagnostics and support.

## 2026-05-06 YooKassa Legal Pages

- Backend source version bumped to `0.9.44` and deployed on `37.220.85.211`.
- Added public pages on `https://api.greenvpn.pro` for YooKassa review:
  - `/` landing/product overview;
  - `/legal/requisites`;
  - `/legal/offer`;
  - `/legal/privacy`;
  - `/legal/acceptable-use`;
  - `/legal/refunds`.
- Owner-provided public self-employed requisites were applied through the safe server env prompt and stored only in `/etc/bluevpn/backend.env`; do not copy personal data into repo/docs/chat.
- Verified `https://api.greenvpn.pro/legal/requisites` server-side: page contains Green VPN service description, masked self-employed INN field, and `support@greenvpn.pro`.
- For the current YooKassa questionnaire, use:
  - site URL `https://api.greenvpn.pro`;
  - requisites URL `https://api.greenvpn.pro/legal/requisites`;
  - login/password empty;
  - monthly turnover over 5M RUB unchecked.
- Root `https://greenvpn.pro` still points to REG.RU parking, so do not use it for YooKassa until DNS/site hosting is switched.
- No public Windows installer was rebuilt.

## 2026-05-06 YooKassa Pause: Waiting For NPD Status

- Owner registered in the FNS "Мой налог" flow; the cabinet accepted the registration request.
- Official public NPD status check on `npd.nalog.ru/check-status` still reports no active NPD status for today, so YooKassa correctly refuses the self-employed connection for now.
- YooKassa is paused until FNS confirms active self-employed/NPD status.
- Once status is active, continue YooKassa questionnaire with:
  - payment flow: website payments;
  - site URL `https://api.greenvpn.pro`;
  - requisites URL `https://api.greenvpn.pro/legal/requisites`;
  - business activity: `Информационные услуги`, subtype `Другое`;
  - bank details entered manually from the owner's bank account requisites;
  - then submit application for YooKassa review.
- Do not store owner passport, bank account, INN, or other personal details in repo/docs/chat.
- No public Windows installer was rebuilt.

## 2026-05-06 Billing Promotions Candidate

- Backend source version bumped to `0.9.45`.
- Backend `0.9.45` deployed on `37.220.85.211`.
- Added billing promo/action groundwork:
  - `promo_codes` and `promo_redemptions` tables;
  - promo-aware `/api/v1/subscription/quote`;
  - strict promo validation when creating a billing order;
  - billing order fields for original amount, discount amount and promo code;
  - one-time redemption accounting when a paid order activates the subscription.
- Added admin endpoints:
  - `GET /api/v1/admin/billing/promos`;
  - `POST /api/v1/admin/billing/promos`;
  - `POST /api/v1/admin/billing/promos/{code}/activate`;
  - `POST /api/v1/admin/billing/promos/{code}/deactivate`.
- Separate `admin_support_app` now has an internal promotions panel in the payments/orders section: create/edit promo code, percent/fixed discount, usage limit, active window, tariff scope, notes, enable/disable.
- YooKassa remains paused until FNS public NPD status becomes active; promo logic does not enable real production charges by itself.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - static admin app id/reference scan for new promo fields;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.45`;
  - protected admin promos endpoint returns safely;
  - server-local quote smoke handles an unknown promo as `not_found`;
  - server-local temp-DB smoke confirmed a percent promo discounts a base quote without touching production DB.
- `node.exe` is still blocked by Windows `Access is denied` in this desktop session, so JS syntax could not be checked with Node here.
- No public Windows installer was rebuilt.

## 2026-05-06 Promotions Strategy Note

- YooKassa remains paused until FNS/NPD status becomes active; this is an external owner/provider blocker, not a backend blocker.
- Updated `docs/BUSINESS_PRICING_STRATEGY_RU.md` with the launch promo policy:
  - limited first-month discounts such as `START20` / `FRIEND`;
  - internal compensation promo only with a support reason;
  - no lifetime deals, no permanent heavy discounts, no promo language about bypassing blocks.
- Promo orders must keep original amount, discount amount and promo code for reconciliation, support and future tax/payment review.
- Next productive work while waiting: public site/download buttons, final neutral product wording, legal/payment readiness, admin checks and monitoring.

## 2026-05-06 Public Download Pages Candidate

- Backend source and live server are now `0.9.46`.
- Public `https://api.greenvpn.pro/` now has a download section and clear buttons:
  - `/download/windows`;
  - `/download/android`;
  - `/download/ios`.
- No new installer was built or published. The Windows download route is ready to redirect once `GREENVPN_PUBLIC_WINDOWS_DOWNLOAD_URL` or `GREENVPN_UPDATE_URL` is configured after the final installer/release gate.
- Android/iOS pages are present as roadmap placeholders and do not promise an available app before Windows MVP is stable.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - backend deploy to `37.220.85.211`;
  - server-side `https://api.greenvpn.pro/healthz` returns `version: 0.9.46`;
  - server-side landing/download page smokes confirmed `Скачать для Windows`, `Android готовится`, and `/download/windows` pending-copy render.
- YooKassa remains paused until FNS public NPD status becomes active.
- No public Windows installer was rebuilt.

## 2026-05-07 API/VPN Endpoint Split Blocker

- Local Windows diagnosis while `AmneziaWGTunnel$device20_full` was active:
  - `api.greenvpn.pro` resolves to `37.220.85.211`;
  - active default route goes through `device20_full`;
  - `37.220.85.211/32` has a special bypass route through physical `Ethernet`;
  - browser access to `https://api.greenvpn.pro` fails with `ERR_NETWORK_ACCESS_DENIED`;
  - server-side `https://api.greenvpn.pro/healthz` remains healthy and returns backend `0.9.46`.
- Root cause: the public API/site shares the same public IP as the active WireGuard/Amnezia endpoint. Windows/WireGuard must bypass the tunnel for the endpoint IP, and firewall/leak-protection can block normal browser HTTPS to that same IP while the tunnel is active.
- This is not a backend outage and not a YooKassa/site-content issue.
- Production requirement before public client release: put `api.greenvpn.pro`/public site on a different public IP from VPN endpoints, or put VPN endpoints on separate `nl1.vpn.greenvpn.pro`/country hosts with different IPs. One IP must not serve both the API/site and the full-tunnel endpoint for the same Windows machine.
- Until the split exists, test `https://api.greenvpn.pro` with that Amnezia/Friendly Linnet tunnel disabled, or through a VPN endpoint that is not `37.220.85.211`.
- Added a release-readiness guard in `scripts/windows/check_external_services_readiness.ps1`: it now reports `API/VPN endpoint split` as red when the API/public site resolves to the same IP as the VPN endpoint. Syntax check passed under Windows PowerShell 5.1, and the current readiness run correctly flags the overlap between `api.greenvpn.pro` and `37.220.85.211`.

## 2026-05-07 Public Site Cleanup And Split Readiness

- Backend source/live server are now `0.9.48`; `/healthz` reports `service: Green VPN Backend`.
- Public site/download pages on `https://api.greenvpn.pro` no longer expose MVP/release-gate wording to users:
  - Windows page says the installer link will appear after final build verification;
  - Android/iOS pages are neutral future download pages, not internal technical placeholders.
- Added protected admin network readiness endpoint: `GET /api/v1/admin/network/readiness`.
- Product/admin readiness now includes API/VPN endpoint separation status.
- Safe server-only env cleanup applied on `37.220.85.211` for public URL keys only:
  - `GREENVPN_PUBLIC_API_BASE_URL=https://api.greenvpn.pro`;
  - `GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro`;
  - `GREENVPN_EMAIL_PUBLIC_BASE_URL=https://api.greenvpn.pro`;
  - `GREENVPN_API_BASE_URLS=https://api.greenvpn.pro`;
  - YooKassa return/webhook URLs on `https://api.greenvpn.pro`.
- No secrets were read or printed; `/etc/bluevpn/backend.env` contents were not output.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `scripts/windows/check_external_services_readiness.ps1`;
  - `bash -n scripts/configure_backend_env_wsl.sh`;
  - backend deploy/restart on `37.220.85.211`;
  - server-local `/healthz` returns version `0.9.48`;
  - external readiness self-check: green `9`, yellow `2`, red `1`.
- Remaining red item is expected: `api.greenvpn.pro` still resolves to `37.220.85.211`, the same IP as the VPN endpoint. Production launch needs a separate API/site IP or reverse proxy, while the VPN endpoint should move to a country host such as `nl1.vpn.greenvpn.pro -> 37.220.85.211`.
- No public Windows installer was rebuilt.

## 2026-05-07 Admin Staff 2FA

- Backend source/live server are now `0.9.49`.
- Added email-based two-factor login for the separate internal admin/support app:
  - staff with `twoFactorEnabled=true` now receives a pending challenge instead of an immediate session after password login;
  - 2FA codes are hashed server-side and stored only as hashes;
  - challenge expiry, max attempts, used/failed/expired states and audit events are recorded;
  - delivery uses the configured SMTP channel and never prints the code to logs/chat/docs.
- Added protected admin endpoints:
  - `POST /api/v1/admin/auth/2fa/verify`;
  - `GET /api/v1/admin/auth/2fa/readiness`.
- Product readiness now includes `admin_2fa`; external readiness self-check verifies the 2FA readiness route.
- Separate `admin_support_app` now supports:
  - pending 2FA code panel on staff login;
  - cancel/retry of pending 2FA login;
  - staff-level 2FA checkbox in `Команда`;
  - 2FA state in staff table and account security block.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - Chrome headless smoke for `admin_support_app\index.html` found no `SyntaxError`, `ReferenceError`, `TypeError` or uncaught JS errors;
  - PowerShell parse check for `scripts/windows/check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.49`;
  - external readiness self-check: green `9`, yellow `2`, red `1`.
- Remaining red item is still the expected API/VPN endpoint split blocker. No public Windows installer was rebuilt.

## 2026-05-07 Launch Readiness Aggregator

- Backend source/live server are now `0.9.50`.
- Added protected admin endpoint `GET /api/v1/admin/launch/readiness`.
- The new launch readiness payload aggregates:
  - product readiness checks;
  - API/VPN endpoint split;
  - YooKassa/payment readiness;
  - final installer/update/rollback readiness;
  - server catalog/provisioning readiness;
  - monitoring/probe readiness;
  - admin alerts and staff 2FA readiness;
  - subscription expiry, billing renewal and support SLA readiness;
  - owner external-action blocking summary.
- Separate `admin_support_app` now shows the launch readiness summary on the dashboard and in `Готовность`.
- `scripts/windows/check_external_services_readiness.ps1` now verifies `/api/v1/admin/launch/readiness` in server-side protected self-checks and local admin route checks.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - Chrome headless smoke for `admin_support_app\index.html` found no `SyntaxError`, `ReferenceError`, `TypeError` or uncaught JS errors;
  - PowerShell parse check for `scripts/windows/check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.50`;
  - external readiness self-check: green `9`, yellow `2`, red `1`;
  - protected launch readiness self-check: state `red`, public launch not ready, `3` critical blockers and `6` warnings.
- Current critical blockers are expected for this stage: API/site must be split from the VPN endpoint IP, YooKassa production is waiting on external status/contract, and the final Windows installer/update artifact must be built only at the end.
- No public Windows installer was rebuilt.

## 2026-05-07 New VPS Onboarding Plan

- Backend source/live server are now `0.9.52`.
- Added a non-secret `newServerOnboardingPlan` block to protected `GET /api/v1/admin/server-catalog/provisioning-readiness`.
- The plan makes the next VPS flow explicit:
  - add a new VPN server only as internal `draft`;
  - keep `isPublic=false`, `isActive=false`, `clientConfigProfile=none`;
  - use hostnames like `nl1.vpn.greenvpn.pro`, `de1.vpn.greenvpn.pro`, `kz1.vpn.greenvpn.pro`;
  - require DNS, WireGuard setup, external endpoint probe, server-specific config provisioning, canary and rollback before publication.
- Separate `admin_support_app` now shows the new VPS plan in the Server Catalog summary.
- `scripts/windows/check_external_services_readiness.ps1` now extracts:
  - `newVpsOnboardingReady`;
  - `safeToCreateInternalDraft`;
  - onboarding phase/blocker counts;
  - first recommended hostname.
- External owner actions now describe the server catalog task as internal draft preparation, not immediate production publication.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `scripts/windows/check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.52`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Protected self-check confirms:
  - `safeForCurrentClient: true`;
  - `currentEndpointConfigReady: true`;
  - `newVpsOnboardingReady: true`;
  - `safeToCreateInternalDraft: true`;
  - public accepted server ids are still only `auto`, `intelligent_smew`;
  - managed endpoints are not client-visible.
- Current readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split blocker. No public Windows installer was rebuilt.

## Testing Priorities

## 2026-05-07 API/Site And VPN Split Plan

- Backend source/live server are now `0.9.51`.
- Added protected admin endpoint `GET /api/v1/admin/network/split-plan`.
- The existing network readiness now includes a non-secret migration plan for separating:
  - public API/site on `api.greenvpn.pro`;
  - VPN endpoint host such as `nl1.vpn.greenvpn.pro`;
  - safe environment keys for public URLs and `BLUEVPN_ENDPOINT_HOST`;
  - DNS records, rollout phases and verification steps.
- Separate `admin_support_app` now renders the split plan inside the network readiness panel.
- `scripts/windows/check_external_services_readiness.ps1` now verifies `/api/v1/admin/network/split-plan` in server-side protected checks, OpenAPI route inventory and local admin-token checks.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js` because the packaged Node runtime is blocked by Windows permissions in this session;
  - PowerShell parse check for `scripts/windows/check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.51`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck`;
  - protected `/api/v1/admin/network/split-plan` returns HTTP 200 during server self-check.
- Current external readiness remains intentionally red: API/public site and VPN endpoint still share `37.220.85.211`. The plan is now visible in admin tooling, but the actual split requires a separate API/site IP or reverse-proxy VPS plus DNS changes.
- No public Windows installer was rebuilt.

Minimum test after any VPN/connect change:

1. Install latest installer.
2. Launch from desktop shortcut.
3. Login existing user.
4. Click `Подключить VPN` once.
5. Confirm UI moves to connected.
6. Check `C:\ProgramData\BlueVPN\backend.log` contains `=== CONNECT OK ===`.
7. Run diagnostics and verify real tunnel is YES or handshake/traffic are non-zero.
8. Toggle Social Only and test YouTube/Telegram/Discord route behavior.
9. Disconnect and confirm service/tunnel stops cleanly.

Minimum test after auth change:

1. Fresh install/fresh user state.
2. Open auth screen and confirm first tab is `Телефон`.
3. Test phone-code start/verify when SMS provider is configured; until SMS provider is configured, confirm it fails gracefully and suggests email-code.
4. Test `Email-код` start/verify when SMTP is configured; until SMTP is configured, confirm it fails gracefully without exposing technical errors.
5. Test legacy `Пароль`: login known user, wrong password, and create-account fallback.
6. Confirm VPN config warmup/fetch after successful auth, then logout.
7. Relaunch and verify session behavior.

Minimum test after installer change:

1. Old BlueVPN shortcut removed.
2. Green VPN shortcut created.
3. Installer icon/title Green VPN.
4. App window title Green VPN.
5. Installed app file is `greenvpn.exe`, not `bluevpn.exe`.
6. Installed uninstall script is `uninstall_greenvpn.ps1`, not `uninstall_bluevpn.ps1`.
7. Installed support tools use Green VPN names.
8. After connecting, `sc qc "WireGuardTunnel$BlueVPNDev1"` shows `START_TYPE` as `DEMAND_START`, not `AUTO_START`.
9. With Amnezia/WARP already active, Green VPN should refuse to connect with a clear conflict message and must not break networking.
10. Launching the app from `Green VPN.lnk` should not show a UAC prompt.
11. `schtasks /Query /TN GreenVPNConnect`, `schtasks /Query /TN GreenVPNDisconnect`, and `schtasks /Query /TN GreenVPNGuard` should exist after install.
12. Existing ProgramData config/state preserved.
13. WireGuard/WARP tunnel still works.

## 2026-05-07 External Server-Health Probe Operator Plan

- Backend/admin static advanced to `0.9.53` for external server-health probe operation.
- `scripts/windows/run_monitoring_probe_once.ps1` now supports `-ServerHealth` and still reads admin token only from stdin/env/file.
- `GET /api/v1/admin/server-health` now returns an `operatorPlan` with safe one-off Windows/Linux commands, a systemd install command and per-endpoint missing coverage actions.
- `admin_support_app` renders the external probe plan in the endpoint monitoring panel.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json` confirms:
  - `/api/v1/admin/server-health` HTTP 200;
  - `hasOperatorPlan=true`;
  - `runOnceUsesServerHealth=true`;
  - `runOnceUsesStdin=true`;
  - `missingCoverageActions=1` for `current_wg0`.
- Current readiness is still green `9`, yellow `2`, red `1`; the red blocker remains the expected API/VPN endpoint split on `37.220.85.211`.
- No public Windows installer was rebuilt.

## 2026-05-07 Safe VPS Drafts And Public Site Cleanup

- Backend/source/live server advanced to `0.9.55`.
- Added protected safe-draft workflow for future VPS entries:
  - `POST /api/v1/admin/server-catalog/draft-from-plan`;
  - requires `servers.manage`;
  - creates only an internal `draft`;
  - forces `isPublic=false`, `isActive=false`, `clientConfigProfile=none`, `healthScore=0`;
  - never publishes a new endpoint into the Windows client catalog.
- `GET /api/v1/admin/server-catalog/provisioning-readiness` now exposes:
  - `draftCreationEndpoint=/api/v1/admin/server-catalog/draft-from-plan`;
  - safe payload examples for `nl1`, `de1`, `kz1`;
  - `safeToCreateInternalDraft=true` while the current client catalog remains safe.
- Separate `admin_support_app` now has a `Черновик нового VPS` action in the server catalog panel. It uses the safe endpoint and still respects staff permissions.
- Public site pages on `https://api.greenvpn.pro/` were cleaned again:
  - kept download buttons for Windows, Android and iPhone/iPad;
  - removed user-visible draft wording about final build checks, temporary unavailability and legal review;
  - offer/download pages now use public-facing wording without exposing internal release blockers.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `bluevpn_release_gate.ps1`;
  - backend deploy/restart and live health check;
  - server-side public page checks for `/`, `/download/windows`, `/legal/offer`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Current readiness remains green `9`, yellow `2`, red `1`; red is still API/VPN endpoint split. YooKassa remains pending external provider approval/contract. No public Windows installer was rebuilt.

## 2026-05-07 Promo Campaign Readiness

- Backend/source/live server advanced to `0.9.56`.
- Added protected promo readiness workflow:
  - `GET /api/v1/admin/billing/promos/readiness`;
  - `POST /api/v1/admin/billing/promos/draft-start-campaign`;
  - recommended safe first campaign is `START20`: 20% discount, 100 uses, 30 days, `starter/base/plus`.
- Promo readiness now flags risky launch discounts before advertising:
  - inactive or not-current promo;
  - percent discount above 30%;
  - fixed discount above 200 RUB;
  - missing redemption limit;
  - no end date, expired date or window above 60 days;
  - missing plan scope.
- Separate `admin_support_app` now shows the promo campaign readiness summary and has two safe actions:
  - `Заполнить START20` only fills the local form;
  - `Черновик START20` creates an inactive draft and never activates the campaign automatically.
- Launch readiness now includes the `promo_campaign` warning gate, so public launch planning sees whether a safe стартовая акция is prepared.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `bluevpn_release_gate.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Server-side protected self-check confirms `/api/v1/admin/billing/promos/readiness` HTTP 200. Current promo state has no active campaign yet, so `safeToRunLaunchCampaign=false` and `recommendedCode=START20`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-07 New Chat Handoff Package

- Created a fresh transfer package for the next Codex chat:
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/README_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/00_COVER_LETTER_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/01_START_MESSAGE_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/02_WORKFLOW_AND_COMMUNICATION_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/03_PROJECT_STATE_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/04_NON_NEGOTIABLE_RULES_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/05_RELEASE_AND_ROLLBACK_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/06_YOOKASSA_AND_PAYMENTS_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/07_EXTERNAL_SERVICES_OWNER_ACTIONS_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/08_PUBLIC_SITE_LEGAL_BUSINESS_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/09_BACKEND_ADMIN_MONITORING_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/10_SERVER_CATALOG_NETWORK_SPLIT_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/11_USER_APP_INSTALLER_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/12_ADMIN_SUPPORT_APP_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/13_NEXT_DEVELOPMENT_TASKS_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/14_TEST_AND_DEPLOY_COMMANDS_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/15_SECRET_HANDLING_RU.md`;
  - `docs/NEW_CHAT_HANDOFF_2026_05_07/16_CONTEXT_HYGIENE_RU.md`.
- The new cover letter explicitly documents the working style:
  - Russian-first communication;
  - step-by-step owner-guided mode for external services;
  - long autonomous mode for 5-7 hour development sessions;
  - no repeated installer builds until final handoff or explicit test request;
  - old chat is only an emergency archive.
- Updated `docs/START_NEW_CODEX_MESSAGE_RU.md` to point at the new package.
- Updated `docs/CODEX_CONTEXT_COMPACT_RU.md` with live backend `0.9.56`, YooKassa next steps and current API/VPN split blocker.
- YooKassa status from owner: dashboard is now active. Backend still needs `YOOKASSA_SHOP_ID` and `YOOKASSA_SECRET_KEY` through server-only env; do not put the secret key in chat/docs/repo.
- No backend code or installer was changed in this handoff-packaging step.

## 2026-05-07 Public Site Readiness Gate

- Backend/source/live server advanced to `0.9.57`.
- Added protected public site readiness:
  - `GET /api/v1/admin/site/readiness`;
  - checks public routes, legal pages, pricing/download buttons, safe public wording, banned phrase matches and YooKassa return/webhook URLs;
  - does not expose secrets or personal legal values beyond configured booleans and public URLs.
- Launch/product readiness now include a critical `public_site` gate.
- Separate `admin_support_app` now loads and renders site readiness in the dashboard/readiness views.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now probes `/api/v1/admin/site/readiness` and includes it in staff-session route inventory.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime import/payload smoke with temporary local dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.57`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live protected self-check confirms `/api/v1/admin/site/readiness` HTTP 200, `productionReady=true`, `publicSiteReady=true`, `green=7`, `yellow=0`, `bannedPhraseMatches=0`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. YooKassa production payments still need `YOOKASSA_SHOP_ID` and `YOOKASSA_SECRET_KEY` through server-only env. No public Windows installer was rebuilt.

## 2026-05-07 Payment Smoke Readiness Gate

- Backend/source/live server advanced to `0.9.58`.
- Added protected read-only payment smoke readiness:
  - `GET /api/v1/admin/billing/payment-smoke/readiness`;
  - reports whether a minimal YooKassa smoke can be run;
  - exposes safe smoke steps and blockers without creating orders, calling YooKassa or returning secrets/provider payment method ids.
- The smoke gate explicitly blocks until YooKassa production env is configured through server-only env.
- Separate `admin_support_app` now renders payment smoke readiness in `Заказы и платежи` next to reconciliation, renewals and promo readiness.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now probes `/api/v1/admin/billing/payment-smoke/readiness`, checks route inventory and verifies `providerPaymentMethodId` is not exposed.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime import/payload smoke with temporary local dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.58`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live protected self-check confirms `/api/v1/admin/billing/payment-smoke/readiness` HTTP 200, `safeToRunSmoke=false`, `smokeCompleted=false`, `methodIdsExposed=false`. This is expected until owner enters YooKassa production keys through the safe env script.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-07 User Auth Flow Readiness Gate

- Backend/source/live server advanced to `0.9.59`.
- Added protected read-only user auth flow readiness:
  - `GET /api/v1/admin/auth/user-flow/readiness`;
  - verifies code-first auth contract: `phone_code` primary, `email_code` fallback, legacy email/password only as fallback;
  - checks SMS/email availability, code TTL/cooldown/attempt/lockout policy, auth-code pepper and `DEV_AUTH_CODES=0`;
  - summarizes recent auth events without exposing one-time codes, tokens, password hashes or provider secrets.
- `/healthz` now includes `userAuthFlowProductionReady`; `/api/v1/bootstrap/windows` now declares fallback method and challenge endpoints.
- Product/launch readiness include a `user_auth_flow` warning gate.
- Separate `admin_support_app` renders auth readiness in `События входа`.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now probes `/api/v1/admin/auth/user-flow/readiness`, validates that codes/tokens are not exposed, and passes the remote Python payload through stdin so the endpoint inventory no longer hits command-line length limits.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime import/payload smoke with temporary local dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - server-side live `/healthz` returns version `0.9.59`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live protected self-check confirms `/api/v1/admin/auth/user-flow/readiness` HTTP 200, `productionReady=true`, `publicAuthReady=true`, `primaryMethod=phone_code`, `fallbackMethod=email_code`, `codesExposed=false`, `tokensExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Launch Closure Plan Gate

- Backend/source/live server advanced to `0.9.60`.
- Added protected read-only launch closure plan:
  - `GET /api/v1/admin/launch/closure-plan`;
  - separates remaining launch gates into owner-blocked inputs, final-handoff-only work, autonomous code work and operational review;
  - names required env keys/owner inputs without returning secret values.
- Admin/support app now renders the closure plan in dashboard/readiness views.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now probes `/api/v1/admin/launch/closure-plan`, verifies `safeNoSecretExposure=true`, and checks route inventory.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime import/payload smoke with temporary local dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.60`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live closure plan summary: `total=18`, `ready=8`, `pending=10`, `ownerBlocked=5`, `codeOwned=3`, `operationalReview=4`, `finalHandoffOnly=1`, `secretValuesExposed=false`.
- Current owner-blocked inputs: API/VPN endpoint split, YooKassa production keys, monitoring probe host, Telegram alerts, and the external owner-action group.
- Next autonomous action from the closure plan: clear support SLA queue items that are overdue/review-pending/missing first response.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Support SLA Cleanup And Promo Draft Hold

- Live support SLA queue was inspected before mutation. It contained only two historical smoke reports:
  - `appVersion=smoke`;
  - summary `support report smoke`;
  - status `new`, overdue and missing first response.
- Closed both smoke reports through the existing protected support status endpoint with audit actor `codex-support-sla-cleanup-0.9.60` and an explicit note that they were historical smoke reports.
- Live `GET /api/v1/admin/support/sla` now reports `attentionRequired=false`, `open=0`, `overdue=0`, `reviewPending=0`, `firstResponseMissing=0`.
- Created inactive `START20` promo draft through existing protected `POST /api/v1/admin/billing/promos/draft-start-campaign`:
  - discount `20%`;
  - `maxRedemptions=100`;
  - inactive, not public, not applied to users.
- Backend/source/live server advanced to `0.9.61` to refine the closure-plan logic:
  - if inactive promo draft exists, `promo_campaign` is no longer treated as an autonomous next step;
  - it becomes a hold depending on `payments` and `updates`;
  - activation remains manual only after payment/release readiness is green.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - QuickJS render smoke for the owner packet card;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.61`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live closure plan now reports `ready=9`, `pending=9`, `ownerBlocked=5`, `codeOwned=2`, `operationalReview=3`, `finalHandoffOnly=1`, `nextAutonomousActions=0`, `canContinueAutonomously=false`, `secretValuesExposed=false`.
- Remaining launch blockers are owner/final/payment-dependent:
  - API/VPN endpoint split;
  - YooKassa production keys/payment smoke;
  - monitoring probe host;
  - Telegram alerts;
  - final installer/update artifact;
  - billing renewals and subscription expiry review after payments.

## 2026-05-08 Owner Action Note Secret Guard

- Backend/source/live server advanced to `0.9.62`.
- External owner-action notes are now guarded server-side before DB/audit writes.
- `POST /api/v1/admin/external-actions/{action_code}` rejects obvious secret material in notes:
  - private key blocks;
  - WireGuard private key assignments;
  - bearer/admin-token/password/secret assignments;
  - sensitive env assignments such as `*_SECRET`, `*_TOKEN`, `*_PASSWORD`, `*_API_ID`, `*_CHAT_ID`.
- The rejection returns only pattern codes and does not echo submitted values.
- `GET /api/v1/admin/external-actions` exposes `ownerActionPolicy.serverEnforced=true` and `blockedNotePatternCodes`.
- Separate `admin_support_app` now renders the owner-note guard state in the owner-actions panel.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` validates the guard.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - temp DB runtime smoke with fake `YOOKASSA_SECRET_KEY=...` blocked and a safe note accepted;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.62`;
  - live self-check confirms `ownerNoteServerEnforced=true`, `blockedNotePatterns=6`, closure `secretValuesExposed=false`.
- Live negative test against `/api/v1/admin/external-actions/payments` returned HTTP `400` without echoing even the fake submitted value.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 API/VPN Split Preflight Tooling

- Backend/source/live server advanced to `0.9.63`.
- Added `scripts\windows\check_api_vpn_split_preflight.ps1`.
- The script is secret-free and mutation-free; it checks:
  - API HTTPS URL;
  - DNS for `api.greenvpn.pro` and the VPN endpoint host;
  - expected API/VPN IPs, when supplied;
  - API/VPN IP overlap;
  - public `/healthz`.
- `/api/v1/admin/network/split-plan` now returns a `preflight` block with a copyable command:
  - use it after the owner prepares a candidate separate API/site IP or reverse proxy;
  - keep `-ExpectedApiIp <new-api-site-ip>` as the owner-provided public API/site IP;
  - expected VPN IP remains `37.220.85.211` unless the VPN endpoint is moved separately.
- `external_owner_setup_bundle()` now includes `splitPreflight` metadata.
- Separate `admin_support_app` renders the preflight command in network readiness.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` validates `hasPreflight=true`, `preflightMutationFree=true`, `preflightUsesScript=true`, `preflightJsonReady=true`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - temp runtime smoke for split preflight payload;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for both readiness/preflight scripts;
  - local preflight dry-run shows expected current red overlap;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.63`;
  - live self-check confirms split preflight metadata is present and closure still has `secretValuesExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Admin Support App Owner Note UX Guard

- Backend source/live server version was not changed; live remains `0.9.63`.
- Separate `admin_support_app` now formats structured API errors without showing `[object Object]`:
  - object/array `detail` values are converted to readable messages;
  - fallback JSON redacts sensitive keys such as `input`, `authorization`, `password`, `secret`, `token`, private keys and preshared keys.
- Owner-action note textareas now run a client-side precheck before `POST /api/v1/admin/external-actions/{action_code}`:
  - blocks obvious private-key blocks, WireGuard private-key assignments, bearer/admin tokens, password/secret assignments and sensitive env assignments;
  - does not echo submitted values in the notice;
  - server-side note guard remains authoritative.
- Checks passed:
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - targeted QuickJS runtime check: safe note passes, fake `YOOKASSA_SECRET_KEY=...` is flagged, object API errors format with pattern codes, validation `input` value is not shown.
- Post-polish live self-check still reports backend `0.9.63`, green `9`, yellow `2`, red `1`; red remains the API/VPN same-IP split.
- No backend deploy/restart was needed for this local admin app polish. No public Windows installer was rebuilt.

## 2026-05-08 Owner Launch Packet Endpoint

- Backend/source/live server advanced to `0.9.64`.
- Added protected read-only owner packet endpoint:
  - `GET /api/v1/admin/launch/owner-packet`;
  - requires `readiness.read`;
  - combines closure-plan, external-actions setup bundle and API/VPN split preflight metadata into one owner-facing packet.
- Added `scripts\windows\get_owner_launch_packet.ps1`:
  - default path reads the admin token only on the server through SSH;
  - prints a sanitized summary or `-Json` payload;
  - fails if forbidden secret markers appear.
- The endpoint returns:
  - owner-facing commands labelled with `secret` and `mutationFree`;
  - pending owner actions and owner input fields;
  - non-secret DNS records and safe defaults;
  - split preflight metadata;
  - after-apply readiness checks.
- Secret policy:
  - endpoint may name env keys/provider fields;
  - secret values are not returned;
  - `safeNoSecretExposure=true` and `policy.noSecretValues=true`.
- Separate `admin_support_app` now loads `/api/v1/admin/launch/owner-packet` and renders an owner packet card in `Готовность`.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now includes the endpoint and validates `safeNoSecretExposure`, `noSecretValues`, command count, split preflight and secret marker absence.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - QuickJS render smoke confirms the owner packet card shows commands, secret-input labels, no-secret policy and launch blockers;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - PowerShell parse check for `check_api_vpn_split_preflight.ps1`;
  - PowerShell parse check and live run for `get_owner_launch_packet.ps1`;
  - temp runtime smoke for `build_owner_launch_packet`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.64`;
  - live owner-packet direct probe returns HTTP `200`, `commands=3`, `ownerActions=3`, `safeNoSecretExposure=true`, `noSecretValues=true`, `hasSplitPreflight=true`, `secretMarkers=false`;
  - `get_owner_launch_packet.ps1` prints summary `version=0.9.64`, `commands=3`, `ownerActions=3`, `ownerBlockers=5`, no token value;
  - live protected self-check confirms owner-packet HTTP `200`, `secretValuesExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Payment-Dependent Renewal And Expiry Guard

- Backend/source/live server advanced to `0.9.65`.
- Tightened the payment-dependent readiness gates:
  - `/api/v1/admin/billing/renewals/readiness` now requires clean payment smoke before `safeToEnableAutoRenewalCharges=true`;
  - `/api/v1/admin/subscriptions/expiry-readiness` now requires clean payment smoke before `safeToEnableExpiryEnforcement=true`;
  - both payloads expose `paymentSmokeCompleted`, `paymentSmokeReady` and `policy.requiresPaymentSmoke=true`.
- Separate `admin_support_app` now shows the payment-smoke dependency in the renewal and expiry cards.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now validates that renewal/expiry safe flags cannot be true while `paymentSmokeReady=false`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - QuickJS render smoke for renewal/expiry cards;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - temp DB runtime smoke: with YooKassa production mocked green but payment smoke mocked incomplete, renewal/expiry stay unsafe and require attention;
  - backend deploy/restart on `37.220.85.211`;
  - server-side `/healthz` returns version `0.9.65`;
  - live protected self-check reports renewal `paymentSmokeReady=false`, `safeToEnableAutoRenewalCharges=false`, `requiresPaymentSmoke=true`;
  - live protected self-check reports expiry `paymentSmokeReady=false`, `safeToEnableExpiryEnforcement=false`, `requiresPaymentSmoke=true`;
  - owner packet still returns HTTP `200`, version `0.9.65`, `ownerBlockers=5`, `safeNoSecretExposure=true`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Payment Launch Safety CLI And Owner Packet Command

- Backend/source/live server advanced to `0.9.66`.
- Added `scripts\windows\check_payment_launch_safety.ps1`:
  - default path reads admin token only on the server through SSH;
  - checks billing readiness, payment smoke, renewals and subscription expiry;
  - prints sanitized text or `-Json`;
  - fails if forbidden markers such as `providerPaymentMethodId`, `secretValue`, `adminToken`, `privateKey` or `passwordHash` appear.
- Owner launch packet now includes mutation-free command `payment_launch_safety`, so owner packet command count is `4`.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now validates `hasPaymentLaunchSafety=true` for owner packet.
- Checks passed:
  - PowerShell parse check and live run for `check_payment_launch_safety.ps1`;
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - owner packet live returns `version=0.9.66`, `commands=4`, `hasPaymentLaunchSafety=true`, `safeNoSecretExposure=true`;
  - payment launch safety live returns `productionPaymentReady=false`, `safeToRunSmoke=false`, `smokeCompleted=false`, `safeForAutomaticBilling=false`;
  - live protected self-check confirms owner packet HTTP `200`, commands `4`, `hasPaymentLaunchSafety=true`, `secretValuesExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Monitoring Probe Plan CLI And Owner Packet Command

- Backend/source/live server advanced to `0.9.67`.
- Added `scripts\windows\get_monitoring_probe_plan.ps1`:
  - default path reads admin token only on the server through SSH;
  - checks monitoring readiness and server-health external probe readiness;
  - prints sanitized text or `-Json`;
  - verifies install/run-once commands use token stdin and server-health mode;
  - fails if forbidden secret markers appear.
- Owner launch packet now includes mutation-free command `monitoring_probe_plan`; live owner packet command count is `5`.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now validates `hasMonitoringProbePlan=true`.
- Checks passed:
  - PowerShell parse check and live run for `get_monitoring_probe_plan.ps1`;
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - owner packet live returns `version=0.9.67`, `commands=5`, `hasPaymentLaunchSafety=true`, `hasMonitoringProbePlan=true`;
  - monitoring probe plan live returns `installCommandUsesTokenStdin=true`, `installCommandUsesServerHealth=true`, `hasOperatorPlan=true`, `safeToProceed=false`;
  - live protected self-check confirms owner packet HTTP `200`, commands `5`, `secretValuesExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Owner Required Input Verification

- Synced the live owner-action state for `email` through protected `POST /api/v1/admin/external-actions/email`.
- Result: external-actions now has `waitingCodes=[]`; `email`, `sms`, `public_api`, `server_catalog` and `monitoring` are `done` and live-ready.
- Verified without printing secret values:
  - local Windows env has no `YOOKASSA_*`, Telegram alert or final update artifact values;
  - server `/etc/bluevpn/backend.env` has no `YOOKASSA_SHOP_ID`, `YOOKASSA_SECRET_KEY`, `GREENVPN_TELEGRAM_ALERT_BOT_TOKEN`, `GREENVPN_TELEGRAM_ALERT_CHAT_ID`, or final `GREENVPN_UPDATE_*`/rollback values;
  - repo search found only code/docs references for those keys, not a prepared private env file.
- Live remaining external action statuses:
  - pending: `payments`, `updates`, `admin_alerts`;
  - `payments` is blocked until YooKassa production keys are entered through server-only env and payment smoke is clean;
  - `admin_alerts` is blocked until Telegram alert bot token/chat id are entered through server-only env;
  - `updates` remains final-handoff only; no new installer was built.
- Live closure-plan summary remains `state=work_remaining`, `ready=9`, `pending=9`, `ownerBlocked=5`, `finalHandoffOnly=1`, `canContinueAutonomously=false`.
- Next owner input is still a separate public API/site IP or reverse proxy target, plus DNS decision for `api.greenvpn.pro` and `nl1.vpn.greenvpn.pro`.
- Checked the current separate site IP candidate `95.163.244.138`: it serves the public site, but SSH on port `22` is refused, so Codex cannot autonomously configure it as an API reverse proxy or monitoring host.
- No backend deploy/restart was needed. No public Windows installer was rebuilt.

## 2026-05-08 YooKassa Production Env Applied

- Applied YooKassa production env to the backend host through the existing server-only env flow without printing the secret value.
- Backend health now reports `paymentsProductionReady=true`; `/api/v1/admin/billing/readiness` reports `provider=yookassa`, `productionReady=true`, `requiredActions=[]`.
- External actions now treat `payments` as `done/ready`; remaining pending owner actions are `updates` and `admin_alerts`.
- Created one minimal YooKassa smoke order through backend billing logic:
  - amount `149 RUB`;
  - `autoRenew=false`;
  - status `pending`;
  - hosted payment URL was created successfully.
- Payment smoke state is now yellow:
  - `safeToRunSmoke=true`;
  - `pendingWithPaymentUrl=1`;
  - `smokeCompleted=false`;
  - auto-renewal charges and strict subscription expiry enforcement remain unsafe/off until provider-backed payment confirmation is observed.
- Closure plan moved to `ready=10`, `pending=8`, `ownerBlocked=4`, `critical=2`; main red blocker remains API/VPN endpoint split.
- Clipboard was overwritten after applying the key. Do not store the YooKassa secret in repo/docs/chat. The downloaded `secret_key.txt` should be removed or the key should be rotated after the owner decides how to handle the exposed value.
- No public Windows installer was rebuilt.

## 2026-05-08 YooKassa Smoke Completed And Renewal Gate Clean

- Owner completed the hosted YooKassa payment for the minimal smoke order.
- Server-side authoritative YooKassa fetch returned `status=succeeded`, `paid=true`; backend then activated the order through `apply_yookassa_payment_update`, not through admin mark-paid.
- Payment smoke is now green:
  - `safeToRunSmoke=true`;
  - `smokeCompleted=true`;
  - `successfulSmokeCandidates=1`;
  - `yookassaActivatedTotal=1`.
- `/payment/return` responds HTTP `200` from the server. The local Firefox failure is consistent with the existing local API/VPN same-IP/DNS access problem, not a missing backend route.
- Canceled one old synthetic pending order that blocked renewal dry-run:
  - order `ord_reNMherdX5YlUfZvjTWlCGC`;
  - user `codex_payments_1777568118@greenvpn.local`;
  - provider `manual_mvp`;
  - status changed from `pending` to `canceled`.
- Renewal readiness is now clean for the current due window:
  - `safeToEnableAutoRenewalCharges=true`;
  - `requiresAttention=false`;
  - `pendingOrderConflicts=0`.
- Subscription expiry enforcement remains intentionally off:
  - `safeToEnableExpiryEnforcement=false`;
  - two expiring trial/free subscriptions lack verified retention contact;
  - do not enable strict expiry enforcement until those operational records are reviewed.
- Closure plan now reports `ready=11`, `pending=7`, `codeOwned=1`, `ownerBlocked=4`, `warnings=5`.
- No public Windows installer was rebuilt.

## 2026-05-08 API/VPN Split Completed

- The main production red blocker was closed.
- DNS now separates public API/site and VPN endpoint:
  - `api.greenvpn.pro -> 72.56.32.197`;
  - `nl1.vpn.greenvpn.pro -> 37.220.85.211`;
  - root `greenvpn.pro` and `www.greenvpn.pro` remain on `95.163.244.138`.
- New Timeweb Cloud VPS `Friendly Cetus` / `72.56.32.197` is configured as the public API reverse proxy:
  - nginx terminates HTTPS for `api.greenvpn.pro`;
  - Let's Encrypt certificate is issued, expires `2026-08-06`;
  - proxy upstream is the origin backend `https://37.220.85.211` with Host/SNI `api.greenvpn.pro`.
- SSH password auth was disabled on the new proxy after the password was exposed in chat; root key login still works.
- Backend origin env was updated to `BLUEVPN_ENDPOINT_HOST=nl1.vpn.greenvpn.pro`; internal names remain unchanged.
- Origin `/etc/hosts` has temporary pins for `api.greenvpn.pro` and `nl1.vpn.greenvpn.pro` because upstream DNS on the origin was still cached during the cutover. It can be removed later after resolver TTL is definitely clear.
- Checks passed:
  - `check_api_vpn_split_preflight.ps1 ... -ExpectedApiIp 72.56.32.197 -ExpectedVpnIp 37.220.85.211 -Json`: `green=7`, `yellow=0`, `red=0`;
  - backend `/api/v1/admin/network/readiness`: `productionReady=true`, `overlapIps=[]`;
  - external readiness: `green=11`, `yellow=1`, `red=0` where the only yellow is the local script's skipped admin-token branch while protected server self-check is green.
- No public Windows installer was rebuilt.

## 2026-05-08 Subscription Expiry Review Gate

- Backend/source/live server advanced to `0.9.69`.
- Added audited admin expiry-review support:
  - DB table `subscription_expiry_reviews`;
  - `POST /api/v1/admin/subscriptions/{subscription_id}/expiry-review`;
  - review reasons reject obvious secret material before DB/audit writes;
  - admin/support app can record review from the subscription expiry card;
  - expiry candidate preview no longer shows candidate email in the card.
- Reviewed the two current trial/free expiry candidates without printing email/phone values. Both had no activated billing orders and no verified retention contact; review allows natural trial expiry, but does not enable strict enforcement.
- Payment launch safety now reports:
  - `productionPaymentReady=True`;
  - `smokeCompleted=True`;
  - `renewalSafeToEnableCharges=True`;
  - `expirySafeToEnableEnforcement=True`;
  - `safeForAutomaticBilling=True`.
- Closure-plan aggregator was tightened so the inactive `START20` draft no longer counts as autonomous work while it is waiting for final release/update readiness.
- `BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS` remains off; do not enable strict enforcement until final launch decision.
- Current closure-plan summary after this work:
  - `ready=13`, `pending=5`, `ownerBlocked=3`, `codeOwned=0`, `operationalReview=1`, `finalHandoffOnly=1`, `critical=1`, `warnings=4`;
  - `canContinueAutonomously=false`;
  - remaining owner-blocked actions: `monitoring_probes`, `admin_alerts`, `owner_actions`;
  - final-only action: `updates`;
  - operational hold: inactive `START20` draft exists and must wait for payment/release readiness before manual activation.
- No public Windows installer was rebuilt.

## Do Not Do

- Do not touch personal Friendly Linnet server.
- Do not store secrets in docs or code.
- Do not remove old working configs/keys.
- Do not rename internal tunnel/service without migration.
- Do not implement Android/iOS before Windows MVP is stable.
- Do not add billing bypasses or free tariff activation paths.
- Do not bury technical errors in silent failures while MVP is still being stabilized; log them to `auth.log`/`backend.log`.
