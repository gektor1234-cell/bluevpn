# Green VPN Release State

Последнее обновление: 2026-05-09

## Latest Known Installer

- Path: `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- Latest alias: `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`
- Candidate copy: `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`
- SHA256: `5F88E078B4E8EE4519D29F6A92FF58A738CA1DD5F1E26ED108864390BAE39D01`
- Size: about 12.7 MB

## Beton Rollback Anchor

If a later experiment breaks install/connect/auth again, return to this exact build first:

- Folder: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok`
- Installer: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- Payload: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_current_release_payload_ROLLBACK.zip`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`
- Why this anchor matters: payment-confirmation flow is accepted as the current stable baseline. It includes production-payment readiness plus the hosted payment return page and automatic pending-order polling in the client.

## Test Build Hygiene

Latest user instruction: do not issue a fresh installer after every intermediate change. Build the next test installer only at the final handoff point, or when the user explicitly asks to stop and test. Immediately before issuing that installer, clean the previous installed Green VPN build first. The cleanup should remove only Green VPN artifacts: installed app folder, shortcuts, Green VPN scheduled tasks, old BlueVPN task names, `C:\ProgramData\BlueVPN`, and only the `BlueVPNDev1` WireGuard tunnel. Do not remove WireGuard itself, Amnezia, WARP, or the user's personal/Friendly VPN setup.

## Roadmap Binding

Development is now bound to `C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`.

After every stable step:

- Freeze a rollback installer.
- Record SHA256 here.
- Update `CURRENT_HANDOFF.md`.
- Move only to the next roadmap item unless the user explicitly changes priority.

Current stable baseline is the payment-confirmation-flow build above. Latest issued installer remains the support-report fallback build. Current source/live backend candidate is `0.9.69`: YooKassa production smoke is complete, API/VPN split is live through the new reverse proxy, payment/renewal/expiry safety is green, closure-plan autonomous work is clear, and no new installer was issued by user instruction. YouTube/Discord/Telegram availability checks and endpoint health scoring remain backend/internal monitoring only, not a normal user-facing app screen.

## Build Commands

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

## Installed App Expectations

- Install dir: `%LOCALAPPDATA%\Programs\Green VPN`
- Desktop shortcut: `Green VPN.lnk`
- Start menu: `Green VPN`
- Visible window title: `Green VPN`
- Installer name: `GreenVPN_Setup.exe`

## Still Expected Internals

- Installed app exe is now `greenvpn.exe`.
- Installed uninstall script is now `uninstall_greenvpn.ps1`.
- Installed support tools are now `doctor_greenvpn.ps1` and `greenvpn_network_recover.ps1`.
- Installed boot-conflict repair tool is now `greenvpn_boot_repair.ps1`.
- Installed privileged VPN task tool is now `greenvpn_vpn_task.ps1`.
- Installed scheduled tasks are `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard`.
- Native service candidate is `GreenVPNService` installed from `greenvpn_service.exe`.
- Tunnel remains `BlueVPNDev1`.
- Config/state remains under `C:\ProgramData\BlueVPN`.
- WireGuard service remains `WireGuardTunnel$BlueVPNDev1`.

## Pre-Public Known Gaps

- Native Windows service is rollback-stable as of the `ROLLBACK_20260430_163530_native_service_ok` anchor. SYSTEM scheduled tasks remain as fallback.
- Tray/background is rollback-stable as of the `ROLLBACK_20260430_165617_tray_ok` anchor.
- Autostart is rollback-stable as of the `ROLLBACK_20260430_170548_autostart_ok` anchor.
- Auth/register/login is rollback-stable as of the `ROLLBACK_20260430_171555_auth_ok` anchor.
- Auth/register/login needs cleanup pass.
- Backend Admin was removed from normal user settings; separate admin/support app is now being built.
- Diagnostics became a coded support report in the user app; support/admin workflow still needs roles, comments and audit log.
- Payments are production-connected through YooKassa and the minimal live smoke payment succeeded; final public rollout still waits for monitoring/admin-alert/update gates.
- No code signing yet.
- Basic updater manifest exists; no signed/downloading updater yet.
- No public docs/offers/privacy policy yet.

## 2026-05-08 API/VPN Split, Payments And Expiry Review

- Live backend is `0.9.69`.
- YooKassa production env is configured server-side; one minimal `149 RUB` hosted payment was paid, fetched authoritatively from YooKassa and activated by backend provider sync.
- Payment launch safety is green:
  - `productionPaymentReady=True`;
  - `safeToRunSmoke=True`;
  - `smokeCompleted=True`;
  - `renewalSafeToEnableCharges=True`;
  - `expirySafeToEnableEnforcement=True`;
  - `safeForAutomaticBilling=True`.
- API/VPN endpoint split is green:
  - `api.greenvpn.pro -> 72.56.32.197`;
  - `nl1.vpn.greenvpn.pro -> 37.220.85.211`;
  - `check_api_vpn_split_preflight.ps1` reports `green=7`, `yellow=0`, `red=0`.
- New API reverse proxy:
  - Timeweb Cloud `Friendly Cetus`, IP `72.56.32.197`;
  - nginx proxies to origin `https://37.220.85.211`;
  - Let's Encrypt cert for `api.greenvpn.pro` expires `2026-08-06`;
  - SSH password auth disabled; key login remains enabled.
- Added `subscription_expiry_reviews` and `POST /api/v1/admin/subscriptions/{subscription_id}/expiry-review`.
- Two current trial/free expiry candidates were reviewed through the new audited endpoint; strict subscription enforcement remains disabled by env.
- Latest external readiness check: `green=11`, `yellow=1`, `red=0`; only yellow is the local no-admin-token branch while server-side protected checks are green.
- Launch closure summary after this work: `ready=13`, `pending=5`, `ownerBlocked=3`, `codeOwned=0`, `operationalReview=1`, `finalHandoffOnly=1`, `critical=1`, `warnings=4`.
- `canContinueAutonomously=false`; the inactive `START20` draft is now treated as a hold until final release/update readiness.
- Remaining non-final blockers:
  - external monitoring probe host/token placement;
  - Telegram admin alert bot token/chat id;
  - `START20` manual activation only after final release readiness.
- Final-only blocker:
  - build/publish final Windows installer/update artifact with SHA256 and rollback.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-09 Public Site/Admin Hosting On API Proxy

- DNS for root/www was changed:
  - `greenvpn.pro -> 72.56.32.197`;
  - `www.greenvpn.pro -> 72.56.32.197`.
- The Timeweb proxy server `Friendly Cetus` / `72.56.32.197` now hosts:
  - public site at `https://greenvpn.pro/` and `https://www.greenvpn.pro/`;
  - installer download at `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`;
  - separate admin site at `https://admin.greenvpn.pro/`.
- Owner added DNS:
  - `A admin -> 72.56.32.197`.
- `https://greenvpn.pro/admin/` now redirects to `https://admin.greenvpn.pro/`.
- Admin UI is no longer openly reachable:
  - `https://admin.greenvpn.pro/` returns HTTP `401` without nginx Basic Auth;
  - authenticated Basic Auth smoke returns HTTP `200`;
  - HTTP `admin.greenvpn.pro` redirects to HTTPS.
- Admin staff login is usable:
  - a server-generated owner staff password was created without printing it;
  - staff login smoke succeeded with `authType=staff_session`;
  - one-time access files are root-only on the Timeweb proxy: `/root/greenvpn-admin-basic-auth-onetime.txt` and `/root/greenvpn-admin-owner-login-onetime.txt`.
- Admin 2FA status:
  - backend/admin UI implement email-code 2FA;
  - server-only admin 2FA pepper is configured;
  - new Yandex 360 mail app password was applied only to server env;
  - SMTP smoke passed through the restricted proxy relay: TCP ok, STARTTLS ok, login ok;
  - mandatory admin 2FA is enabled;
  - readiness is production-ready with `required=true`, `enabledStaffCount=1`, `requiredActionsCount=0`;
  - staff login smoke returns `authType=staff_2fa_pending`, `challengeIssued=true`, `sessionTokenIssued=false`.
- A restricted SMTP TCP forward is active on `72.56.32.197`:
  - systemd unit `greenvpn-yandex-smtp-relay.service`;
  - source-limited to origin `37.220.85.211`;
  - origin maps `smtp.yandex.ru` to `72.56.32.197` and uses port `2587` with STARTTLS.
- Let's Encrypt certificates:
  - `greenvpn.pro` / `www.greenvpn.pro` expires `2026-08-07`;
  - `admin.greenvpn.pro` expires `2026-08-07`.
- Existing `api.greenvpn.pro` reverse proxy remains separate and still proxies to origin backend `37.220.85.211`.
- Server capacity check after deployment:
  - load average `0.00`;
  - memory `344 MiB` used, about `1.6 GiB` available;
  - disk `/` about `2.1 GiB` used of `38 GiB`;
  - public site including installer about `13 MiB`;
  - admin app about `336 KiB`.
- Conclusion: current `2 CPU / 2 GB RAM / 40 GB NVMe` proxy is enough for public static site, admin static app, installer downloads for MVP, and API reverse proxy. It must not be treated as the VPN traffic endpoint; VPN endpoint remains `37.220.85.211`.

## 2026-05-05 Admin Support Alerts/Readiness Candidate

- Backend source and live server are now `0.9.2`.
- Added protected admin external-action checklist for the owner-facing setup work:
  - public API/domain/HTTPS;
  - Yandex 360 SMTP/email;
  - SMS.ru;
  - YooKassa;
  - updates;
  - server catalog;
  - monitoring;
  - Telegram admin alerts.
- Added admin alert readiness/test endpoints:
  - `GET /api/v1/admin/alerts/readiness`
  - `POST /api/v1/admin/alerts/test`
- Added Telegram incident alert groundwork through server-only env variables. Tokens/chat ids must be configured only on the server; nothing sensitive is stored in repo/docs.
- Added incident `last_alert_at`, `last_alert_status`, and `last_alert_error` metadata.
- Added monitoring probe inventory endpoint `GET /api/v1/admin/monitoring/probes`.
- Added `scripts\monitoring\install_probe_systemd.sh` for a controlled external monitoring VPS probe. It installs `service_probe.py` as a systemd timer and stores the admin token only on the probe host.
- Hardened `scripts\windows\check_external_services_readiness.ps1`:
  - DNS checks for A/MX/TXT/SPF/DKIM/DMARC;
  - server-side HTTPS self-check;
  - protected `-ServerAdminSelfCheck` that reads the admin token only on the server and returns sanitized readiness summaries;
  - no admin token is printed, copied, or stored locally.
- Separate `admin_support_app` now shows:
  - owner external-actions checklist;
  - admin alert readiness/test action;
  - incident last alert status;
  - monitoring/probe readiness.
- Current readiness result:
  - green: DNS A/MX/SPF/DKIM, backend raw IP, server-side HTTPS, protected admin self-check;
  - red expected: missing `_dmarc.greenvpn.pro` TXT;
  - local Windows/WSL may fail `https://api.greenvpn.pro` while server-side HTTPS is green, so use `-ServerAdminSelfCheck` as the authoritative backend readiness check from this machine.
- Checks passed:
  - `python -m py_compile .\backend_live\app\main.py .\scripts\monitoring\service_probe.py`
  - `wsl bash -lc "bash -n /mnt/c/Users/gekto/projects/bluevpn/scripts/monitoring/install_probe_systemd.sh && bash -n /mnt/c/Users/gekto/projects/bluevpn/scripts/configure_backend_env_wsl.sh"`
  - live `/healthz` reports `version: 0.9.2`
  - `check_external_services_readiness.ps1 -Json -ServerAdminSelfCheck`
  - `flutter build windows --release -t .\lib\main.dart`
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`
  - `bluevpn_release_gate.ps1 -StrictPaymentGate -ReleaseZip C:\BlueVPN_Builds\_installer_work\GreenVPN_current_release_payload.zip`
- Previous installed Green VPN artifacts and old setup exe files were cleaned before issuing this candidate.
- New installer aliases:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`
- Named candidate copy:
  - `C:\BlueVPN_Builds\GreenVPN_Setup_AdminSupportAlertsReadiness_20260505.exe`
- SHA256: `0B9BA08343444DF23F8A01FD47A52F3A3779F3CD93A75EF752D89FD664AC8F82`
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_2028_payment_confirmation_ok` until the user confirms this candidate behaves correctly.

## 2026-05-05 Admin Staff Sessions/RBAC Candidate

- Backend source version bumped to `0.9.3`.
- Added proper staff login/session flow for the separate admin/support app:
  - `POST /api/v1/admin/auth/login`;
  - `GET /api/v1/admin/auth/me`;
  - `POST /api/v1/admin/auth/logout`.
- Added `admin_sessions` storage. Backend stores only SHA256 hash of session tokens.
- Extended `admin_staff` with password hash metadata and last-login tracking.
- Staff temporary passwords can be set from `Команда`; open passwords are never returned by API.
- Backend now enforces role permissions on admin endpoints instead of merely preparing roles.
- Bootstrap `admin_token` is still accepted as owner/emergency access, but staff session auth is now the intended daily admin/support path.
- Separate `admin_support_app` now supports:
  - email/password staff login;
  - logout;
  - role-aware navigation;
  - permission-aware data loading to avoid expected 403 spam for support/finance/readonly roles;
  - default-off `Запомнить на этом компьютере`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`
- `node --check admin_support_app\app.js` could not run in this Codex desktop session because bundled `node.exe` is blocked by Windows with `Access is denied`. This is an environment limitation, not a known app failure.
- Not deployed/frozen yet unless a later deploy entry confirms live `/healthz` `0.9.3`.

## 2026-05-05 Admin Feature Flags/Runbooks Candidate

- Backend source version bumped to `0.9.4`.
- Added internal feature flag storage `admin_feature_flags`.
- Added internal support/ops runbook storage `admin_runbooks`.
- Added default seeded feature flags and runbooks on backend startup.
- Added admin endpoints:
  - `GET /api/v1/admin/feature-flags`;
  - `POST /api/v1/admin/feature-flags`;
  - `POST /api/v1/admin/feature-flags/{flag_id}`;
  - `GET /api/v1/admin/runbooks`;
  - `POST /api/v1/admin/runbooks`;
  - `POST /api/v1/admin/runbooks/{runbook_id}`.
- Added RBAC permissions:
  - `flags.read`;
  - `flags.manage`;
  - `runbooks.read`;
  - `runbooks.manage`.
- Admin overview now reports:
  - `featureFlagsCount`;
  - `activeFeatureFlagsCount`;
  - `runbooksCount`;
  - `activeRunbooksCount`.
- Separate `admin_support_app` now has internal sections:
  - `Флаги` for rollout/control flags;
  - `Инструкции` for support/ops runbooks.
- These sections are internal only and must not be exposed in the normal Green VPN user client.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - static Python scan for new backend/admin app ids and endpoint references;
  - `quickjs` syntax parse of `admin_support_app\app.js` passed until expected browser-global runtime boundary.
- `node --check admin_support_app\app.js` could not run in this Codex desktop session because bundled `node.exe` is blocked by Windows with `Access is denied`.
- Deployed on `37.220.85.211`.
- Live smoke passed:
  - `/healthz` reports `version: 0.9.4`;
  - `/api/v1/admin/feature-flags` returns 8 seeded feature flags;
  - `/api/v1/admin/runbooks` returns 7 seeded runbooks;
  - `/api/v1/admin/overview` returns matching `featureFlagsCount` and `runbooksCount`.
- No new public VPN installer was rebuilt for this entry because only backend/admin-support internals changed.
- Not frozen as a public rollback anchor. The latest public installer alias remains whatever was produced by the previous installer entry unless a later client build explicitly replaces it.

## 2026-05-05 Admin Support Actions Candidate

- Backend source version bumped to `0.9.5`; live server `37.220.85.211` now reports `0.9.5`.
- Added internal support action storage `admin_support_actions`.
- Added support config-refresh markers on devices:
  - `support_config_refresh_requested_at`;
  - `support_config_refresh_reason`;
  - `support_config_refresh_requested_by`.
- Added RBAC permissions:
  - `support_actions.read`;
  - `support_actions.manage`.
- Added admin endpoints:
  - `GET /api/v1/admin/support/actions/workflow`;
  - `GET /api/v1/admin/support/actions`;
  - `POST /api/v1/admin/users/{user_id}/support-actions`.
- Added support actions:
  - reset user sessions;
  - request config refresh for one/all devices;
  - clear config refresh request;
  - disable device;
  - enable device;
  - add internal support note.
- User detail payload now includes `supportActions`; device payloads include support refresh markers.
- Admin overview now reports `supportActionsCount` and `supportActions24hCount`.
- Separate `admin_support_app` now shows a support-action panel inside the user card and a safe history table for performed actions.
- These actions are internal admin/support tooling only. They must not appear in the normal Green VPN user client.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - `quickjs` syntax parse for `admin_support_app\app.js` up to expected browser-global boundary;
  - live `/healthz` reports `version: 0.9.5`;
  - live `/api/v1/admin/support/actions/workflow` returns 6 support actions;
  - live `/api/v1/admin/support/actions?limit=5` returns successfully;
  - live `/api/v1/admin/overview` includes support action counters.
- No new public VPN installer was rebuilt for this entry because only backend/admin-support internals changed.

## 2026-05-05 External Owner Actions Workflow Candidate

- Backend source version bumped to `0.9.6`.
- Added internal owner action status storage `admin_owner_action_statuses`.
- Added RBAC permission `readiness.manage` for `owner` and `admin`.
- Added admin endpoint `POST /api/v1/admin/external-actions/{action_code}`.
- External checklist actions now include owner workflow metadata:
  - `ownerStatus`;
  - `ownerStatusTitle`;
  - `ownerNote`;
  - `ownerUpdatedBy`;
  - `ownerUpdatedAt`.
- Supported owner statuses:
  - `todo`;
  - `in_progress`;
  - `waiting_owner`;
  - `waiting_provider`;
  - `ready_to_apply`;
  - `done`;
  - `blocked`;
  - `not_needed`.
- Separate `admin_support_app` now lets allowed roles update external setup status and safe notes from the readiness/checklist screen.
- Manual owner status does not override production readiness. Real readiness still depends on actual DNS/env/HTTPS/provider checks.
- No public VPN installer was rebuilt for this entry unless a later client build explicitly replaces the aliases.

## 2026-05-04 Admin/Support App Backend Candidate

- Backend source version bumped to `0.8.1`.
- Added admin user-detail endpoint `GET /api/v1/admin/users/{user_id}` for the separate support/admin app.
- User detail returns account state, subscription, devices, billing orders and recent support reports in one support-friendly payload.
- Backend support report listing now supports filters by `status`, `userId`, `email` and `deviceUid`.
- Admin billing order list now treats `status=all` as all orders instead of accidentally filtering for a literal `all` status.
- Separate `admin_support_app` now has a user card with account/subscription/devices/orders/reports.
- Support can manually disable or enable a user's device from that user card.
- Admin UI rendering was hardened with HTML escaping for user/report/order/auth strings.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - `node --check admin_support_app\app.js`
- Not deployed yet in this entry unless the following deploy check confirms SSH key access.

## 2026-05-04 Admin/Support Workflow Candidate

- Backend source version bumped to `0.8.2`.
- Added `support_report_comments` storage for support notes on user-submitted reports.
- Added `admin_audit_log` storage for manual admin/support actions.
- Added admin endpoints:
  - `GET /api/v1/admin/support/reports/{report_id}/comments`
  - `POST /api/v1/admin/support/reports/{report_id}/comments`
  - `GET /api/v1/admin/audit`
- Admin user search now accepts email, phone and device id through `GET /api/v1/admin/users?q=...`.
- Admin user detail now fetches the exact user id instead of depending on the first page of users.
- Mutating admin actions now write audit events: support status changes, support comments, mark-paid, device enable/disable, subscription update and manual tariff apply.
- Separate `admin_support_app` now has:
  - support report search by email/user id/device id;
  - user search by email/phone/device id;
  - support comments inside the report dialog;
  - `Аудит` section for action history.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - `node --check admin_support_app\app.js`
- Deployed on `37.220.85.211`.
- Live smoke passed:
  - `/healthz` reports `version: 0.8.2`;
  - `/api/v1/admin/users?limit=5` returns users;
  - `/api/v1/admin/support/reports?status=all&limit=5` returns reports;
  - `/api/v1/admin/audit?limit=5` returns an audit payload;
  - `/api/v1/admin/support/reports/{report_id}/comments` returns comments.

## 2026-05-04 Admin Staff/Roles Candidate

- Backend source version bumped to `0.8.3`.
- Deployed on `37.220.85.211`.
- Added prepared role matrix for the separate internal admin/support app:
  - `owner`
  - `admin`
  - `support`
  - `finance`
  - `readonly`
- Added `admin_staff` storage for internal team accounts without storing employee passwords.
- Added admin endpoints:
  - `GET /api/v1/admin/roles`
  - `GET /api/v1/admin/staff`
  - `POST /api/v1/admin/staff`
  - `POST /api/v1/admin/staff/{staff_id}`
- Added optional `X-Admin-Actor` audit header so actions can be attributed to a support/admin operator instead of only the shared MVP token.
- Role enforcement is intentionally marked as `prepared_not_enforced`; the shared `admin_token` still works so the team cannot get locked out before real staff auth exists.
- Separate `admin_support_app` now has:
  - `Кто работает` field on the login panel;
  - `Команда` section;
  - staff creation/update form;
  - role descriptions;
  - active/inactive toggle for staff records;
  - audit table actor column.
- Live smoke passed:
  - `/healthz` reports `version: 0.8.3`;
  - `/api/v1/admin/roles` returns all prepared roles;
  - `/api/v1/admin/staff` returns staff list;
  - `support@greenvpn.pro` was seeded as the first placeholder support operator;
  - latest audit event records actor `codex-smoke-0.8.3`.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - `node --check admin_support_app\app.js`

## 2026-05-04 Support Triage/SLA Candidate

- Backend source version bumped to `0.8.4`.
- Deployed on `37.220.85.211`.
- Added internal support workflow metadata for user reports:
  - statuses: `new`, `triage`, `in_progress`, `waiting_user`, `resolved`, `closed`;
  - priorities: `urgent`, `high`, `normal`, `low`;
  - categories: `vpn_connect`, `network`, `auth`, `payment`, `installer`, `app_ui`, `general`.
- New support reports are automatically triaged by summary/report keywords into a category, priority, reason and SLA due time.
- Added support report fields: `category`, `triage_reason`, `sla_due_at`, `first_response_at`.
- Added admin endpoint `GET /api/v1/admin/support/workflow`.
- Admin support report list now supports filters by `category`, `priority`, and `assignedTo`.
- Support status update can now also update priority, category and SLA due time.
- First support comment/status response stores `first_response_at` for later support SLA analytics.
- Separate `admin_support_app` now has:
  - priority/category filters in `Поддержка`;
  - category, priority and SLA columns in the support report table;
  - editable status/priority/category/SLA fields in the report dialog;
  - triage reason visible to support.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - static admin app id/reference check with Python
- `node --check admin_support_app\app.js` could not be run in this Windows session because `node.exe` returned `Access is denied`; this is an environment issue, not a known JS syntax failure.
- Live smoke passed:
  - `/healthz` reports `version: 0.8.4`;
  - `/api/v1/admin/support/workflow` returns statuses/priorities/categories;
  - `/api/v1/admin/support/reports` returns the new support report fields.

## 2026-05-04 Internal Incidents Candidate

- Backend source version bumped to `0.8.5`.
- Deployed on `37.220.85.211`.
- Added internal incident storage for admin/support monitoring:
  - `admin_incidents` table;
  - incident statuses: `open`, `investigating`, `mitigated`, `resolved`;
  - incident severities: `critical`, `high`, `medium`, `low`.
- Monitoring and service-availability checks now sync into incident records:
  - red/yellow checks create or reopen incidents;
  - green checks auto-resolve matching open incidents;
  - details are stored as sanitized JSON without secrets.
- Added admin endpoints:
  - `GET /api/v1/admin/incidents`
  - `POST /api/v1/admin/incidents/{incident_id}`
- Admin overview now includes open incident count after synchronizing monitoring state.
- Separate `admin_support_app` now has:
  - `Инциденты` section;
  - status/severity filters;
  - incident table with affected service/endpoint, assignee and last-seen time;
  - actions `В работу`, `Решено`, and `Открыть снова`.
- Incident updates write `admin_incident_updated` audit events and support optional `X-Admin-Actor`.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - static admin app id/reference check with Python
- `node --check admin_support_app\app.js` could not be run in this Windows session because `node.exe` returned `Access is denied`; this is the same local environment issue seen during 0.8.4.
- Live smoke passed:
  - `/healthz` reports `version: 0.8.5`;
  - `/api/v1/admin/incidents` returns workflow and incident payload;
  - incident update works and writes audit actor `codex-smoke-0.8.5b`;
  - `/api/v1/admin/overview` reports the open incident count after sync.

## 2026-05-04 Managed Service Monitoring Candidate

- Backend source version bumped to `0.9.0`.
- Deployed on `37.220.85.211`.
- Added internal monitoring target storage:
  - `monitoring_targets`;
  - statuses: `active`, `paused`, `disabled`;
  - target types: `web`, `api`, `dns`, `tcp`, `tls`, `telegram`, `discord`, `youtube`, `payment`, `update`, `bootstrap`, `social`.
- Added service availability observation storage:
  - `service_availability_observations`;
  - statuses: `green`, `yellow`, `red`, `unknown`;
  - probe id, probe region, latency, message, sanitized details.
- Added backend seed targets for important services and infrastructure targets:
  - YouTube;
  - Discord;
  - Telegram;
  - Green VPN API health;
  - production API domain;
  - Windows update manifest;
  - payment return page.
- Added admin endpoints:
  - `GET /api/v1/admin/monitoring/targets`
  - `POST /api/v1/admin/monitoring/targets`
  - `POST /api/v1/admin/monitoring/targets/{target_id}`
  - `GET /api/v1/admin/monitoring/service-observations`
  - `POST /api/v1/admin/monitoring/service-observations`
- Service availability observations can create/resolve internal incidents through the existing incident sync layer.
- Separate `admin_support_app` now has an internal `Мониторинг` section:
  - monitoring target form;
  - status/service filters;
  - target table with latest status;
  - service availability observation table;
  - summary cards for green/problem targets and failed checks over 24h.
- This is internal admin/support monitoring only. Do not expose it as a normal user-facing Green VPN screen.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
- `node.exe` is blocked by Windows `Access is denied` in this session, so JS syntax could not be checked with `node --check`; inserted admin UI references were inspected statically.
- Live smoke passed:
  - `/healthz` reports `version: 0.9.0`;
  - admin monitoring targets endpoint returns seeded targets;
  - a safe paused `codex_service_smoke` target was upserted;
  - a green service availability observation was created for that smoke target;
  - observation listing returned `summaryFailed24h: 0`.

## 2026-05-04 Managed Server Catalog Candidate

- Backend source version bumped to `0.8.7`.
- Deployed on `37.220.85.211`.
- Added internal managed server catalog groundwork for the separate admin/support app:
  - `server_catalog_entries` table;
  - prepared statuses: `draft`, `healthy`, `degraded`, `maintenance`, `disabled`;
  - prepared protocols/transports for the later resilience layer.
- Added admin endpoints:
  - `GET /api/v1/admin/server-catalog`
  - `POST /api/v1/admin/server-catalog`
  - `POST /api/v1/admin/server-catalog/{entry_id}`
- Public `/api/v1/catalog/servers` deliberately still exposes only the proven working endpoint `intelligent_smew` / `37.220.85.211:443`; managed entries are not published to normal clients yet.
- Added role permissions `servers.read` and `servers.manage` to the prepared admin role matrix.
- Separate `admin_support_app` now has:
  - `Серверы` section;
  - public catalog summary;
  - managed server form;
  - status/active filters;
  - actions to edit, mark healthy, or disable an internal server entry.
- Server catalog changes write audit events with optional `X-Admin-Actor`.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - static admin app id/reference check with Python
- `node.exe` is still blocked by Windows `Access is denied` in this session, so JS syntax was checked with static balance/id checks instead.
- Live smoke passed:
  - `/healthz` reports `version: 0.8.7`;
  - public catalog still returns one client-visible server;
  - admin server catalog endpoint returns workflow, public catalog and managed entries;
  - a disabled internal smoke entry `codex_disabled_smoke` was created without exposing it to the public catalog.

## 2026-05-04 Account And Support Report Candidate

- Backend deployed as `0.7.3` on `37.220.85.211`.
- Added `/api/v1/support/reports`.
- Added `support_reports` storage for encoded user support reports.
- Normal user Settings -> Account was simplified to only `Почта` and `Телефон`; separate noisy rows `Подтвердить почту` and `Привязать телефон` were removed from the default settings screen.
- Settings -> Support now sends a coded `GVPN1.` report to backend instead of only copying it to clipboard.
- The support report excludes passwords, tokens, private keys, and WireGuard config contents.
- Language selector is locked to `Русский` until real i18n is implemented, so the app no longer exposes a fake broken English toggle.
- Dark theme switch thumb was softened to fit the Green VPN theme.
- Live smoke test passed: synthetic user submitted `/api/v1/support/reports` and backend returned `status: received`.
- Local test cleanup was run after building: `%LOCALAPPDATA%\Programs\Green VPN`, `C:\ProgramData\BlueVPN\state\session.dat`, `GreenVPNService`, and `WireGuardTunnel$BlueVPNDev1` were absent after cleanup.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - `dart format lib\main.dart`
  - `flutter build windows --release -t .\lib\main.dart`
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_AccountSupportReport_20260504.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- SHA256: `FD94A3B9B02161EF40392F441B748053E720A0B233EBA603B5313FB2C452C0DF`
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_2028_payment_confirmation_ok` until this candidate is user-tested.

## 2026-05-04 SMS/Phone And External Services Readiness Candidate

- Backend deployed as `0.7.2` on `37.220.85.211`.
- Added phone/SMS account groundwork:
  - `/api/v1/auth/phone/status`
  - `/api/v1/auth/phone/start`
  - `/api/v1/auth/phone/verify`
  - `/api/v1/admin/sms/readiness`
- Added safe SMS storage model: confirmation codes are hashed with server-only pepper, and queued outbox text masks the real code.
- Added SMS.ru production configuration support through server-only env variables.
- Added Settings -> Account phone binding UI. Without SMS.ru credentials it stays in a safe prepared/not-configured state.
- Added `C:\Users\gekto\projects\bluevpn\scripts\configure_backend_env_wsl.sh` and `C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1` to configure SMTP, SMS.ru, YooKassa, public URLs, and return/webhook URLs on the server without writing secrets into the repo.
- Added `C:\Users\gekto\projects\bluevpn\docs\EXTERNAL_SERVICES_CHECKLIST_RU.md` with the exact external-service checklist for the user.
- Live `/healthz` returns `version: 0.7.2`; `paymentsProductionReady`, `emailProductionReady`, and `smsProductionReady` remain `false` until real external credentials are configured.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - `dart format lib\main.dart`
  - `flutter build windows --release -t .\lib\main.dart`
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`
- `flutter analyze` still exits non-zero because of existing warning/info lint noise in the large legacy Flutter file; the release build and release gate are green.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_SMSPhoneReadinessCandidate_20260504.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- SHA256: `DE8022B0A0774E269DF053FA427DA3C8B84B0BCF14D41E46B2B2089190D108F3`
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_2028_payment_confirmation_ok` until this candidate is user-tested.

## 2026-04-30 Hotfix

- Removed remaining Windows-service experiment traces from the active build.
- Earlier hotfix temporarily kept the legacy admin-shortcut/UAC launch model from the last working Green VPN build; this is superseded by the later no-launch-UAC task guard build below.
- Hid the installer PowerShell self-elevation window where possible.
- Disabled MVP subscription gating locally so `subscription_inactive` does not block VPN connect.
- Deployed backend `0.6.1` to `37.220.85.211`; `/healthz` now reports `subscriptionEnforced: false`, and current Trial users can fetch `/api/v1/client/config` again while direct paid tariff activation remains disabled.
- Added client fallback to reuse the existing `C:\ProgramData\BlueVPN` config if the server config fetch is temporarily blocked.
- Strengthened the WSL backend relay launch so the client keeps a real hidden `wsl.exe` relay process while the app is open.

## 2026-04-30 Public UI Cleanup

- Removed the `Backend Admin` entry from the normal user settings screen.
- Removed the traffic slider and numbered traffic icons from the user tariff screen.
- Rebuilt `GreenVPN_Setup.exe`, `GreenVPN_Setup_LATEST.exe`, and `GreenVPN_Setup_PublicUI_20260430.exe`.

## 2026-04-30 Public Installed Names Cleanup

- Closed stale hidden installer PowerShell/cmd processes that were holding `%LOCALAPPDATA%\Programs\Green VPN`.
- Verified a nested create/delete probe inside `%LOCALAPPDATA%\Programs\Green VPN` succeeds after closing the stale process.
- Changed installer payload from `BlueVPN_payload.zip` to `GreenVPN_payload.zip`.
- Changed installed executable from `bluevpn.exe` to `greenvpn.exe`.
- Changed installed uninstall script from `uninstall_bluevpn.ps1` to `uninstall_greenvpn.ps1`.
- Changed installed support tools to `doctor_greenvpn.ps1` and `greenvpn_network_recover.ps1`.
- Kept internal tunnel/config names unchanged for compatibility with the working VPN tunnel.

## 2026-04-30 Boot Conflict Fix

- Root cause: `wireguard.exe /installtunnelservice` leaves `WireGuardTunnel$BlueVPNDev1` as `AUTO_START`, so Windows can auto-start Green VPN's full-tunnel service on reboot and conflict with Amnezia/WARP/other VPN services.
- Fixed connect flow: after installing `BlueVPNDev1`, Green VPN now runs `sc config WireGuardTunnel$BlueVPNDev1 start= demand` before starting the tunnel.
- Added `tools\greenvpn_boot_repair.ps1` for existing/tester machines. It removes only the Green VPN tunnel service `BlueVPNDev1` and Green VPN startup entries, leaving Amnezia/WARP alone.
- Current already-installed machines still need the repair script or reinstalling this new installer once, because the old service may already be registered as `AUTO_START`.

## 2026-04-30 Single Active VPN Guard

- Root cause after boot repair: Amnezia can already own the active full-tunnel route (`device20_full`), while Green VPN tries to install/start its own WireGuard full tunnel.
- Added preflight before Green VPN connect: detect active WireGuard/Wintun/Amnezia/WARP/Cloudflare adapters and running tunnel services.
- If another VPN is active, Green VPN now blocks connect with a human message instead of trying to overlay routes/DNS and risking a dead network.
- Autostart remains acceptable for the UI/background app, but tunnel autostart remains disabled. Green VPN must not auto-connect over another active VPN.
- Strengthened the normal-user UI preflight to use both `Get-NetAdapter -IncludeHidden` and `Get-CimInstance` so it detects active Amnezia/WireGuard/WARP before starting the SYSTEM task. Verified on the test machine with `adapter:device20_full` and `service:AmneziaWGTunnel$device20_full`.

## 2026-04-30 Native Windows Service Candidate

- Added `windows\green_vpn_service\main.cpp` and CMake target `greenvpn_service.exe`.
- Installer now installs `GreenVPNService` once under LocalSystem with a local service API on `127.0.0.1:48737`.
- Service endpoints: `/ping`, `/status`, `/connect`, `/disconnect`.
- The service reuses the proven `tools\greenvpn_vpn_task.ps1` path for privileged WireGuard actions, so the risky WireGuard tunnel logic did not get rewritten.
- Flutter UI now tries `GreenVPNService` first for connect/disconnect and falls back to `GreenVPNConnect` / `GreenVPNDisconnect` scheduled tasks if the service is unavailable.
- Fixed installer service creation to use `New-Service` instead of fragile `sc.exe create` quoting for `%LOCALAPPDATA%\Programs\Green VPN`.
- Install-test passed: `GreenVPNService` reached `Running`, `/ping` returned OK, `/status` returned OK with tunnel state `missing`.
- After install-test, the local test install was cleaned again: no Green VPN install dir, no `C:\ProgramData\BlueVPN`, no Green VPN service, no Green VPN tasks, no Green VPN shortcuts.
- User confirmed the native-service build works: app launches, login/session works, VPN flow works well enough to continue.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_163530_native_service_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `9335A64355097B5EB388C3751CEFF8BBF6ABBF5F12BC7EE82D89FEA3498BAD80`.
- Next step is tray/background mode, with the native-service build kept as the rollback anchor.

## 2026-04-30 Backend 0.6.2 Device Limit Hotfix

- Root cause: repeated reinstall/cleanup removed local `device_id.txt`, so the same tester account could accumulate more than `maxDevices` old enabled devices and `/api/v1/client/config` returned `Device limit exceeded`.
- Backend now counts enabled devices and, for MVP/test flow, auto-disables the oldest enabled device for the same user when a new current device would exceed the plan limit.
- Deploy completed on `37.220.85.211`; `/healthz` reports `version: 0.6.2` and `autoReplaceOldestDeviceOnLimit: true`.
- Verified with a synthetic account: six sequential device registrations/config fetches succeeded; total devices became 6, enabled devices stayed 5, the oldest device was disabled with `auto_replaced_by_new_device`.
- WSL SSH deploy key configured locally at `~/.ssh/greenvpn_ed25519`; password is not stored in the repository or docs.

## 2026-04-30 No-Launch-UAC Task Guard

- Removed the `Run as administrator` shortcut flag from installer-created desktop and Start menu shortcuts.
- Installer now launches `greenvpn.exe` normally after installation, not through `Start-Process -Verb RunAs`.
- Removed the old app self-relaunch path for VPN connect/disconnect.
- Added installer-created SYSTEM scheduled tasks:
  - `GreenVPNConnect` starts only `BlueVPNDev1`.
  - `GreenVPNDisconnect` stops/uninstalls only `BlueVPNDev1`.
  - `GreenVPNGuard` runs every minute and disconnects Green VPN if another VPN adapter/service becomes active.
- User-facing expectation: UAC should appear during installation/repair, not on every Green VPN app launch.
- The installer exe now embeds a `requireAdministrator` manifest, so the install-time UAC should belong to `GreenVPN_Setup.exe` itself instead of a separate PowerShell elevation prompt.
- The installer bootstrap now uses hidden `install.vbs` instead of `install.cmd`, so installation should not show a separate PowerShell/cmd window.

## 2026-04-30 Full Uninstaller

- Strengthened installed `uninstall_greenvpn.ps1`.
- Added one-click `uninstall_greenvpn.cmd` next to the app.
- Uninstall removes Green VPN scheduled tasks, startup entries, shortcuts, installed files, old BlueVPN/GreenVPN app-data folders, and `C:\ProgramData\BlueVPN` by default.
- Uninstall removes only Green VPN's WireGuard tunnel `BlueVPNDev1`; it intentionally does not remove WireGuard, Amnezia, WARP, or other VPN clients.
- Optional `-KeepProgramData` is available for support/debug cases where logs/config/state must be preserved.

## 2026-04-30 Cleanup Script Hardening

- `greenvpn_clean_previous_install.ps1` now self-elevates through UAC when service/task removal needs administrator rights.
- The cleanup script now verifies that `GreenVPNService`, Green VPN scheduled tasks, `WireGuardTunnel$BlueVPNDev1`, `%LOCALAPPDATA%\Programs\Green VPN`, and `C:\ProgramData\BlueVPN` are gone.
- If the empty install folder is still locked by a stale WSL backend relay, the cleanup script runs `wsl --shutdown` and retries the removal.
- Manual cleanup verification on the test machine passed: no Green VPN service, no Green VPN tasks, no Green VPN processes, no Green VPN install folder, and no `C:\ProgramData\BlueVPN`.

## 2026-04-30 Clean Installer Rebuild

- Removed old `BlueVPN_Setup*.exe` and `GreenVPN_Setup*.exe` files from `C:\BlueVPN_Builds` before rebuilding, leaving only the fresh `GreenVPN_Setup.exe` and `GreenVPN_Setup_LATEST.exe`.
- Cleaned local installed remnants before the rebuild: `%LOCALAPPDATA%\Programs\Green VPN`, Green VPN shortcuts, Green VPN scheduled tasks, `C:\ProgramData\BlueVPN`, and the Green VPN WireGuard tunnel `BlueVPNDev1`.
- Root cause of a stuck empty install directory was an old WSL backend relay process holding `%LOCALAPPDATA%\Programs\Green VPN`; the relay was stopped and the folder was removed.
- Rebuilt the installer from the current release payload and verified release gates against both source and installer payload.

## 2026-04-30 Installer UI Candidate

- Replaced the default IExpress finish/error message boxes with a custom WinForms `Green VPN Installer` UI.
- The installer UI now shows a branded white/green card, blue accent line, marquee progress bar, live install stage text, and the real Green VPN app icon.
- `FinishMessage` in the IExpress SED is intentionally blank, so Windows should no longer show the old grey `Green VPN installed successfully.` dialog.
- `install_ui.ps1` is generated with ASCII UI strings to avoid PowerShell encoding/mojibake parser failures.
- The extra `Open log` button was removed. On failure, the UI still shows the log path in text.
- Generated `install_ui.ps1` parse check passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Superseded by the support-report candidate below.

## 2026-04-30 Support Report Candidate

- Settings entry `Диагностика` was renamed to `Поддержка`.
- The user-facing support screen no longer shows raw endpoint/path/route technical details.
- The screen now shows only simple human status lines: system component, VPN config, connection, and other VPN state.
- The copy action now creates a coded support report with prefix `GVPN1.` using JSON + gzip + base64url.
- The report excludes passwords, tokens, private keys, and config contents. It may include sanitized runtime status needed by support.
- Flutter Windows release build passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Generated installer UI script parse check passed.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no install folder, no `C:\ProgramData\BlueVPN`, no Green VPN tasks, no Green VPN processes.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportCandidate_20260430.exe`, SHA256 `0FEF4326F81F58002C229B026B991F0A172EF89E2872E22C6C8A642D58FCEFBC`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_1730_dev_admin_cleanup_ok` until the user confirms this support-report candidate behaves correctly.

## 2026-04-30 Update Manifest Candidate

- Fixed the custom installer window logo: the UI no longer tries to render the `.ico` through `PictureBox` / `ToBitmap`, which produced a noisy corrupted square on the test machine.
- Installer UI now draws a simple Green VPN key mark directly in WinForms, while the window/exe still use the normal Green VPN icon.
- Added the first simple updater surface in the user app: `Настройки` -> `Обновления`.
- Client now has a single `kAppVersion` constant and calls `/api/v1/updates/windows?currentVersion=...`.
- Backend deployed as `0.6.3` on `37.220.85.211`.
- Backend update endpoint returns `latestVersion`, `downloadUrl`, `sha256`, `required`, `releasedAt`, and `changelog`.
- Current manifest intentionally points to the same version and has an empty download URL until update hosting is configured.
- Flutter Windows release build passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Generated installer UI script parse check passed.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no install folder, no `C:\ProgramData\BlueVPN`, no Green VPN tasks, no Green VPN services, no Green VPN processes.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_UpdateManifestCandidate_20260430.exe`, SHA256 `96CA9FD1F02A4EE2BE135F8E99A9F8105A4B074DE2022DD2797D684DDB3178F8`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_1845_update_manifest_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `96CA9FD1F02A4EE2BE135F8E99A9F8105A4B074DE2022DD2797D684DDB3178F8`.

## 2026-04-30 Catalog And Monitoring Candidate

- Added backend `/api/v1/catalog/servers` as the first simple server catalog.
- Catalog currently exposes one healthy available endpoint: `intelligent_smew` / Netherlands #1 / `37.220.85.211:443` / WireGuard UDP.
- Added backend `/api/v1/monitoring/status` with basic checks for backend, SQLite database, WireGuard, server catalog, update manifest, and payments.
- Backend deployed as `0.6.4` on `37.220.85.211`.
- Live backend checks passed: `/healthz`, `/api/v1/catalog/servers`, and `/api/v1/monitoring/status`.
- Client server picker now refreshes the catalog from backend and shows endpoint protocol, latency, and health score.
- Client now sends selected `serverId` to `/api/v1/client/config`; backend validates it but still uses the current proven WireGuard endpoint, so the working config flow is not rewritten.
- At this intermediate stage Settings had `Состояние сервисов`, showing the monitoring summary and individual checks. This user-facing entry was removed later in the Payments Hardening Candidate.
- Release gate was extended to require the new catalog and monitoring endpoints.
- Flutter Windows release build passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Generated installer UI script parse check passed.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no install folder, no `C:\ProgramData\BlueVPN`, no Green VPN tasks, no Green VPN services, no Green VPN processes.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_CatalogMonitoringCandidate_20260430.exe`, SHA256 `CBC8996D08A8FD4DB0F9270DF5C24E0E1CD32A0E95F8369FF5D6A61447586611`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_1845_update_manifest_ok` until the user confirms this catalog/monitoring candidate behaves correctly.

## 2026-04-30 Internal Service Checks Candidate

- Added backend `/api/v1/monitoring/services` for internal/support monitoring of YouTube, Discord, and Telegram availability.
- Backend deployed as `0.6.5` on `37.220.85.211`.
- Live check passed: YouTube, Discord, and Telegram were green from the current backend/VPN-server egress point.
- Important product boundary: this endpoint is not exposed as a normal user-facing screen in the Green VPN client. It is for future admin/support/alerting workflows.
- A bad intermediate `GreenVPN_Setup_ServiceAvailabilityCandidate_20260430.exe` briefly exposed this as a user screen; that artifact was deleted and must not be used.
- At this intermediate stage the normal user app showed only `Состояние сервисов` and `Поддержка`, not raw YouTube/Discord/Telegram probe details. `Состояние сервисов` was removed later from the user UI; monitoring remains internal/admin groundwork.
- Flutter Windows release build passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Generated installer UI script parse check passed.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no install folder, no `C:\ProgramData\BlueVPN`, no Green VPN tasks, no Green VPN services, no Green VPN processes.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_InternalServiceChecksCandidate_20260430.exe`, SHA256 `F261CC3613D3FA730F38F2EBCE0A3FA2F6B4E6C98B432E1C326D80CB825048AA`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- User confirmed the build works well enough to continue.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_1928_internal_service_checks_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `F261CC3613D3FA730F38F2EBCE0A3FA2F6B4E6C98B432E1C326D80CB825048AA`.
- Next planned roadmap step is production-payment preparation.

## 2026-04-30 Payment History / Auto-Renew Candidate

- Backend deployed as `0.6.6` on `37.220.85.211`.
- Added user endpoint `GET /api/v1/billing/orders` for the current user's order history.
- Added user endpoint `POST /api/v1/subscription/auto-renew/cancel`.
- Public user billing responses no longer include raw provider payment ids.
- Subscription status now includes safe public flags `autoRenew` and `paymentMethodSaved`.
- At this intermediate stage the tariff screen showed a simple `История заказов` section and an `Отключить автопродление` action when applicable. `История заказов` was removed later from the user tariff UI because it cluttered the screen.
- Live backend test passed with a synthetic user: order creation returned `pending`, order history returned the order, auto-renew cancel returned `autoRenew=false`, and provider ids did not leak in the user order response.
- Flutter Windows release build passed.
- `python -m py_compile backend_live\app\main.py` passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload contents were checked: `app\greenvpn.exe`, `app\greenvpn_service.exe`, `tools\greenvpn_boot_repair.ps1`, and `tools\greenvpn_vpn_task.ps1` are present.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no Green VPN service, tasks, shortcuts, install folder, or Green VPN processes remained.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_PaymentHistoryCandidate_20260430.exe`, SHA256 `CC736F5EB07DEA053386CE3718FB3153814D42BECE7FC4B67BFA26E8CB78247B`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_1928_internal_service_checks_ok` until the user confirms this payment-history candidate behaves correctly.

## 2026-04-30 Payments Hardening Candidate

- Removed the user-facing Settings entry `Состояние сервисов`; monitoring stays backend/internal/admin groundwork and must not be exposed as a normal user screen.
- Removed the tariff page `История заказов`; the user tariff screen stays focused on choosing and paying for the current tariff.
- Backend deployed as `0.6.7` on `37.220.85.211`.
- Pending YooKassa orders can now be synced through provider payment lookup by saved payment id when YooKassa credentials are configured.
- YooKassa webhook handling now validates order metadata, payment id, amount, and currency before marking an order paid and activating a tariff.
- Live synthetic backend checks passed: correct `payment.succeeded` webhook activated a pending order; amount mismatch was rejected with HTTP `409`; public user order response did not leak provider payment ids.
- Flutter Windows release build passed.
- `python -m py_compile backend_live\app\main.py` passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload contents were checked: `app\greenvpn.exe`, `app\greenvpn_service.exe`, `tools\greenvpn_boot_repair.ps1`, `tools\greenvpn_vpn_task.ps1`, `tools\greenvpn_network_recover.ps1`, and `tools\doctor_greenvpn.ps1` are present.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no Green VPN service, tasks, shortcuts, install folder, ProgramData state, or Green VPN processes remained.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_PaymentsHardeningCandidate_20260430.exe`, SHA256 `0C504DD845E04B15EE36FC912C5F885DC59FB52F5E60241AF74FEA9CB265C8A3`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_2005_payments_hardening_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `0C504DD845E04B15EE36FC912C5F885DC59FB52F5E60241AF74FEA9CB265C8A3`.
- Next planned roadmap step is production-payment readiness: domain, HTTPS, YooKassa production keys, real webhook URL, and payment confirmation flow.

## 2026-04-30 Production Payments Readiness Candidate

- Backend deployed as `0.6.8` on `37.220.85.211`.
- Added payment production-readiness checks without exposing secrets:
  - `YOOKASSA_SHOP_ID` / `YOOKASSA_SECRET_KEY` configured.
  - `YOOKASSA_RETURN_URL` is real HTTPS and not a local placeholder.
  - `YOOKASSA_WEBHOOK_URL` or `GREENVPN_PUBLIC_BASE_URL` points to real HTTPS.
  - `GREENVPN_PUBLIC_BASE_URL` is set for the production API origin.
  - `YOOKASSA_API_BASE` uses HTTPS.
- Added admin endpoint `GET /api/v1/admin/billing/readiness`.
- `/healthz` now exposes `paymentsProductionReady` as a boolean so monitoring/admin can distinguish MVP manual mode from production payment readiness.
- Monitoring `Payments` check now uses the production-readiness result, not only the presence of YooKassa keys.
- YooKassa webhook handling now treats the incoming webhook payload as a signal only. If YooKassa credentials are configured, backend fetches the authoritative payment from YooKassa by payment id before applying payment status to a Green VPN order.
- Live backend checks passed on `37.220.85.211`: `/healthz` reports `version: 0.6.8` and `paymentsProductionReady: false` until real production domain/HTTPS/keys are configured.
- Live admin readiness check passed: provider is `manual_mvp`, production is not ready yet, and required actions correctly list YooKassa keys plus real HTTPS return/webhook/public base URLs.
- Live synthetic webhook check passed in current manual-MVP mode: pending order became `activated`; public user order response did not leak provider payment ids.
- Flutter Windows release build passed.
- `python -m py_compile backend_live\app\main.py` passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no Green VPN service, tasks, shortcuts, install folder, ProgramData state, or Green VPN processes remained.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_ProductionPaymentsCandidate_20260430.exe`, SHA256 `4594ADC55FB813764296AE68C6491731F431C0FFBDE8BFFF67E5BD649D26C9A3`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_2015_production_payments_readiness_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `4594ADC55FB813764296AE68C6491731F431C0FFBDE8BFFF67E5BD649D26C9A3`.
- Next planned roadmap step is payment confirmation flow: automatic order polling in the client and a return page for browser-based YooKassa checkout.

## 2026-04-30 Payment Confirmation Flow Candidate

- Backend deployed as `0.6.9` on `37.220.85.211`.
- Added hosted payment return page `GET /payment/return` for YooKassa redirect checkout. It tells the user to return to Green VPN and that the app checks payment automatically.
- Client now starts automatic polling for a pending billing order after creating/loading/opening payment. Manual `Проверить оплату` remains as a fallback.
- Background polling does not flip the whole tariff page into busy mode every few seconds.
- Pending order UI copy now says Green VPN checks payment automatically.
- Canceled/expired orders are cleared from the pending local order state instead of staying forever.
- Live backend checks passed on `37.220.85.211`: `/healthz` reports `version: 0.6.9`, `/payment/return` returns the Green VPN payment page, and admin readiness still reports required production YooKassa/HTTPS actions.
- Live synthetic webhook check passed in current manual-MVP mode: pending order became `activated`; public user order response did not leak provider payment ids.
- Flutter Windows release build passed.
- `python -m py_compile backend_live\app\main.py` passed.
- Source release gate passed with 0 warnings and 0 errors.
- Installer payload release gate passed with 0 warnings and 0 errors.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate: no Green VPN service, tasks, shortcuts, install folder, ProgramData state, or Green VPN processes remained.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_PaymentConfirmationCandidate_20260430.exe`, SHA256 `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`.

## 2026-04-30 Email Confirmation Candidate

- Backend deployed as `0.7.0` on `37.220.85.211`.
- Added email confirmation storage: `users.email_verified`, `users.email_verified_at`, `email_confirmations`, and `email_outbox`.
- Added public email endpoints: `/api/v1/auth/email/status`, `/api/v1/auth/email/resend`, GET/POST `/api/v1/auth/email/verify`.
- Added admin readiness endpoint `/api/v1/admin/email/readiness`.
- Registration now creates a confirmation token and queues/sends a confirmation email. If SMTP is not configured, it stays in `not_configured` mode and does not block login/VPN.
- Client Settings -> Account now shows email confirmation status and a `Подтвердить почту` action. This is intentionally small user-facing UI, not a new dev/admin screen.
- Live backend checks passed: `/healthz` reports `version: 0.7.0`; synthetic registration created a pending email confirmation; resend returned `not_configured`; verification link consumption set `emailVerified=true`.
- Email production readiness currently requires external/user actions: real HTTPS public base URL, SMTP host, and SMTP sender address.
- Flutter Windows release build passed.
- `bluevpn_release_gate.ps1 -StrictPaymentGate` passed with 0 warnings/errors.
- Payload release gate passed with 0 warnings/errors.
- Previous installed Green VPN test build was cleaned before issuing the new installer.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_EmailConfirmationCandidate_20260430.exe`, SHA256 `1099C4254E137CFEB7F5611CD0F44526DD8807D5CFF16A218D65925FA5A01AC5`.
- Payload zip: `C:\BlueVPN_Builds\GreenVPN_EmailConfirmationCandidate_payload_20260430.zip`, SHA256 `9A23F744110A5891B0D127B07915DCE9C8782AD79D057DC3A2C1AC44485E0031`.
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe` were synced to the same candidate hash.
- Not yet frozen as rollback. Current rollback remains `ROLLBACK_20260430_2028_payment_confirmation_ok` until the user confirms this email-confirmation candidate behaves correctly.

## 2026-04-30 System Task Registration Fix

- Fixed installer task creation for install paths with spaces, especially `%LOCALAPPDATA%\Programs\Green VPN\tools\greenvpn_vpn_task.ps1`.
- Root cause: `schtasks.exe /TR` split the quoted `Green VPN` path incorrectly, so app files installed but `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard` were not created.
- Replaced task creation with `Register-ScheduledTask` / `New-ScheduledTaskAction` so quoted paths are preserved.
- Fixed task ACLs: installer now grants normal users read/execute rights on `GreenVPNConnect`, `GreenVPNDisconnect`, and `GreenVPNGuard`, because tasks created as `SYSTEM` were present but returned `Access is denied` to the non-admin UI.
- Added a post-registration check that fails installation if any required Green VPN system task is missing.
- Removed incompatible `New-ScheduledTaskSettingsSet -DisallowStartIfOnBatteries` usage for Windows PowerShell 5.1 on the test machine.
- Added installer transcript logging to `%TEMP%\GreenVPN_Setup.log`; failures now show the log path in the installer error dialog.
- Fixed clean-before-register flow: installer no longer calls `schtasks.exe /Delete` for missing tasks under `$ErrorActionPreference = 'Stop'`, which previously caused a false install failure before creating the new tasks.

## 2026-04-30 Tray/Background Candidate

- Added native Windows tray behavior in the runner without adding Flutter tray/window plugins, avoiding extra Developer Mode/symlink requirements for testers.
- Closing the Green VPN window now hides it instead of ending the process.
- Tray icon tooltip is `Green VPN`.
- Double-click/left-click on the tray icon restores the window.
- Right-click tray menu contains `Open Green VPN`, `Connect VPN`, `Disconnect VPN`, and `Exit`.
- `Connect VPN` and `Disconnect VPN` from the tray call existing `GreenVPNConnect` / `GreenVPNDisconnect` SYSTEM tasks, so the proven privileged path remains unchanged.
- `Exit` from the tray is the real UI process exit. The native `GreenVPNService` remains installed independently.
- `greenvpn_clean_previous_install.ps1` now also attempts to remove `GreenVPNService`; non-elevated cleanup cannot delete service/tasks and must rely on the next UAC installer repair path.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_TrayCandidate_20260430.exe`, SHA256 `0730AA12787F5E66961709EE4772C8B63FE8C076C9F3E43E407D6A266C666763`.
- Not yet frozen as rollback. Needs user test: install over previous build with UAC, close window to tray, restore from tray, connect/disconnect from tray, Exit from tray.

## 2026-04-30 Tray/Background Stable

- User confirmed the tray/background build works.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_165617_tray_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `0730AA12787F5E66961709EE4772C8B63FE8C076C9F3E43E407D6A266C666763`.
- Next step is autostart.

## 2026-04-30 Autostart Candidate

- Added native runner support for `--background` / `--tray`.
- Normal desktop/start menu shortcuts still open the full window.
- Installer writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\GreenVPN` with value `"greenvpn.exe" --background`.
- On Windows login, Green VPN should start into tray/background mode without showing the window.
- Autostart does not auto-connect VPN; it only starts the UI/tray process.
- Uninstaller and cleanup remove Green VPN startup entries.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_AutostartCandidate_20260430.exe`, SHA256 `4BE06006668E7E8B94401D61AE5B4B995B5A76013BAD09E762F7D50EE0492E34`.
- Not yet frozen as rollback. Needs user test: install with UAC, confirm Run entry exists, reboot Windows, confirm Green VPN appears in tray without auto-connecting or breaking Amnezia/WARP/WireGuard.

## 2026-04-30 Autostart Stable

- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_170548_autostart_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `4BE06006668E7E8B94401D61AE5B4B995B5A76013BAD09E762F7D50EE0492E34`.
- Next step is auth rewrite: cleaner login/register UX, human errors, successful registration should take the user forward instead of leaving them stuck.

## 2026-04-30 Auth Rewrite Candidate

- Successful fresh login/register now opens the main app directly instead of stopping on the saved-session gate.
- Saved-session gate still remains for app restarts, so a returning user can choose current account or another account.
- Auth error text is normalized so backend/network details like `HttpException`, `SocketException`, raw `User already exists`, and `Invalid credentials` do not leak into the normal UI.
- If registration hits "email already registered", the UI switches to the login tab and fills the same email/password for a quick retry.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_AuthCandidate_20260430.exe`, SHA256 `E84E0B9691498D33AC8F5CEFA3B53C0EB8A0DFC43DB856EDEDEB54AE5921AF7D`.
- Not yet frozen as rollback. Needs user test: register fresh email, register existing email, login existing email, wrong password, relaunch saved-session behavior.

## 2026-04-30 Auth Rewrite Stable

- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_171555_auth_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `E84E0B9691498D33AC8F5CEFA3B53C0EB8A0DFC43DB856EDEDEB54AE5921AF7D`.
- Next step is removing/hiding dev/admin UI from the normal user client.

## 2026-04-30 Dev/Admin UI Cleanup Candidate

- Removed the visible `Backend Admin` entry point from the normal user settings screen.
- Removed the debug/dev login button from the auth screen.
- Replaced the remaining user-facing `DEV:` config toast with a normal Russian message.
- Kept backend/admin source code in place for now, but it is unreachable from the normal user UI. Later it should move into a separate admin app/web panel.
- `flutter build windows --release -t .\lib\main.dart` passed.
- `bluevpn_release_gate.ps1 -StrictPaymentGate` passed with 0 warnings and 0 errors.
- `bluevpn_release_gate.ps1 -StrictPaymentGate -ReleaseZip C:\BlueVPN_Builds\_installer_work\GreenVPN_current_release_payload.zip` passed with 0 warnings and 0 errors.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_DevAdminCleanupCandidate_20260430.exe`, SHA256 `A13C945BB1A88EAF45779398258063A645A03A324827C3A1A2203557278C788B`.
- Latest aliases updated: `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`.
- Stable rollback remains `ROLLBACK_20260430_171555_auth_ok` until the user tests and accepts this candidate.
- Cleanup note: the Green VPN app/service/tasks were removed before the rebuild. An empty `%LOCALAPPDATA%\Programs\Green VPN` directory can remain if Explorer or Windows keeps a directory handle open; the next elevated installer reuses it safely.

## 2026-04-30 Dev/Admin UI Cleanup Stable

- User confirmed the dev/admin cleanup build works.
- Frozen as rollback: `C:\BlueVPN_Builds\ROLLBACK_20260430_1730_dev_admin_cleanup_ok\GreenVPN_Setup_ROLLBACK.exe`, SHA256 `A13C945BB1A88EAF45779398258063A645A03A324827C3A1A2203557278C788B`.
- Next planned roadmap step is support report instead of raw diagnostics.

## 2026-04-30 Boot/Slider Polish Candidate

- Startup now shows a branded Green VPN loading card with stage text instead of a bare spinner.
- Bootstrap keeps the loading card visible briefly so the app does not appear to flash into an unfinished state.
- User tariff page has the traffic slider back under the clean 5/20/50/100 GB package chips.
- Slider styling follows the Green VPN palette.
- `flutter build windows --release -t .\lib\main.dart` passed.
- `bluevpn_release_gate.ps1 -StrictPaymentGate` passed with 0 warnings and 0 errors.
- `bluevpn_release_gate.ps1 -StrictPaymentGate -ReleaseZip C:\BlueVPN_Builds\_installer_work\GreenVPN_current_release_payload.zip` passed with 0 warnings and 0 errors.
- Previous installed Green VPN artifacts were cleaned before issuing this candidate. A stale empty `%LOCALAPPDATA%\Programs\Green VPN` directory may remain if Windows keeps a directory handle open; there were no Green VPN processes/services after elevated cleanup and the installer can reuse the directory.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_BootSliderCandidate_20260430.exe`, SHA256 `DA239DFDE26DB62D0D9045BDCFB66C15A24FBC39C67F9E3417C1F2F6D005DBE5`.
- Latest aliases updated: `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`.
- Stable rollback remains `ROLLBACK_20260430_1730_dev_admin_cleanup_ok` until the user tests and accepts this candidate.

## 2026-04-30 Production Domain / HTTPS Bootstrap

- Domain purchased: `greenvpn.pro`.
- DNS provider: REG.RU DNS (`ns1.reg.ru`, `ns2.reg.ru`).
- Added DNS record: `A api -> 37.220.85.211`.
- Server nginx now has a dedicated `api.greenvpn.pro` reverse-proxy vhost to `http://127.0.0.1:8000`.
- Let's Encrypt certificate was issued successfully for `https://api.greenvpn.pro`; certbot renewal timer is installed.
- Backend systemd drop-in added at `/etc/systemd/system/bluevpn-backend.service.d/greenvpn-domain.conf`.
- Backend env now includes:
  - `GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro`
  - `GREENVPN_EMAIL_PUBLIC_BASE_URL=https://api.greenvpn.pro`
  - `GREENVPN_API_BASE_URLS=https://api.greenvpn.pro,http://37.220.85.211:8000`
  - `YOOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return`
  - `YOOKASSA_WEBHOOK_URL=https://api.greenvpn.pro/api/v1/billing/yookassa/webhook`
- Verified with forced DNS resolve: `https://api.greenvpn.pro/healthz` returns backend `version: 0.7.0`.
- Verified catalog bootstrap includes `https://api.greenvpn.pro` before the raw IP fallback.
- Public recursive DNS may lag shortly after the REG.RU change; forced resolve and authoritative REG.RU records are correct.

## 2026-05-04 Admin Analytics Candidate

- Backend source version bumped to `0.8.8`.
- Deployed on `37.220.85.211`.
- Added admin analytics endpoint `GET /api/v1/admin/analytics/summary`.
- Analytics currently summarizes business, support, incidents, updates, server catalog, auth, readiness, and 14-day trends.
- Separate `admin_support_app` now has `Аналитика` with revenue/orders/users/support/incidents/update/catalog/readiness cards.
- Analytics refresh also syncs monitoring incidents so the admin dashboard sees infrastructure/service failures before users report them.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - static admin HTML/JS id-reference scan
- Live smoke passed:
  - `/healthz` returned `version: 0.8.8`;
  - `/api/v1/admin/analytics/summary` returned `ok: true`;
  - analytics payload included users, revenue, support reports, incidents, orders and trends.
- This is internal admin/support functionality only. It must not be exposed inside the normal user VPN client.

## 2026-05-04 Server Health Observations Candidate

- Backend source version bumped to `0.8.9`.
- Deployed on `37.220.85.211`.
- Added internal `server_health_observations` storage for endpoint health probes.
- Added admin endpoints:
  - `GET /api/v1/admin/server-health`
  - `POST /api/v1/admin/server-health/observations`
- Health observations track endpoint id, probe id, probe region, protocol, transport, target, status, latency, packet loss, error code, message and details.
- A new observation updates the matching managed server catalog entry health/status/latency, but does not publish new endpoints to the public client catalog.
- Public `/api/v1/catalog/servers` remains safely limited to the proven `intelligent_smew` endpoint until real multi-server rollout rules are intentionally added.
- Separate `admin_support_app` now shows server health observations in `Серверы`.
- Admin analytics now includes server-health counters for observed endpoints and degraded/down checks.
- Local checks passed:
  - `python -m py_compile backend_live\app\main.py`
  - static admin HTML/JS id-reference scan; remaining missing ids are existing dynamic support-dialog controls generated by JS.
- Live smoke passed:
  - `/healthz` returned `version: 0.8.9`;
  - a sanitized admin smoke created a healthy observation for `intelligent_smew`;
  - `/api/v1/admin/server-health` returned that observation without exposing `admin_token`.
- This is the first backend piece of future endpoint health scoring. It is internal/admin-only and does not alter user routing yet.

## 2026-05-05 Staged Update Rollout Candidate

- Backend source version bumped to `0.9.7`.
- Backend `0.9.7` deployed on `37.220.85.211`.
- Public update manifests now accept stable `clientId` from the Windows client:
  - `/api/v1/updates/windows?currentVersion=<version>&clientId=<device_id>`;
  - `/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=<version>&clientId=<device_id>`.
- Manifest now returns `updateAvailable`, `baseUpdateAvailable`, `rolloutEligible`, `rolloutBucket`, `rolloutReason`, and `rolloutPercent`.
- Windows client sends its stored device id and trusts `updateAvailable` instead of doing only local string comparison.
- Separate `admin_support_app` update preview shows rollout eligibility and reason.
- This prepares safe staged rollout, holdback and required-update behavior without adding secrets or changing VPN/WireGuard internals.
- Live smoke passed:
  - `/healthz` returned `version: 0.9.7`;
  - `/api/v1/updates/windows?currentVersion=0.1.0&clientId=codex-smoke` returned `rolloutEligible: true` and `rolloutReason: full_rollout`;
  - `/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.1.0&clientId=codex-smoke` returned the same rollout fields.
- Local installed Green VPN artifacts were cleaned before rebuilding this installer.
- `flutter build windows --release -t .\lib\main.dart` passed via installer build.
- `bluevpn_release_gate.ps1 -StrictPaymentGate` passed with 0 warnings and 0 errors.
- New candidate installer: `C:\BlueVPN_Builds\GreenVPN_Setup_StagedUpdater_20260505.exe`, SHA256 `A26D3DA9C6F2C12D9FB3EF7B41E68716CCE20E1D875829F54EEFA48D6DFB6678`.
- Latest aliases updated: `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`.

## 2026-05-05 Safe Server Catalog Publication Gate Candidate

- Backend source version bumped to `0.9.9`.
- Backend `0.9.9` deployed on `37.220.85.211`.
- Public `/api/v1/catalog/servers` remains safe and unchanged for users: it still returns only the proven builtin `intelligent_smew` endpoint.
- Managed server catalog entries now include:
  - `publicEligibility`;
  - explicit `publicBlockers`;
  - latest health observation status/time;
  - 24h healthy/failed observation counters.
- Added internal admin endpoint `GET /api/v1/admin/server-catalog/publication-readiness`.
- The readiness endpoint explains whether managed endpoints can be published, why they are blocked, and what the next action is.
- Separate `admin_support_app` shows the publication gate in `Серверы`.
- This prepares the resilience/fallback roadmap without changing real user routing or WireGuard config delivery.
- Important safety rule: managed endpoints must remain blocked until managed endpoint peer/config provisioning exists.
- Rebuilt Windows installer candidate: `C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`, SHA256 `E0A861DE4B486E5FFC037C9D850B5E0F30C702F876DEAD536AB7BA43E53E7A54`.
- Latest aliases updated: `C:\BlueVPN_Builds\GreenVPN_Setup.exe` and `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`.

## 2026-05-05 Managed Endpoint Config-Readiness Candidate

- Backend source version bumped to `0.9.10`.
- Backend `0.9.10` deployed on `37.220.85.211`.
- Managed server catalog entries now include:
  - `clientConfigProfile`;
  - `clientConfigProfileTitle`;
  - `clientConfigReadiness`;
  - `clientConfigReady`.
- Added internal admin endpoint `POST /api/v1/admin/server-catalog/seed-current`.
- The endpoint seeds/updates `current_wg0` for the current working WireGuard endpoint:
  - host `37.220.85.211`;
  - port `443`;
  - protocol `wireguard_udp`;
  - transport `udp`;
  - client config profile `builtin_wg0`;
  - `clientConfigReady: true`;
  - `isPublic: false`.
- Separate `admin_support_app` now has `Добавить текущий endpoint` and a `Профиль выдачи конфига` field in `Серверы`.
- Public `/api/v1/catalog/servers` remains unchanged and still exposes only builtin `intelligent_smew`; `current_wg0` is internal until health/provisioning rollout rules are safe.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - `quickjs` syntax parse for `admin_support_app\app.js`;
  - live `/healthz` reports `version: 0.9.10`;
  - live `POST /api/v1/admin/server-catalog/seed-current` created/updated internal `current_wg0`;
  - live public `/api/v1/catalog/servers` still reports `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry because only backend/admin-support internals changed. Current public installer aliases remain:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`;
  - candidate copy `C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`;
  - SHA256 `E0A861DE4B486E5FFC037C9D850B5E0F30C702F876DEAD536AB7BA43E53E7A54`.

## 2026-05-05 Current Endpoint Health Scoring Candidate

- Backend source version bumped to `0.9.11`.
- Backend `0.9.11` deployed on `37.220.85.211`.
- Correct public server catalog endpoint is now confirmed as `GET /api/v1/catalog/servers`.
- Public `/api/v1/catalog/servers` remains safe for normal clients:
  - returns `ok: true`;
  - returns the proven builtin `intelligent_smew`;
  - reports `clientVisibleManagedEntries: 0`;
  - does not automatically publish managed/admin endpoints.
- Admin-only health flow is confirmed:
  - `GET /api/v1/admin/server-catalog`;
  - `GET /api/v1/admin/server-health`;
  - `POST /api/v1/admin/server-health/probe-current`.
- `probe-current` checks the current server-local WireGuard endpoint and stores safe observations only:
  - `wg0`/WireGuard readiness signals;
  - config/profile readiness;
  - peer/handshake signs where available;
  - UDP endpoint reachability signs;
  - score `0-100`;
  - no private keys, tokens, passwords or private configs.
- Separate `admin_support_app` uses Russian health UI labels:
  - `Наблюдения здоровья`;
  - `Оценка здоровья`;
  - `Проверить текущий endpoint`;
  - `Задержка`, `потери`, `статус`, `score`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - live `/healthz` reports `version: 0.9.11`;
  - live `/api/v1/catalog/servers` reports `ok: true`;
  - live admin `probe-current` returns `status: healthy`, `score: 90`;
  - live admin `server-health` returns observations without exposing admin token.
- No new public Windows installer was rebuilt for this entry because only backend/admin-support internals changed. Current public installer aliases remain:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`.
- Progress marker after this step:
  - overall master plan: ~39%;
  - Windows MVP: ~85%;
  - monitoring/resilience layer: ~52%.

## 2026-05-05 Monitoring Details Hardening Candidate

- Backend source and live server remain `0.9.11`.
- Before issuing this candidate, local installed Green VPN artifacts were fully cleaned with `scripts\windows\greenvpn_clean_previous_install.ps1`:
  - `GreenVPNService`;
  - `WireGuardTunnel$BlueVPNDev1`;
  - `GreenVPNConnect`, `GreenVPNDisconnect`, `GreenVPNGuard`;
  - installed app folder;
  - `C:\ProgramData\BlueVPN`.
- Hardened admin/internal monitoring storage so arbitrary `details` JSON is sanitized on write and on read for:
  - `server_health_observations`;
  - `service_availability_observations`.
- The sanitizer redacts sensitive-looking keys and raw text patterns for private keys, preshared keys, admin/session/device tokens, passwords, provider secrets and raw WireGuard configs.
- Safe operational fields such as score, latency, packet loss, status, host, port, protocol, probe id and check-step metadata remain available for admin/support diagnostics.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`.
- Deployed on `37.220.85.211` with `scripts\windows\deploy_backend_wsl.ps1`.
- Live checks passed:
  - forced-resolve `https://api.greenvpn.pro/healthz` returns `version: 0.9.11`;
  - forced-resolve `https://api.greenvpn.pro/api/v1/catalog/servers` returns `ok: true`, builtin `intelligent_smew`, and `clientVisibleManagedEntries: 0`;
  - server-local Python smoke confirms monitoring details sanitizer redacts dummy private-key/raw-config fields while preserving safe score/latency fields.
- Fresh public Windows installer was rebuilt and release-gated because the test workflow requires every issued candidate to install from a clean state:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_MonitoringDetailsHardening_20260505.exe`;
  - SHA256 `BBB5E0E8CAFDD1465DEBED2537580B799FAFC5AABFA24F8F94DAA22D9233A387`.
- Admin/support app local URL for this iteration: `http://127.0.0.1:8090/`.
- Not frozen as a public rollback anchor because no user-facing installer changed.

## 2026-05-05 Support Report Send-First Fallback Candidate

- Normal user support screen remains send-first: primary action is `Отправить отчёт`.
- Added fallback button `Скопировать код отчёта` only when backend submission fails, so offline/broken-network users can still pass a coded `GVPN1.` report to support.
- Successful report submission hides the fallback code and keeps the normal user UI clean.
- Backend support flow already stores reports through `POST /api/v1/support/reports`; separate `admin_support_app` can list, open and decode reports.
- Before issuing this candidate, local Green VPN remained clean after the previous full cleanup: no installed app folder, no `C:\ProgramData\BlueVPN`, no Green VPN service/tasks/tunnel.
- Checks passed:
  - `dart format lib\main.dart`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `build_installer.ps1`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate -ReleaseZip C:\BlueVPN_Builds\_installer_work\GreenVPN_current_release_payload.zip`.
- Fresh installer:
  - `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`;
  - `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`;
  - SHA256 `5F88E078B4E8EE4519D29F6A92FF58A738CA1DD5F1E26ED108864390BAE39D01`.
- Admin/support app local URL: `http://127.0.0.1:8090/`.
- Not frozen as rollback until user installs this clean candidate and confirms install/login/VPN/support-report behavior.

## 2026-05-05 Auth Challenge / Phone-First Login Source Candidate

- Backend source version bumped to `0.9.12`.
- Backend `0.9.12` deployed on `37.220.85.211`.
- Added neutral challenge endpoints for the client:
  - `POST /api/v1/auth/challenge/start`;
  - `POST /api/v1/auth/challenge/verify`.
- These route to existing phone SMS login or email-code login and add method/channel metadata without returning auth codes.
- Normal user auth screen now shows:
  - `Телефон` first;
  - `Email-код` second;
  - `Пароль` as legacy fallback.
- Password login/register remains available but is no longer the primary flow.
- Code verification sends safe device metadata and then runs the existing VPN config warmup before opening the app.
- Invalid/expired code errors are normalized to a human Russian message.
- Release gate now also checks both auth challenge endpoints.
- Checks passed:
  - `dart format lib\main.dart`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `flutter build windows --release -t .\lib\main.dart`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL live `/healthz` returns `version: 0.9.12`;
  - WSL live `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - OpenAPI lists `/api/v1/auth/challenge/start` and `/api/v1/auth/challenge/verify`;
  - invalid-email route smoke returns HTTP `400` for challenge start and verify without creating a test user.
- `node --check admin_support_app\app.js` could not run in this Codex desktop session because bundled `node.exe` returns `Access is denied`; no admin/support app JS changed in this entry.
- No new public Windows installer was rebuilt for this entry per the latest user instruction. The next installer should be built only at final handoff or explicit stop/test request, after safe Green VPN-only cleanup.

## 2026-05-05 Admin Auth Event Filters Candidate

- Backend source version bumped to `0.9.14`.
- Backend `0.9.14` deployed on `37.220.85.211`.
- `GET /api/v1/admin/auth/events` now supports filters:
  - `eventType`;
  - `status`;
  - `contact`.
- Contact filter matches email, phone, or exact user id.
- Auth event details are redacted before response using the shared safe details sanitizer.
- Separate `admin_support_app` `Входы` section now has filters for contact/user id, auth event type, and status. This helps support inspect phone/email-code login problems without exposing secrets.
- Admin analytics no longer treats normal code-start status `created` as failed auth.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.14`;
  - WSL forced-resolve `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - server-local filtered `list_auth_events` smoke passed without printing contact data.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Controlled Monitoring Probe Readiness Candidate

- Backend source version bumped to `0.9.15`.
- Backend `0.9.15` deployed on `37.220.85.211`.
- Added admin-only service-probe readiness endpoint:
  - `GET /api/v1/admin/monitoring/readiness`.
- Monitoring summaries now include `probeReadiness` with:
  - fresh/stale probe-agent state;
  - required target coverage;
  - required target freshness;
  - required target green/yellow/red status;
  - owner action for installing a separate monitoring VPS without storing the admin token in repo.
- Product readiness now has a separate `monitoring_probes` check, distinct from backend/WireGuard health.
- Separate `admin_support_app` `Мониторинг` section now shows probe readiness and required-target coverage in the probe-agent cards.
- Release gate now checks admin server-catalog, server-health, monitoring target/observation/probe, and monitoring readiness endpoints.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - WSL `bash -n` for `scripts/monitoring/install_probe_systemd.sh`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.15`;
  - WSL forced-resolve `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - OpenAPI lists `/api/v1/admin/monitoring/readiness`;
  - server-local readiness smoke returned `productionReady: false`, `requiredTargetCount: 5`, with no secrets printed.
- No new public Windows installer was rebuilt for this entry. The next installer should be built only at final handoff or explicit stop/test request, after safe Green VPN-only cleanup.

## 2026-05-05 Support Action Safety Guard Candidate

- Backend source version bumped to `0.9.16`.
- Backend `0.9.16` deployed on `37.220.85.211`.
- Dangerous support actions now require a reason on the backend:
  - `reset_user_sessions`;
  - `disable_device`.
- Support action workflow now includes `requiresReason` and `confirmationText`.
- Separate `admin_support_app` now:
  - requires a reason before reason-required actions;
  - shows browser confirmation before dangerous actions;
  - shows latest support actions in `Техподдержка` with filters by action/status/user id;
  - keeps actions audited and still avoids secrets/private WireGuard data.
- Release gate now checks:
  - `GET /api/v1/admin/support/actions/workflow`;
  - `POST /api/v1/admin/users/{user_id}/support-actions`.
- `scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck` now covers the newer protected admin endpoints without printing the admin token:
  - product readiness;
  - monitoring readiness;
  - server-catalog publication readiness;
  - support action workflow;
  - auth-event filters.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - local admin app HTTP `200` at `http://127.0.0.1:8090/`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.16`;
  - WSL forced-resolve `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - OpenAPI lists support action workflow/action endpoints;
  - server-local support-action smoke confirmed dangerous action without reason returns HTTP `400` and does not execute.
  - `check_external_services_readiness.ps1 -SkipServerSelfCheck -ServerAdminSelfCheck -Json` returned protected admin self-check green.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Monitoring Default Targets Refresh Candidate

- Backend source version bumped to `0.9.17`.
- Backend `0.9.17` deployed on `37.220.85.211`.
- Added admin-only endpoint:
  - `POST /api/v1/admin/monitoring/targets/seed-defaults`.
- The endpoint refreshes built-in controlled monitoring targets without deleting custom targets.
- Built-in targets currently cover:
  - YouTube web;
  - Discord gateway;
  - Telegram API;
  - Green VPN API healthz;
  - production API domain healthz;
  - Windows update manifest;
  - payment return page.
- Separate `admin_support_app` `Мониторинг` now has `Обновить базовые цели`.
- Release gate now checks the seed-defaults endpoint.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - WSL forced-resolve `/healthz` returns `version: 0.9.17`;
  - WSL forced-resolve `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - OpenAPI lists `/api/v1/admin/monitoring/targets/seed-defaults`;
  - server-local smoke refreshed 7 built-in targets without printing secrets.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Update Release Readiness Guard Candidate

- Backend source version bumped to `0.9.18`.
- Backend `0.9.18` deployed on `37.220.85.211`.
- Added admin-only endpoint:
  - `GET /api/v1/admin/updates/readiness`.
- Update manifest safety was hardened:
  - manifests now include `fileReady`, `publicHttpsReady`, `configuredRequired`, `releaseBlocked`, and `blockingReason`;
  - effective client `required` is suppressed when a required update is configured without a ready artifact;
  - `updateAvailable` is false when the download artifact is missing even if a newer version string exists;
  - published stable releases require public HTTPS download URL plus valid SHA256.
- Separate `admin_support_app` `Обновления` now shows release readiness above the manifest preview.
- Separate `admin_support_app` `Серверы` now filters endpoint health observations by endpoint id and health status.
- Release gate now checks update readiness and release list endpoints.
- External readiness script now includes update readiness in protected server-side admin self-check and treats local Windows/WSL HTTPS failures as yellow when server-side checks are green.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.18`;
  - OpenAPI lists `/api/v1/admin/updates/readiness`, `/api/v1/admin/updates/releases`, and `/api/v1/updates/windows`;
  - server-side protected smoke returns update readiness with `productionReady: false`, `fileReady: false`, `publicHttpsReady: false`, no secrets printed;
  - server-side protected smoke confirms filtered `GET /api/v1/admin/server-health` observations work for endpoint and status filters;
  - `check_external_services_readiness.ps1 -SkipServerSelfCheck -ServerAdminSelfCheck -Json` returns protected admin self-check green and keeps only DMARC as a real red owner-action in this mode.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Support Trial Action Candidate

- Backend source version bumped to `0.9.19`.
- Backend `0.9.19` deployed on `37.220.85.211`.
- Added support action:
  - `grant_support_trial_3d`.
- Safety behavior:
  - reason is required;
  - creates or extends `support_trial` by 3 days;
  - preserves active paid subscriptions and records `noop`;
  - writes support-action history and admin audit;
  - does not expose secrets, tokens, payment credentials or WireGuard private keys.
- Separate `admin_support_app` fallback workflow includes the action and confirms any action with `confirmationText`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.19`;
  - protected support workflow returns `actions: 7`, `hasSupportTrial3d: true`, `reasonRequired: 4`;
  - temp-DB smoke confirms support trial grant works and paid subscription preservation returns `noop`;
  - external readiness protected admin self-check remains green.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Release Gate Safety Invariants Candidate

- No backend source version bump and no backend deploy were needed; backend remains `0.9.19`.
- `scripts\windows\bluevpn_release_gate.ps1` now fails if these backend safety invariants disappear:
  - `apply_update_artifact_guard`;
  - `required_update_without_artifact`;
  - published stable release public HTTPS/SHA256 guard;
  - `grant_support_trial_3d`;
  - paid-subscription preservation for support trial;
  - `SUPPORT_ACTIONS_REQUIRING_REASON`.
- Checks passed:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - server-local `/healthz` returns `version: 0.9.19`.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Admin Support Assigned Filter Candidate

- No backend source version bump and no backend deploy were needed; backend remains `0.9.19`.
- Separate `admin_support_app` support reports now include an `исполнитель` filter.
- The filter reuses the existing protected backend query parameter `assignedTo` on `GET /api/v1/admin/support/reports`.
- Checks passed:
  - local admin app index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - local `app.js` returns HTTP 200 from the same server;
  - static source check confirms the HTML control, `assignedTo` request param and debounced reload listener are wired;
  - static source check confirms backend route already forwards `assignedTo` into `list_support_reports`.
- Full JS parser check was not rerun in this heartbeat shell because local `python` is not on PATH and the available WindowsApps `node.exe` returns access denied.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Monitoring Service Observation Filters Candidate

- No backend source version bump and no backend deploy were needed; backend remains `0.9.19`.
- Separate `admin_support_app` monitoring service observations now include filters for `target id` and observation status.
- The filters reuse the existing protected backend query params `targetId`, `status`, and `limit` on `GET /api/v1/admin/monitoring/service-observations`.
- Checks passed:
  - local admin app index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - local `app.js` returns HTTP 200 from the same server;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Server Catalog Publication Filter Candidate

- No backend source version bump and no backend deploy were needed; backend remains `0.9.19`.
- Separate `admin_support_app` managed server catalog now includes a publication-state filter for public candidates vs internal endpoints.
- The filter reuses the existing protected backend query param `public` on `GET /api/v1/admin/server-catalog`.
- Checks passed:
  - local admin app index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Update Readiness Channel Filter Candidate

- No backend source version bump and no backend deploy were needed; backend remains `0.9.19`.
- Separate `admin_support_app` update readiness now requests the selected release channel explicitly instead of relying on the later releases response to overwrite stable readiness.
- The readiness cards reuse the existing protected backend query params `platform=windows` and `channel` on `GET /api/v1/admin/updates/readiness`.
- Checks passed:
  - local admin app index returns HTTP 200 on `http://127.0.0.1:8090/`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`.
- No new public Windows installer was rebuilt for this entry.

## 2026-05-05 Support Report Redaction Hardening Candidate

- Backend source version bumped to `0.9.20`.
- Backend `0.9.20` deployed on `37.220.85.211`.
- Hardened decoded support reports:
  - sensitive-looking key names are redacted using the shared telemetry key detector, not only exact key matches;
  - sensitive-looking string values are redacted using the shared telemetry value patterns;
  - nested payloads are depth/size bounded before display in the separate admin/support app.
- Release gate now fails if the support-report submission/decode endpoints or user-app send-first/fallback-copy flow disappear.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - local stubbed backend import smoke for support-report redaction;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.20`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - server-local support-report redaction smoke passed without printing secrets;
  - external readiness protected admin self-check remains green, with DMARC still the remaining owner-action blocker.
- `dart analyze lib\main.dart` still exits with existing warning/info debt; no new analyzer error was introduced by this backend/admin safety step.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Server Catalog Auto-Pause Safety Gate Candidate

- Backend source version bumped to `0.9.21`.
- Backend `0.9.21` deployed on `37.220.85.211`.
- Managed endpoint publication safety was hardened:
  - bad server-health observations (`down`/`degraded`) automatically clear `is_public` for managed public candidates;
  - low health score below the publication threshold also clears `is_public`;
  - backend records `publication_paused_at`, `publication_paused_reason`, `publication_paused_by=health_gate`;
  - an admin audit event records the automatic pause.
- Separate `admin_support_app` shows the `auto-paused` marker and reason in the managed server table.
- Release gate now checks the auto-pause backend safety fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.21`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - server-local temp-DB smoke confirmed auto-pause and public-catalog safety;
  - external readiness protected admin self-check remains green, with DMARC still the remaining owner-action blocker.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Support Config Refresh Apply Candidate

- Backend source version bumped to `0.9.22`.
- Backend `0.9.22` deployed on `37.220.85.211`.
- Support `request_config_refresh` now becomes a real next-config-fetch reissue:
  - rotates client WireGuard keypair and preshared key;
  - preserves assigned IP when possible;
  - replaces the managed peer block;
  - applies the new live peer;
  - best-effort removes the old live peer;
  - clears refresh request markers only after successful config issue;
  - stores last applied refresh time/reason and writes audit.
- Public responses expose only `supportConfigRefreshApplied: true/false`; keys are never logged, returned to admin, or written to docs.
- Separate `admin_support_app` now shows the last applied refresh marker in the device card.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.22`;
  - server-local temp-DB smoke confirmed support refresh application without touching real WireGuard peers;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`;
  - external readiness protected admin self-check remains green, with DMARC still the remaining owner-action blocker.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Admin Staff Session Management Candidate

- Backend source version bumped to `0.9.23`.
- Backend `0.9.23` deployed on `37.220.85.211`.
- Added staff-session inventory and revocation for owner/admin:
  - list sessions for a staff member;
  - revoke one active staff session by short public session id;
  - revoke all active staff sessions for a staff member;
  - preserve the current operator session when revoking the operator's own sessions.
- Staff list now includes session counters and last session activity.
- Separate `admin_support_app` `Команда` now exposes session counts, session list, single revoke and revoke-all.
- Audit records staff session revocations without exposing raw session tokens.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.23`;
  - server-local temp-DB smoke confirmed inventory/revoke/revoke-all/current-preserve/audit;
- live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Support SLA Backfill Candidate

- Backend source version bumped to `0.9.37`.
- Backend `0.9.37` deployed on `37.220.85.211`.
- Added startup backfill for legacy support reports with empty workflow fields.
- Backfill fills only empty `priority`, `category`, `triage_reason`, and `sla_due_at`; it does not overwrite operator-set values.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed legacy report workflow/SLA backfill;
  - live `/healthz` returns `version: 0.9.37`;
  - live protected support SLA endpoint now reports `missingSla=0`; current two open reports are visible as overdue/review-pending work items;
  - protected server-side readiness self-check remains green for admin endpoints except expected external owner blockers.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Support SLA Queue Candidate

- Backend source version bumped to `0.9.36`.
- Backend `0.9.36` deployed on `37.220.85.211`.
- Added protected `GET /api/v1/admin/support/sla`.
- Support report payloads now expose derived `slaStatus` and `firstResponseMissing`.
- SLA dashboard exposes open/overdue/due-soon/missing-SLA/first-response/review-pending counts and `attentionQueue`.
- Separate `admin_support_app` renders compact SLA queue cards above the support report table.
- External readiness server-side self-check now covers the SLA endpoint.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed SLA status derivation and attention queue;
  - live `/healthz` returns `version: 0.9.36`;
  - live protected support SLA endpoint responds; current live backlog has 2 open reports requiring attention due missing SLA/first-response metadata;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Owner Action Audit Guard Candidate

- Backend source version bumped to `0.9.35`.
- Backend `0.9.35` deployed on `37.220.85.211`.
- External owner-action status updates now require a safe note for:
  - `waiting_owner`;
  - `waiting_provider`;
  - `ready_to_apply`;
  - `blocked`;
  - `not_needed`;
  - manual `done` when the backend readiness check for that action is still not green.
- `GET /api/v1/admin/external-actions` now includes owner-action policy and blocking summary metadata:
  - `ownerActionPolicy`;
  - `blockingSummary`;
  - `doneButBackendNotReadyCodes`;
  - `missingOwnerNoteCodes`;
  - `safeToProceed`.
- Separate `admin_support_app` renders owner-action audit status and policy near the external setup bundle.
- External readiness server-side self-check now verifies owner-action policy and blocking summary.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed note-required guard and `done`-before-backend-ready mismatch detection;
  - live `/healthz` returns `version: 0.9.35`;
  - live protected external-actions payload reports policy/blocking summary without exposing secrets;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Readiness Self-Check Staff Sessions Coverage Candidate

- No backend source version bump and no deploy were needed; backend remains `0.9.23`.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now covers the staff/session admin surface:
  - staff list plus session counters;
  - safe session inventory for the first staff record when available;
  - OpenAPI route presence for revoke/revoke-all endpoints without calling mutating endpoints on live data.
- Checks passed:
  - external readiness protected admin self-check is green and reports staff/session route coverage;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Incident Runbook Suggestions Candidate

- Backend source version bumped to `0.9.24`.
- Backend `0.9.24` deployed on `37.220.85.211`.
- Internal incident payloads now include `suggestedRunbooks`, selected from active admin runbooks by incident title/source/service/endpoint/summary.
- Suggested categories cover payments, auth, VPN/WireGuard, servers/API/catalog, monitoring/service probes, updates, and fallback incident/general.
- Separate `admin_support_app` shows suggested runbook pills under incident title/summary in `Инциденты`.
- Release gate now checks the incident runbook suggestion fragments.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.24`;
  - server-local temp-DB smoke confirmed relevant suggestions for payment, monitoring, and API/server incidents;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Incident Staff Assignment Candidate

- Backend source version bumped to `0.9.25`.
- Backend `0.9.25` deployed on `37.220.85.211`.
- Incidents now support structured staff assignment with `assigneeStaffId`, `assignedAt`, `assignedBy`, and assignment history in sanitized incident details.
- Added protected endpoint `GET /api/v1/admin/incidents/assignees`, requiring `incidents.read`, so support roles can receive safe active assignee options without full staff-management rights.
- `GET /api/v1/admin/incidents` now supports `assignee` filter and returns safe assignee options for the separate admin app.
- Separate `admin_support_app` incident table now has assignee filter, per-incident assignment dropdown, and current-staff assignment for incident workflow buttons.
- Release/readiness gates now cover the incident assignee surface.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.25`;
  - server-local temp-DB smoke confirmed active assignee listing, assignment, clear, assignment history, and filters;
  - protected readiness self-check confirmed assignee endpoint and no raw token exposure;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Incident Alert Outbox/History Candidate

- Backend source version bumped to `0.9.26`.
- Backend `0.9.26` deployed on `37.220.85.211`.
- Added internal `admin_alert_events` storage for sanitized incident alert attempts.
- High/critical incidents now record alert history even before Telegram secrets exist:
  - no-secret mode records `skipped/manual_mvp`;
  - future configured Telegram mode records `sent` or `failed`;
  - low-severity events below alert threshold do not create alert noise.
- Added protected endpoint `GET /api/v1/admin/alerts/events`, requiring `incidents.read`.
- Separate `admin_support_app` readiness section now shows recent incident alert history.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.26`;
  - server-local temp-DB smoke confirmed skipped/manual MVP event creation and low-severity suppression;
  - protected readiness self-check confirmed alert-events endpoint and no raw token exposure;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Updater Release Publication Gate Candidate

- Backend source version bumped to `0.9.27`.
- Backend `0.9.27` deployed on `37.220.85.211`.
- Added per-release `releaseReadiness` with `canPublish`, artifact readiness, public HTTPS readiness, blockers, and warnings.
- Published releases are blocked through one explicit publication gate:
  - `artifact_missing`;
  - `stable_requires_public_https`;
  - `required_update_without_artifact`.
- `GET /api/v1/admin/updates/readiness` now includes `latestReleaseReadiness` and `release_publication_gate`.
- Separate `admin_support_app` release table shows gate state and first blockers/warnings; blocked publish buttons are disabled client-side while backend remains authoritative.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.27`;
  - server-local temp-DB smoke confirmed draft/publish blocking and valid HTTPS+SHA publish path;
  - protected readiness self-check remains green for admin endpoints; update readiness still waits for final artifact URL/SHA256;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-05 Server Catalog Provisioning Readiness Candidate

- Backend source version bumped to `0.9.28`.
- Backend `0.9.28` deployed on `37.220.85.211`.
- Added protected `GET /api/v1/admin/server-catalog/provisioning-readiness`.
- The admin provisioning gate now verifies the current client config contract:
  - `/api/v1/client/config` is public-catalog-only;
  - accepted client `serverId` values are `auto` and `intelligent_smew`;
  - internal `current_wg0` can be config-ready but is not accepted as a direct client `serverId`;
  - managed endpoints remain invisible to public `/api/v1/catalog/servers`.
- Separate `admin_support_app` Server Catalog summary now shows `Provisioning gate` and blocked selection cases.
- Release/readiness gates cover the new endpoint and invariants.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.28`;
  - server-local temp-DB smoke confirmed `current_wg0` config readiness without public client visibility;
  - protected readiness self-check confirmed `safeForCurrentClient=true`, `currentEndpointConfigReady=true`, `multiEndpointProvisioningReady=false`;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- External readiness still has owner-action blockers: DMARC TXT, final update artifact/SHA256, external monitoring probe, Telegram alert secrets, SMTP/SMS/YooKassa production data.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Auth Code Verify Lockout Candidate

- Backend source version bumped to `0.9.30`.
- Backend `0.9.30` deployed on `37.220.85.211`.
- Added bounded verify attempts for email-code and phone/SMS-code login:
  - `GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS`, default `5`;
  - `GREENVPN_AUTH_CODE_LOCKOUT_MINUTES`, default `15`;
  - DB fields `attempts_count`, `last_attempt_at`, `locked_until` on auth-code tables.
- After repeated wrong codes, verification returns HTTP `429` with `too_many_attempts`; the correct code is not accepted until lockout expires.
- `auth_code_readiness()` now exposes max attempts and lockout duration for readiness/admin visibility.
- Separate `admin_support_app` `Входы` filter now includes `too_many_attempts`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.30`;
  - server-local temp-DB smoke confirmed lockout for both email and phone auth codes;
  - protected readiness self-check remains green for admin endpoints;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- External readiness still has owner-action blockers: DMARC TXT, final update artifact/SHA256, external monitoring probe, Telegram alert secrets, SMTP/SMS/YooKassa production data.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Support Report Review Workflow Candidate

- Backend source version bumped to `0.9.29`.
- Backend `0.9.29` deployed on `37.220.85.211`.
- Support reports now expose `reviewedAt`, `reviewedBy`, and `reviewPending`.
- Added protected `POST /api/v1/admin/support/reports/{report_id}/review`.
- Review action moves fresh reports into work, records first-response/review metadata, assigns the operator when needed, and writes `support_report_reviewed` audit.
- Existing status quick-actions now preserve `assignedTo` if the request does not explicitly change it.
- Separate `admin_support_app` now shows review state and has a quick `В работу` action in the support report table and detail dialog.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.29`;
  - server-local temp-DB smoke confirmed review metadata, first response, assignee preservation after resolve, and decoded-report redaction;
  - protected readiness self-check confirmed the review route is present in OpenAPI;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- External readiness still has owner-action blockers: DMARC TXT, final update artifact/SHA256, external monitoring probe, Telegram alert secrets, SMTP/SMS/YooKassa production data.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 External Owner Setup Bundle Candidate

- Backend source version bumped to `0.9.31`.
- Backend `0.9.31` deployed on `37.220.85.211`.
- Admin external-actions payload now includes a safe owner setup bundle:
  - apply command for the server-only env helper;
  - readiness command for the server-side protected checker;
  - expected public DNS records, including the DMARC TXT value;
  - safe defaults for public API/YooKassa URLs and auth-code lockout env.
- Every external owner action now exposes `ownerInputs`, `applySteps`, and `verifySteps`; secret inputs are marked as secret but never include secret values.
- `configure_backend_env_wsl.sh` now writes `GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS=5` and `GREENVPN_AUTH_CODE_LOCKOUT_MINUTES=15` when rotating auth-code pepper.
- `check_external_services_readiness.ps1` now reports expected DNS values for missing/mismatched records and checks the external-actions setup metadata in protected server-side self-check.
- Separate `admin_support_app` now renders the setup bundle and per-action owner input/apply/verify metadata.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.31`;
  - protected server-side smoke confirmed setup bundle, ownerInputs/applySteps/verifySteps coverage, 5 DNS records and no admin token exposure;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- External readiness still has owner-action blockers: DMARC TXT, final update artifact/SHA256, external monitoring probe, Telegram alert secrets, SMTP/SMS/YooKassa production data.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Monitoring Probe Install Bundle Candidate

- Backend source version bumped to `0.9.32`.
- Backend `0.9.32` deployed on `37.220.85.211`.
- `GET /api/v1/admin/monitoring/readiness` now includes a safe `installBundle` for the external monitoring VPS:
  - install command for `install_probe_systemd.sh`;
  - `--token-stdin` token handoff;
  - token path `/etc/greenvpn-monitoring/admin_token`;
  - required target ids and verification commands;
  - owner inputs/apply steps without secret values.
- Separate `admin_support_app` renders the probe install bundle in the monitoring agents panel.
- External readiness server-side self-check now verifies that monitoring readiness has the install bundle and `--token-stdin` command.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.32`;
  - protected server-side smoke confirmed install bundle, 5 required targets and `productionReady=false` until a real external VPS sends fresh green observations;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No monitoring VPS was installed; this still needs owner-provided VPS/SSH access and token handoff.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Billing Reconciliation Guard Candidate

- Backend source version bumped to `0.9.33`.
- Backend `0.9.33` deployed on `37.220.85.211`.
- Added protected `GET /api/v1/admin/billing/reconciliation`.
- Admin billing orders payload now includes a reconciliation summary.
- Reconciliation detects paid-not-activated, paid-at-without-activation, stale pending orders, YooKassa payment creation gaps and terminal-order payment marker mismatches.
- Manual `mark-paid` activation now refuses `failed` / `canceled` / `cancelled` orders with HTTP `409`, while pending manual activation remains available for MVP/manual payment flow.
- Separate `admin_support_app` payments section now shows billing reconciliation issue counts, attention order preview and manual activation policy.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed issue detection, canceled-order activation guard and pending activation;
  - live `/healthz` returns `version: 0.9.33`;
  - live protected reconciliation endpoint responds and external readiness self-check includes it;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- Live DB currently reports 8 orders and 4 medium reconciliation attention items, mostly old pending orders to review before production payments.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Update Rollback Publication Guard Candidate

- Backend source version bumped to `0.9.34`.
- Backend `0.9.34` deployed on `37.220.85.211`.
- Added `releaseReadiness.rollbackReadiness` to admin-managed releases and top-level `rollbackReadiness` to `GET /api/v1/admin/updates/readiness`.
- Stable `rolloutPercent >= 100` or `isRequired=true` publication is now blocked by `rollback_artifact_missing` until a previous published stable release or configured `GREENVPN_ROLLBACK_*` public HTTPS artifact is ready.
- Staged stable rollout below 100% can still publish, but receives `rollback_missing_for_staged_rollout` and keeps update readiness non-production.
- `configure_backend_env_wsl.sh` now has an optional final update/rollback artifact block for `GREENVPN_UPDATE_*`, `GREENVPN_LATEST_VERSION`, and `GREENVPN_ROLLBACK_*`.
- Separate `admin_support_app` renders rollback state in update readiness, update manifest and release table.
- External readiness server-side self-check now verifies updater rollback readiness metadata.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed blocked full/required release without rollback, allowed staged rollout with warning, and full rollout after previous published rollback candidate;
  - live `/healthz` returns `version: 0.9.34`;
  - live protected update readiness reports no rollback source until final release/rollback artifact exists;
  - live public `/api/v1/catalog/servers` still exposes only builtin `intelligent_smew` with `clientVisibleManagedEntries: 0`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Billing Renewal Readiness Guard Candidate

- Backend source version bumped to `0.9.38`.
- Backend `0.9.38` deployed on `37.220.85.211`.
- Added protected `GET /api/v1/admin/billing/renewals/readiness`.
- Auto-renewal readiness is dry-run only in this backend version:
  - detects upcoming auto-renew subscriptions;
  - flags missing saved provider payment methods;
  - flags existing pending auto-renew orders;
  - blocks charges while production YooKassa readiness is false;
  - does not expose provider payment method ids.
- Separate `admin_support_app` payments section renders the renewal readiness summary and candidate preview.
- External readiness server-side self-check now verifies the endpoint and checks that raw payment method ids are not exposed.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed missing-method/pending-order blockers and no method id exposure;
  - live `/healthz` returns `version: 0.9.38`;
  - live protected renewal readiness reports `productionPaymentReady=false`, `safeToEnableAutoRenewalCharges=false`, 3 auto-renew subscriptions, 0 due within the window, and 1 pending-order conflict;
  - protected external readiness self-check is green for admin endpoints; external blockers remain DMARC, local DNS/API health, monitoring VPS, Telegram, SMTP/SMS/YooKassa and final update/rollback artifacts.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Subscription Expiry Readiness Guard Candidate

- Backend source version bumped to `0.9.39`.
- Backend `0.9.39` deployed on `37.220.85.211`.
- Added `BLUEVPN_DATA_DIR` / `BLUEVPN_BASE_DIR` support for isolated backend smoke tests while keeping the production default unchanged.
- Added protected `GET /api/v1/admin/subscriptions/expiry-readiness`.
- Subscription expiry readiness is dry-run only:
  - detects active subscriptions already past `expires_at`;
  - detects paid subscriptions expiring soon without auto-renew;
  - detects missing verified email/phone contact for expiring users;
  - detects expiring auto-renew subscriptions blocked by YooKassa readiness, pending renewal conflicts, or missing saved payment method;
  - does not expose provider payment method ids.
- Separate `admin_support_app` users/subscriptions section renders expiry readiness summary and candidates.
- External readiness server-side self-check now verifies the endpoint and method-id non-exposure.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed isolated `BLUEVPN_DATA_DIR`, expired-active/manual-expiring/auto-renew-payment blockers and no method id exposure;
  - live `/healthz` returns `version: 0.9.39`;
  - live protected expiry readiness reports `safeToEnableExpiryEnforcement=false`, 29 latest subscriptions, 19 expired active rows and 3 expiring rows needing retention/review;
  - protected external readiness self-check is green for admin endpoints.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Expired Trial Subscription Backfill Candidate

- Backend source version bumped to `0.9.41`.
- Backend `0.9.41` deployed on `37.220.85.211`.
- Added startup `backfill_expired_non_paid_subscriptions()`.
- The backfill is intentionally narrow:
  - deactivates expired `trial` / `support_trial` / default non-paid rows;
  - does not deactivate paid plans;
  - keeps paid expired rows visible for manual review instead of silently changing them.
- Subscription expiry readiness now separates:
  - `expired`: expired rows that still have `is_active=1`;
  - `expiredTotal`: all expired latest rows, including inactive historical trials.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed trial-only deactivation and paid-row preservation;
  - live `/healthz` returns `version: 0.9.41`;
  - live protected expiry readiness reports `expired=0`, `expiredTotal=19`, `expiringWithinWindow=3`, `blockedExpiring=3`;
  - protected external readiness self-check is green for admin endpoints.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 External Endpoint Probe Readiness Candidate

- Backend source version bumped to `0.9.42`.
- Backend `0.9.42` deployed on `37.220.85.211`.
- Added external endpoint-probe readiness to `GET /api/v1/admin/server-health`:
  - reports required config-ready endpoint ids, currently `current_wg0`;
  - separates server-local `backend-local` health observations from external monitoring VPS observations;
  - keeps production endpoint readiness blocked until an external probe sends fresh healthy observations.
- Updated `scripts\monitoring\service_probe.py`:
  - new `--server-health` mode fetches managed server catalog entries and posts safe endpoint observations to `POST /api/v1/admin/server-health/observations`;
  - dry-run mode verifies checks without writing live observations;
  - payload contains only safe DNS/API/UDP-route/config-readiness signals, no secrets or WireGuard private configs.
- Updated `scripts\monitoring\install_probe_systemd.sh` and admin readiness install bundle:
  - server-health probing is enabled by default;
  - install command keeps `--token-stdin` and now includes `--server-health`;
  - `--no-server-health` remains available for service-only probe runs.
- Separate `admin_support_app` server-health cards now show external endpoint probe agent count and required endpoint coverage.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - `wsl bash -lc "bash -n scripts/monitoring/install_probe_systemd.sh"`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - live `/healthz` returns `version: 0.9.42`;
  - live protected `/api/v1/admin/server-health` reports `requiredEndpointIds=["current_wg0"]`, `missingEndpointIds=["current_wg0"]`, and `externalProductionReady=false`, which is expected until the owner provides a separate monitoring VPS;
  - `service_probe.py --server-health --dry-run` checked `production_api_healthz` and `current_wg0` without posting live observations;
  - protected external readiness self-check is green for admin endpoints and verifies `--server-health` in the probe install bundle.
- Public `/api/v1/catalog/servers` remains unchanged and managed endpoints are still not published to the user client.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Server Health Incident Sync Candidate

- Backend source version bumped to `0.9.43`.
- Backend `0.9.43` deployed on `37.220.85.211`.
- Added `sync_server_health_observation_incident()`:
  - degraded/down or `ok=false` server-health observations open/reopen incidents keyed as `server-health:<endpointId>`;
  - `down` creates high severity, `degraded` creates medium severity;
  - healthy observations resolve the matching server-health incident.
- This ties endpoint health scoring into the existing internal incident dashboard, runbook suggestions and alert outbox. It remains admin/support-only and does not affect the normal Green VPN client routing.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py scripts\monitoring\service_probe.py`;
  - QuickJS syntax parse for `admin_support_app\app.js`;
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - backend deploy to `37.220.85.211`;
  - server-local temp-DB smoke confirmed degraded endpoint observation opens a `server_health_observation` incident and later healthy observation resolves it;
  - live `/healthz` returns `version: 0.9.43`;
  - live protected server-health check reports no open server-health incidents and keeps external endpoint readiness blocked until a real monitoring VPS covers `current_wg0`.
- Public `/api/v1/catalog/servers` remains unchanged and managed endpoints are still not published to the user client.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Admin Staff Password/Session Guard

- No new backend version was required; live backend remains `0.9.43`.
- Confirmed existing staff self-service endpoints and UI:
  - `GET /api/v1/admin/auth/sessions`;
  - `POST /api/v1/admin/auth/password/change`;
  - `POST /api/v1/admin/auth/sessions/revoke`;
  - `POST /api/v1/admin/auth/sessions/revoke-others`;
  - overview security form in the separate `admin_support_app`.
- Hardened release/readiness checks:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate` now requires the password/session endpoints and audit fragments;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now verifies the self-service session/password routes in OpenAPI route inventory.
- Checks passed:
  - `bluevpn_release_gate.ps1 -StrictPaymentGate`;
  - protected external readiness route inventory reports `routesPresent=true`.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 SMTP/Yandex 360 Owner Setup

- No new backend version was required; live backend remains `0.9.43`.
- Yandex 360 mailboxes were created externally: `no-reply@greenvpn.pro`, `support@greenvpn.pro`, and `postmaster@greenvpn.pro`.
- SMTP settings for Yandex 360 were applied to `/etc/bluevpn/backend.env` through the safe env script; the app password was not stored in the repository or docs.
- Backend restart succeeded and `/healthz` reports `emailProductionReady=true` while email confirmation enforcement remains disabled for safe rollout.
- `check_external_services_readiness.ps1 -Json -ServerAdminSelfCheck` returned `ok=true`, `green=10`, `yellow=2`, `red=0`; server-side protected checks are green.
- Real email-code delivery is still blocked by VPS/network SMTP egress: latest test outbox row failed with `[Errno 113] No route to host`, and server-side TCP checks to `smtp.yandex.ru` ports `25/465/587` fail while normal Yandex HTTPS works.
- Owner created Timeweb support ticket `11901262`; production email-code verification remains pending until the VPS/provider unblocks SMTP submission or a different approved mail relay is configured.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 SMS.ru Owner Setup

- No new backend version was required; live backend remains `0.9.43`.
- Hardened `scripts\configure_backend_env_wsl.sh` so required secret prompts, currently `SMS.ru api_id`, cannot silently accept an empty value; post-restart backend health check now retries before failing.
- SMS.ru `api_id` was applied through the safe env prompt and stored only in `/etc/bluevpn/backend.env`.
- Removed the accidental `GREENVPN_SMS_FROM=y` value from the server env; sender name remains unset until a real branded sender is approved.
- Backend restart succeeded and `/healthz` reports `smsProductionReady=true` and `authCodeProductionReady=true`.
- Protected `/api/v1/admin/sms/readiness` reports `provider=smsru`, `deliveryReady=true`, `productionReady=true`, `testMode=false`, and no required actions.
- External actions checklist marks SMS as done; real delivery/balance test is still an operational owner check because the SMS.ru dashboard showed zero balance during setup.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 YooKassa Legal Pages

- Backend source version bumped to `0.9.44`.
- Backend `0.9.44` deployed on `37.220.85.211`.
- Added public review pages on `https://api.greenvpn.pro`:
  - `/` landing/product overview;
  - `/legal/requisites`;
  - `/legal/offer`;
  - `/legal/privacy`;
  - `/legal/acceptable-use`;
  - `/legal/refunds`.
- Owner-provided public self-employed requisites were applied through the safe server env prompt and stored only in `/etc/bluevpn/backend.env`; personal data is intentionally not copied into repository docs.
- Server-side checks passed:
  - `https://api.greenvpn.pro/healthz` returns `version: 0.9.44`;
  - `https://api.greenvpn.pro/legal/requisites` contains Green VPN service description, masked self-employed INN field, and `support@greenvpn.pro`.
- Current YooKassa questionnaire should use `https://api.greenvpn.pro` as site URL and `https://api.greenvpn.pro/legal/requisites` as requisites URL until root `greenvpn.pro` DNS is moved away from REG.RU parking.
- No new public Windows installer was rebuilt for this entry. Next installer remains final-only or explicit stop/test-only.

## 2026-05-06 Billing Promotions Candidate

- Backend source version bumped to `0.9.45`.
- Backend `0.9.45` deployed on `37.220.85.211`.
- Added promo/action support for future launch campaigns:
  - promo storage and redemption accounting;
  - promo-aware subscription quote;
  - strict promo validation on billing order creation;
  - original amount, discount amount and promo code stored on billing orders;
  - admin create/edit/list/activate/deactivate endpoints.
- Separate `admin_support_app` payments section now includes an internal promo panel for percent/fixed discounts, usage limits, active dates, tariff scoping and internal notes.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - static admin app id/reference scan for promo fields;
  - backend deploy to `37.220.85.211`;
  - server-local `/healthz` returns `version: 0.9.45`;
  - protected admin promos endpoint returns safely;
  - server-local quote smoke handles unknown promo as `not_found`;
  - server-local temp-DB promo logic smoke confirms a 20% test promo discounts base quote from 149 to 119 RUB.
- `node.exe` is blocked by Windows `Access is denied` in this session; Node syntax check was not available.
- YooKassa remains paused until FNS NPD status becomes active. No public Windows installer was rebuilt for this entry.

## 2026-05-06 Promotions Strategy Note

- Added launch promo policy to `docs/BUSINESS_PRICING_STRATEGY_RU.md`.
- Baseline approach: short first-month discounts with usage/date/tariff limits, not permanent discounting.
- Suggested internal codes for launch planning: `START20`, `FRIEND`, and support-only compensation codes with notes.
- Public wording must keep the same positioning as the product/legal pages: protected and stable connection, not bypass/unblock marketing.
- YooKassa is still waiting for the external FNS/NPD status update; no installer was rebuilt.

## 2026-05-06 Public Download Pages Candidate

- Backend source version bumped to `0.9.46`.
- Backend `0.9.46` deployed on `37.220.85.211`.
- Public site at `https://api.greenvpn.pro/` now includes a download section:
  - Windows button: `/download/windows`;
  - Android placeholder: `/download/android`;
  - iOS placeholder: `/download/ios`.
- The Windows route will redirect to the final HTTPS installer after `GREENVPN_PUBLIC_WINDOWS_DOWNLOAD_URL` or `GREENVPN_UPDATE_URL` is configured. Until then it shows a controlled pending page, because no intermediate installer should be issued.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - backend deploy;
  - server-side HTTPS health and landing/download smokes.
- No public Windows installer was rebuilt.

## 2026-05-08 Owner Required Input Verification

- Live owner-action state was aligned for `email`: protected update succeeded and `/api/v1/admin/external-actions` now reports `waitingCodes=[]`.
- Confirmed current owner-action statuses:
  - done and ready: `public_api`, `email`, `sms`, `server_catalog`, `monitoring`;
  - pending: `payments`, `updates`, `admin_alerts`.
- Confirmed without exposing values that the missing production inputs are not already present locally or on the backend host:
  - YooKassa: `YOOKASSA_SHOP_ID`, `YOOKASSA_SECRET_KEY`;
  - Telegram alerts: `GREENVPN_TELEGRAM_ALERT_BOT_TOKEN`, `GREENVPN_TELEGRAM_ALERT_CHAT_ID`;
  - final update/rollback artifact env: `GREENVPN_UPDATE_*`, `GREENVPN_ROLLBACK_*`.
- Closure plan remains owner/final blocked, not code blocked: `canContinueAutonomously=false`, `ownerBlocked=5`, `finalHandoffOnly=1`.
- API/VPN split remains the main public-launch blocker: `api.greenvpn.pro` still overlaps the VPN endpoint IP `37.220.85.211`; `nl1.vpn.greenvpn.pro` still needs to resolve to the VPN endpoint after the split is prepared.
- Current separate site IP candidate `95.163.244.138` was checked read-only: SSH on port `22` is refused, so it cannot be configured autonomously as API reverse proxy or monitoring probe host from this workspace.
- No backend deploy/restart was needed. No public Windows installer was rebuilt.

## 2026-05-08 YooKassa Production Env Applied

- YooKassa production keys were applied to server-only backend env without printing the secret value.
- Live `/healthz`: `paymentsProductionReady=true`.
- Live `/api/v1/admin/billing/readiness`: `provider=yookassa`, `productionReady=true`, `requiredActions=[]`.
- Live external-actions: `payments=done/ready`; pending owner actions are now `updates` and `admin_alerts`.
- A minimal provider-backed smoke order was created by backend billing logic:
  - `149 RUB`, `autoRenew=false`, `status=pending`;
  - YooKassa hosted payment URL is present.
- Payment smoke is not complete yet:
  - `safeToRunSmoke=true`;
  - `pendingWithPaymentUrl=1`;
  - `successfulSmokeCandidates=0`;
  - `smokeCompleted=false`.
- Auto-renewal and subscription expiry enforcement remain blocked by the payment-smoke guard.
- Launch closure plan is now `ready=10`, `pending=8`, `ownerBlocked=4`, `critical=2`; API/VPN split remains the main red production blocker.
- No public Windows installer was rebuilt.

## 2026-05-08 YooKassa Smoke Completed And Renewal Gate Clean

- Minimal YooKassa payment was completed by the owner.
- Backend verified the payment by authoritative YooKassa API fetch:
  - payment status `succeeded`;
  - `paid=true`;
  - order status moved to `activated`;
  - subscription became active.
- Payment smoke readiness is green: `safeToRunSmoke=true`, `smokeCompleted=true`, `successfulSmokeCandidates=1`.
- Server-side `/payment/return` returns HTTP `200`; the browser return-page error is the known local access problem while API/site and VPN endpoint share `37.220.85.211`.
- One old synthetic `codex_payments_...@greenvpn.local` pending order was canceled to clear renewal dry-run conflicts.
- Renewal readiness now reports `safeToEnableAutoRenewalCharges=true` and `requiresAttention=false` for the current due window.
- Strict expiry enforcement remains disabled/unsafe because two trial/free subscriptions are expiring without verified retention contact.
- Closure plan now reports `ready=11`, `pending=7`, `codeOwned=1`, `ownerBlocked=4`.
- No public Windows installer was rebuilt.

## 2026-05-07 API/VPN Endpoint Split Blocker

- Investigated a local Windows failure where `https://api.greenvpn.pro` opened normally with VPN off, but failed with browser `ERR_NETWORK_ACCESS_DENIED` while `AmneziaWGTunnel$device20_full` was active.
- Safe network checks showed:
  - DNS for `api.greenvpn.pro` returns `37.220.85.211`;
  - Windows default IPv4 route is through the active WireGuard adapter `device20_full`;
  - `37.220.85.211/32` is bypassed through physical `Ethernet`;
  - local TCP to `37.220.85.211:443` and `:8000` fails while the tunnel is active;
  - server-side curl confirms backend/site is healthy and `/healthz` returns `version: 0.9.46`.
- Diagnosis: API/public site and VPN endpoint currently share one public IP. For full-tunnel WireGuard/Amnezia on Windows, that endpoint IP must be routed outside the tunnel, and leak-protection/firewall behavior can block browser HTTPS to the same IP. This makes the product appear to break its own site while a tunnel is active.
- Release implication: public release needs API/site IP separation from VPN endpoint IPs. Recommended shape:
  - `api.greenvpn.pro` and public/legal/download site on a separate public IP or small reverse-proxy VPS;
  - VPN endpoints on separate country hosts such as `nl1.vpn.greenvpn.pro`;
  - update server catalog/bootstrap URLs after the split.
- `scripts/windows/check_external_services_readiness.ps1` now includes an `API/VPN endpoint split` guard. It is PowerShell 5.1-compatible and currently reports the expected red result because both `api.greenvpn.pro` and the VPN endpoint resolve to `37.220.85.211`.
- No installer was rebuilt and no third-party VPN/Amnezia/Friendly Linnet configuration was changed.

## 2026-05-07 Public Site Cleanup And Network Readiness

- Backend source version bumped to `0.9.48`.
- Backend `0.9.48` deployed on `37.220.85.211`; live `/healthz` returns `service: Green VPN Backend`.
- Cleaned public download/site wording:
  - removed MVP/release-gate phrasing from user-visible pages;
  - Windows download remains unavailable until final installer verification;
  - Android/iOS download pages are neutral future-platform pages.
- Added admin/product readiness for API/VPN endpoint separation:
  - `GET /api/v1/admin/network/readiness`;
  - `apiVpnEndpointSeparationReadiness` in admin summary;
  - `api_vpn_endpoint_split` in product readiness.
- Updated safe setup defaults so public/API/YooKassa URLs use `https://api.greenvpn.pro`, not raw `http://37.220.85.211:8000`.
- Applied the same non-secret public URL keys to `/etc/bluevpn/backend.env` without printing env contents.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - `bash -n scripts/configure_backend_env_wsl.sh`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -Json -ServerAdminSelfCheck`.
- Current external readiness is intentionally not fully green:
  - green `9`, yellow `2`, red `1`;
  - red is `API/VPN endpoint split` because DNS still maps `api.greenvpn.pro` to VPN endpoint IP `37.220.85.211`.
- Production action needed later: move API/site to a separate public IP or reverse proxy and put VPN endpoint on a separate hostname such as `nl1.vpn.greenvpn.pro`.
- No public Windows installer was rebuilt.

## 2026-05-07 Admin Staff 2FA Candidate

- Backend source version bumped to `0.9.49`.
- Backend `0.9.49` deployed on `37.220.85.211`.
- Added internal admin/support staff 2FA:
  - staff records can enable email-based 2FA;
  - password login returns a pending challenge when 2FA is enabled;
  - `POST /api/v1/admin/auth/2fa/verify` verifies the code and then issues the staff session;
  - codes are hashed with a server-only pepper, expire, have attempt limits, and are not returned or logged;
  - `GET /api/v1/admin/auth/2fa/readiness` reports safe setup status for staff managers.
- Separate `admin_support_app` now includes the 2FA login panel, staff 2FA toggle and 2FA state in team/security views.
- External readiness self-check now verifies the 2FA readiness endpoint.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - Chrome headless admin app smoke with no JS runtime errors reported;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck`.
- Current readiness remains green `9`, yellow `2`, red `1`; the red item is still the expected API/VPN endpoint split blocker.
- No public Windows installer was rebuilt. Next installer remains final-only or explicit stop/test-only.

## 2026-05-07 Launch Readiness Aggregator Candidate

- Backend source version bumped to `0.9.50`.
- Backend `0.9.50` deployed on `37.220.85.211`; live `/healthz` returns `service: Green VPN Backend`.
- Added launch-readiness aggregation for release decisions:
  - protected route `GET /api/v1/admin/launch/readiness`;
  - critical vs warning launch gates;
  - next action text for the owner/developer;
  - billing renewal, subscription expiry, support SLA and external-action summaries included without exposing secrets.
- Separate `admin_support_app` now renders the launch readiness summary on dashboard/release and readiness pages.
- Readiness checker now includes `/api/v1/admin/launch/readiness` in protected server self-check, OpenAPI route inventory and local admin-token checks.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - Chrome headless smoke for `admin_support_app\index.html`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck`.
- Current launch-readiness result is intentionally red:
  - public launch ready: `false`;
  - production ready: `false`;
  - critical blockers: `3`;
  - warnings: `6`.
- Expected blockers remain API/VPN endpoint IP split, YooKassa production readiness, and final installer/update artifact. No public Windows installer was rebuilt.

## 2026-05-07 API/Site And VPN Split Plan Candidate

- Backend source version bumped to `0.9.51`.
- Backend `0.9.51` deployed on `37.220.85.211`; live `/healthz` returns version `0.9.51`.
- Added protected route `GET /api/v1/admin/network/split-plan`.
- Network readiness now carries a concrete non-secret migration plan:
  - keep public API/site on `api.greenvpn.pro`;
  - move VPN endpoint to a separate hostname such as `nl1.vpn.greenvpn.pro`;
  - use `BLUEVPN_ENDPOINT_HOST` and public URL env keys through the existing server env helper;
  - verify API/site while Green VPN is connected before public launch.
- Separate `admin_support_app` renders the split plan in the network readiness block.
- Readiness checker now includes `/api/v1/admin/network/split-plan` in protected server self-checks, OpenAPI inventory and local admin-token checks.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - QuickJS render smoke for the owner packet card;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck`.
- Current readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split blocker until owner provides or orders a separate API/site IP or reverse proxy. No public Windows installer was rebuilt.

## 2026-05-07 New VPS Onboarding Plan Candidate

- Backend source version bumped to `0.9.52`.
- Backend `0.9.52` deployed on `37.220.85.211`; live `/healthz` returns version `0.9.52`.
- Added `newServerOnboardingPlan` to protected `GET /api/v1/admin/server-catalog/provisioning-readiness`.
- The plan keeps future VPN servers safe by default:
  - new VPS entries start as internal `draft`;
  - `isPublic=false`, `isActive=false`, `clientConfigProfile=none`;
  - suggested hostnames are `nl1.vpn.greenvpn.pro`, `de1.vpn.greenvpn.pro`, `kz1.vpn.greenvpn.pro`;
  - publication is locked behind DNS, server WireGuard setup, external probe, server-specific config provisioning, canary and rollback checks.
- Separate `admin_support_app` renders the onboarding plan in the Server Catalog summary.
- Readiness checker now reports `newVpsOnboardingReady`, `safeToCreateInternalDraft`, onboarding phase/blocker counts and the first recommended hostname.
- External owner action text for `server_catalog` now says to prepare internal drafts first, not publish new production endpoints immediately.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Protected self-check confirms current Windows client safety:
  - `safeForCurrentClient=true`;
  - `currentEndpointConfigReady=true`;
  - `newVpsOnboardingReady=true`;
  - public accepted server ids remain `auto` and `intelligent_smew`;
  - managed endpoints are still hidden from users.
- Current readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split blocker. No public Windows installer was rebuilt.

## 2026-05-07 External Server-Health Probe Operator Plan Candidate

- Backend source version bumped to `0.9.53`.
- Backend `0.9.53` deployed on `37.220.85.211`; live `/healthz` returns version `0.9.53`.
- Windows one-off monitoring wrapper now supports:
  - `-ServerHealth`;
  - `-AdminTokenFromStdin`;
  - token file/env input without printing or storing secrets in the repository.
- Protected `GET /api/v1/admin/server-health` now includes an external probe `operatorPlan`:
  - Windows and Linux one-off commands with `--server-health`/`-ServerHealth`;
  - Linux systemd install command with `--server-health --token-stdin`;
  - missing coverage action for `current_wg0`;
  - token policy reminding that admin token must stay outside repo/docs/chat.
- Separate `admin_support_app` renders the server-health external probe plan under endpoint monitoring.
- Readiness checker now verifies that server-health run-once commands use server-health mode and stdin token input.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `run_monitoring_probe_once.ps1`;
  - backend deploy/restart and live health check;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Protected self-check confirms `/api/v1/admin/server-health` exposes `hasOperatorPlan=true`, `runOnceUsesServerHealth=true`, `runOnceUsesStdin=true`, `missingCoverageActions=1`.
- Current readiness remains green `9`, yellow `2`, red `1`; red is still API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-07 Safe VPS Draft Workflow And Public Site Cleanup Candidate

- Backend source/live server version bumped to `0.9.55`.
- Added safe internal new-VPS draft workflow:
  - protected endpoint `POST /api/v1/admin/server-catalog/draft-from-plan`;
  - permission: `servers.manage`;
  - forced safe defaults: `status=draft`, `isPublic=false`, `isActive=false`, `clientConfigProfile=none`, `healthScore=0`;
  - no user-visible catalog publication and no client config profile assignment.
- Server catalog provisioning readiness now exposes `draftCreationEndpoint`, safe draft payload examples and first recommended hostname `nl1.vpn.greenvpn.pro`.
- Separate admin/support app can create a planned VPS draft from the onboarding plan via the `Черновик нового VPS` button.
- Public site pages on `https://api.greenvpn.pro/` were cleaned:
  - download cards for Windows, Android and iPhone/iPad remain visible;
  - user-visible technical blocker phrases were removed from `/`, `/download/windows` and `/legal/offer`;
  - public payment/legal wording no longer says the offer is a draft or awaiting legal review.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `bluevpn_release_gate.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.55`;
  - server-side HTTPS checks for `/`, `/download/windows`, `/legal/offer` found no removed blocker phrases;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Current readiness remains green `9`, yellow `2`, red `1`; the red blocker is still the expected API/VPN endpoint split because `api.greenvpn.pro` and the current VPN endpoint share `37.220.85.211`.
- YooKassa production remains outside-code pending provider status/contract. No public Windows installer was rebuilt.

## 2026-05-07 Promo Campaign Readiness Candidate

- Backend source/live server version bumped to `0.9.56`.
- Added promo campaign readiness for launch planning:
  - protected `GET /api/v1/admin/billing/promos/readiness`;
  - protected `POST /api/v1/admin/billing/promos/draft-start-campaign`;
  - recommended starter campaign `START20`: 20% discount, 100 uses, 30 days, `starter/base/plus`.
- The readiness policy blocks/flags unsafe launch discounts:
  - no redemption limit;
  - no end date or window longer than 60 days;
  - discount above 30% or fixed discount above 200 RUB;
  - missing tariff scope;
  - expired/not-current campaigns.
- Separate admin/support app now renders promo readiness next to promo codes and provides safe `Заполнить START20` and `Черновик START20` actions. The draft action creates an inactive promo only.
- Launch readiness now includes a `promo_campaign` warning gate.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `bluevpn_release_gate.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.56`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Protected self-check confirms promo readiness HTTP 200 with `recommendedCode=START20`, `safeToRunLaunchCampaign=false` until an owner manually reviews/activates a promo.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. YooKassa is still waiting for provider-side approval/contract. No public Windows installer was rebuilt.

## 2026-05-07 New Chat Handoff And YooKassa Activation Status

- Created fresh handoff package:
  - `C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07`
- The package includes 17 transfer files plus README and is now the preferred starting point for the next Codex chat.
- `docs\START_NEW_CODEX_MESSAGE_RU.md` now points to the fresh package.
- `docs\CODEX_CONTEXT_COMPACT_RU.md` now reflects backend live `0.9.56` and current next steps.
- Owner reports YooKassa cabinet is now fully active.
- Backend production payments are not yet marked ready until `YOOKASSA_SHOP_ID` and `YOOKASSA_SECRET_KEY` are applied through `scripts\windows\configure_backend_env_wsl.ps1`.
- Do not paste `YOOKASSA_SECRET_KEY` into chat or docs; it must go only to `/etc/bluevpn/backend.env` on `37.220.85.211`.
- No code deploy and no public Windows installer rebuild were performed for this docs-only handoff step.

## 2026-05-07 Public Site Readiness Gate Candidate

- Backend source/live server version bumped to `0.9.57`.
- Added protected `GET /api/v1/admin/site/readiness`.
- The new site gate checks:
  - public site/download/legal/payment-return routes;
  - server-side legal requisites configuration without exposing private values;
  - download buttons and pricing markers on the landing page;
  - banned public VPN marketing phrases;
  - YooKassa return URL and webhook URL shape.
- Launch/product readiness now include a critical `public_site` gate.
- Admin/support app renders site readiness in the dashboard and production readiness section.
- Readiness checker now probes `/api/v1/admin/site/readiness` in server-side admin self-check and route inventory.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime smoke with temporary local backend dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.57`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live self-check confirms site readiness HTTP 200, `productionReady=true`, `green=7`, `yellow=0`, `bannedPhraseMatches=0`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split. YooKassa production keys are still pending owner/env input. No public Windows installer was rebuilt.

## 2026-05-07 Payment Smoke Readiness Gate Candidate

- Backend source/live server version bumped to `0.9.58`.
- Added protected read-only `GET /api/v1/admin/billing/payment-smoke/readiness`.
- The endpoint:
  - blocks payment smoke until YooKassa production readiness is green;
  - reports safe smoke steps for owner/ops;
  - detects whether recent YooKassa orders have hosted payment URLs or confirmed activation;
  - returns booleans instead of provider payment method ids;
  - states that provider smoke must not use admin mark-paid or direct tariff activation.
- Admin/support app now renders payment smoke readiness in the `Заказы и платежи` panel.
- Readiness checker now probes the endpoint in server-side admin self-check and validates that `providerPaymentMethodId` is not exposed.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime smoke with temporary local backend dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.58`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live self-check confirms payment smoke readiness HTTP 200, `safeToRunSmoke=false`, `smokeCompleted=false`, `methodIdsExposed=false`; expected until owner applies YooKassa keys through safe env.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-07 User Auth Flow Readiness Gate Candidate

- Backend source/live server version bumped to `0.9.59`.
- Added protected read-only `GET /api/v1/admin/auth/user-flow/readiness`.
- The endpoint:
  - confirms the public auth contract is code-first;
  - keeps `phone_code` primary and `email_code` fallback;
  - treats email/password as legacy only;
  - checks delivery readiness, code TTL/cooldown/attempt/lockout policy, auth-code pepper and dev-code exposure;
  - returns only booleans/counters and does not expose one-time codes, tokens, password hashes or provider secrets.
- `/healthz` now reports `userAuthFlowProductionReady`; `/api/v1/bootstrap/windows` now includes auth fallback method and challenge endpoint hints.
- Product/launch readiness now include `user_auth_flow` as a warning gate.
- Admin/support app now renders auth flow readiness above the auth event table.
- Readiness checker now probes `/api/v1/admin/auth/user-flow/readiness`, validates `codesExposed=false` and `tokensExposed=false`, and sends the remote admin self-check Python payload over stdin to avoid command-line length failures.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime smoke with temporary local backend dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - server-side live `/healthz` returns version `0.9.59`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live self-check confirms auth flow readiness HTTP 200, `productionReady=true`, `publicAuthReady=true`, `primaryMethod=phone_code`, `fallbackMethod=email_code`, `codesExposed=false`, `tokensExposed=false`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Launch Closure Plan Gate Candidate

- Backend source/live server version bumped to `0.9.60`.
- Added protected read-only `GET /api/v1/admin/launch/closure-plan`.
- The endpoint separates remaining launch work into:
  - owner-blocked inputs;
  - final-handoff-only work;
  - autonomous code work;
  - operational review.
- The endpoint may name required env keys/actions, but does not return secret values.
- Admin/support app now renders closure-plan status in dashboard/readiness views.
- Readiness checker now probes `/api/v1/admin/launch/closure-plan`, validates `safeNoSecretExposure=true`, checks for obvious secret-value markers, and includes the route in protected self-check inventory.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - runtime smoke with temporary local backend dependencies and temp DB;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.60`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live self-check confirms closure plan HTTP 200 with `total=18`, `ready=8`, `pending=10`, `ownerBlocked=5`, `codeOwned=3`, `operationalReview=4`, `finalHandoffOnly=1`, `secretValuesExposed=false`.
- Next autonomous action from closure plan is `support_sla`; owner-blocked launch inputs remain API/VPN endpoint split, YooKassa production keys, monitoring probe host, Telegram alerts and external owner-action group.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Support SLA Cleanup And Promo Draft Hold

- Closed the only two live support SLA items after verifying both were historical smoke reports (`appVersion=smoke`, summary `support report smoke`).
- The reports were resolved through the existing protected support status endpoint with audit actor `codex-support-sla-cleanup-0.9.60`.
- Live `GET /api/v1/admin/support/sla` now reports `attentionRequired=false`, `open=0`, `overdue=0`, `reviewPending=0`, `firstResponseMissing=0`.
- Created inactive `START20` promo draft through `POST /api/v1/admin/billing/promos/draft-start-campaign`; it is not active and must not be activated until payment/release readiness is green.
- Backend source/live server version bumped to `0.9.61` to refine launch closure logic:
  - if the inactive promo draft exists, `promo_campaign` is no longer returned as the next autonomous action;
  - it is held behind `payments` and `updates`;
  - activation remains a manual review step after launch readiness is green.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.61`;
  - `check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json`.
- Live self-check confirms closure plan HTTP 200 with `ready=9`, `pending=9`, `ownerBlocked=5`, `codeOwned=2`, `operationalReview=3`, `finalHandoffOnly=1`, `nextAutonomousActions=0`, `canContinueAutonomously=false`, `secretValuesExposed=false`.
- Remaining launch work is now owner/final/payment-dependent: API/VPN split, YooKassa production keys/payment smoke, monitoring probe host, Telegram alerts, final installer/update artifact, billing renewal and subscription-expiry review after payments. No public Windows installer was rebuilt.

## 2026-05-08 Owner Action Note Secret Guard

- Backend source/live server version bumped to `0.9.62`.
- External owner-action notes are now server-guarded before DB/audit writes:
  - obvious secret assignments, admin tokens, provider keys, passwords, bearer headers and WireGuard private-key blocks are rejected with HTTP `400`;
  - the error reports only pattern codes, not submitted values;
  - normal status notes remain accepted.
- `GET /api/v1/admin/external-actions` now exposes `ownerActionPolicy.serverEnforced=true` and non-secret `blockedNotePatternCodes`.
- Separate `admin_support_app` renders the owner-note guard state in the owner-actions panel.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now validates that the owner-note guard is enforced and has blocked pattern codes.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - temp DB runtime smoke: fake `YOOKASSA_SECRET_KEY=...` owner note is blocked, safe note is accepted;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.62`;
  - live protected self-check confirms `ownerNoteServerEnforced=true`, `blockedNotePatterns=6`, closure `secretValuesExposed=false`.
- Live negative test against `/api/v1/admin/external-actions/payments` returned HTTP `400`, `detailHasSecretMaterial=true`, and did not echo even the fake submitted value.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 API/VPN Split Preflight Tooling

- Backend source/live server version bumped to `0.9.63`.
- Added non-mutating, secret-free Windows preflight script:
  - `scripts\windows\check_api_vpn_split_preflight.ps1`;
  - checks API HTTPS URL, DNS resolution, expected API/VPN IPs, API/VPN IP overlap, and `/healthz`;
  - supports `-Json` for handoff/self-check usage.
- `/api/v1/admin/network/split-plan` now includes a `preflight` block with the exact command to run after the owner prepares a candidate API/site IP or reverse proxy.
- `external_owner_setup_bundle()` now includes `splitPreflight` metadata.
- Separate `admin_support_app` renders the split preflight command in the network readiness card.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now validates that split-plan has mutation-free JSON preflight metadata using `check_api_vpn_split_preflight.ps1`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - temp runtime smoke for split preflight payload;
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - PowerShell parse checks for `check_external_services_readiness.ps1` and `check_api_vpn_split_preflight.ps1`;
  - local preflight dry-run against current same-IP state returns expected red overlap;
  - backend deploy/restart on `37.220.85.211`;
  - live `/healthz` returns version `0.9.63`;
  - live protected self-check confirms `hasPreflight=true`, `preflightMutationFree=true`, `preflightUsesScript=true`, `preflightJsonReady=true`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the expected API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Admin Support App Owner Note UX Guard

- Backend source/live server version was not changed; live remains `0.9.63`.
- Separate `admin_support_app` now formats structured API errors without `[object Object]`.
- Error fallback formatting redacts sensitive fields such as `input`, `authorization`, `password`, `secret`, `token`, private keys and preshared keys.
- Owner-action note textareas now run a client-side precheck before saving status:
  - obvious private-key blocks, WireGuard private-key assignments, bearer/admin tokens, password/secret assignments and sensitive env assignments are blocked locally;
  - notices show only pattern codes, not submitted values;
  - backend server-side owner note guard remains authoritative.
- Checks passed:
  - QuickJS syntax compile for `admin_support_app\app.js`;
  - targeted QuickJS runtime check: safe note passes, fake `YOOKASSA_SECRET_KEY=...` is flagged, object API errors format with pattern codes, validation `input` value is not shown.
- Post-polish live self-check still reports backend `0.9.63`, green `9`, yellow `2`, red `1`; red remains the API/VPN same-IP split.
- No backend deploy/restart was needed for this local admin app polish. No public Windows installer was rebuilt.

## 2026-05-08 Owner Launch Packet Endpoint

- Backend source/live server version bumped to `0.9.64`.
- Added protected read-only endpoint:
  - `GET /api/v1/admin/launch/owner-packet`;
  - requires `readiness.read`;
  - returns owner-facing commands, pending owner actions, non-secret DNS records, safe defaults, split preflight metadata and after-apply checks.
- Added `scripts\windows\get_owner_launch_packet.ps1` to fetch the packet as sanitized text/JSON while keeping the admin token on the server by default.
- Secret policy:
  - env keys/provider fields may be named;
  - secret values are not returned;
  - payload exposes `safeNoSecretExposure=true` and `policy.noSecretValues=true`.
- Separate `admin_support_app` now renders the owner packet card in the production readiness section.
- `check_external_services_readiness.ps1 -ServerAdminSelfCheck` now includes owner-packet validation.
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

- Backend source/live server version bumped to `0.9.65`.
- Renewal and expiry readiness now require clean payment smoke before they can be considered safe to enable:
  - `/api/v1/admin/billing/renewals/readiness`: `safeToEnableAutoRenewalCharges` requires `paymentSmokeReady=true`;
  - `/api/v1/admin/subscriptions/expiry-readiness`: `safeToEnableExpiryEnforcement` requires `paymentSmokeReady=true`.
- Both endpoints now expose `paymentSmokeCompleted`, `paymentSmokeReady` and `policy.requiresPaymentSmoke=true`.
- Admin/support app renders the payment-smoke dependency in renewal and expiry panels.
- Readiness checker validates that safe flags cannot be true while `paymentSmokeReady=false`.
- Checks passed:
  - `python -m py_compile backend_live\app\main.py`;
  - QuickJS syntax compile and renewal/expiry render smoke for `admin_support_app\app.js`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - temp DB runtime smoke for the future scenario where YooKassa production is configured but payment smoke is not complete;
  - backend deploy/restart on `37.220.85.211`;
  - server-side `/healthz` returns version `0.9.65`;
  - live protected self-check confirms renewal/expiry `paymentSmokeReady=false`, safe flags false and `requiresPaymentSmoke=true`.
- Overall readiness remains green `9`, yellow `2`, red `1`; red is still the API/VPN endpoint split. No public Windows installer was rebuilt.

## 2026-05-08 Payment Launch Safety CLI And Owner Packet Command

- Backend source/live server version bumped to `0.9.66`.
- Added `scripts\windows\check_payment_launch_safety.ps1` for sanitized payment launch safety checks:
  - reads admin token on the server by default;
  - checks billing readiness, payment smoke, renewals and subscription expiry;
  - outputs text or `-Json`;
  - blocks forbidden markers such as `providerPaymentMethodId`, `secretValue`, `adminToken`, `privateKey` and `passwordHash`.
- Owner launch packet now includes mutation-free `payment_launch_safety`; live owner packet has `commands=4`.
- Readiness checker validates `hasPaymentLaunchSafety=true` in owner packet.
- Checks passed:
  - PowerShell parse check and live run for `check_payment_launch_safety.ps1`;
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - owner packet live returns `version=0.9.66`, `commands=4`, `hasPaymentLaunchSafety=true`;
  - payment launch safety live returns `safeForAutomaticBilling=false` until YooKassa/payment smoke is complete;
  - live protected self-check remains green for admin endpoints and reports overall green `9`, yellow `2`, red `1`.
- No public Windows installer was rebuilt.

## 2026-05-08 Monitoring Probe Plan CLI And Owner Packet Command

- Backend source/live server version bumped to `0.9.67`.
- Added `scripts\windows\get_monitoring_probe_plan.ps1`:
  - reads admin token on the server by default;
  - checks monitoring readiness and server-health external probe readiness;
  - outputs sanitized text or `-Json`;
  - verifies token-stdin and server-health command modes;
  - blocks forbidden secret markers.
- Owner launch packet now includes mutation-free `monitoring_probe_plan`; live owner packet has `commands=5`.
- Readiness checker validates `hasMonitoringProbePlan=true`.
- Checks passed:
  - PowerShell parse check and live run for `get_monitoring_probe_plan.ps1`;
  - `python -m py_compile backend_live\app\main.py`;
  - PowerShell parse check for `check_external_services_readiness.ps1`;
  - backend deploy/restart on `37.220.85.211`;
  - owner packet live returns `version=0.9.67`, `commands=5`, `hasMonitoringProbePlan=true`;
  - monitoring probe plan live returns `installCommandUsesTokenStdin=true`, `installCommandUsesServerHealth=true`, `hasOperatorPlan=true`, `safeToProceed=false`;
  - live protected self-check remains green for admin endpoints and reports overall green `9`, yellow `2`, red `1`.
- No public Windows installer was rebuilt.
