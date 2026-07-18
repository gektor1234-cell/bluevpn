# Green VPN Current Handoff

Updated: 2026-07-18.

This is the current operational entry point. Read it together with
`RELEASE_STATE.md`, `PROJECT_MAP_RU.md` and
`PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md`. Dated reports are evidence only.

## Hard rules

1. Run `git status --short` before editing. Never reset or overwrite unrelated
   working-tree changes.
2. Never print, commit or place in ordinary archives API/payment/provider
   credentials, private keys, passwords, OTP values, full invite codes or full
   client profiles.
3. Never touch Friendly Linnet `5.129.237.163` without a new explicit owner
   instruction.
4. Android 0.3.5 is already public and mandatory. Do not republish or roll it
   back without a verified artifact, alternate-node health and an atomic backup.
5. AWG2, Hysteria2, VLESS REALITY/XHTTP, Naive HTTPS and dnstt remain isolated
   to NL2 `5.129.216.42`. The rollout runbook is documentation, not permission
   to deploy them elsewhere.
6. Rewarded ads are enabled only for free Android 0.3.5 connections. Paid
   subscriptions and Windows are exempt. The forced VPN disconnect timer must
   remain disabled unless the owner gives a new explicit instruction.
7. Billing has one writer: Timeweb. RUVDS serves failover reads/auth/config but
   must reject first-payment creation and must not run the renewal executor.
8. Server maintenance is one node at a time after alternate control/data planes
   pass readiness. The owner Windows PC must not be rebooted by automation.
9. Windows 0.3.5 is temporarily public and mandatory by explicit owner decision,
   but remains unsigned. Keep the `NotSigned` status visible in operations and
   expect Windows SmartScreen/reputation warnings until a signed successor is
   released.
10. The admin console is a protected operator surface. Keep Nginx Basic Auth,
    `noindex`, frame denial, staff authentication, RBAC and audit enabled; never
    expose bootstrap tokens or payment/tunnel secrets in the UI or exports.

## Repository

- Root: `C:\Users\gekto\projects\bluevpn`.
- Active branch: `green-vpn-transport-canary-20260711`.
- Android 0.3.3 runtime-fix commit:
  `11b5f546795d8c07bd1a68066aa94a7aa085975a`.
- Android 0.3.3 release tag: `greenvpn-android-0.3.3-2026071608`.
- Android 0.3.4 label-release commit:
  `001db006060ee3d325e4f13236234818dc4be91d`.
- Android 0.3.4 release tag: `greenvpn-android-0.3.4-2026071701`.
- Current final-candidate source checkpoint:
  `ceec7aad27ab0399d3ec93f096bbae83c5187ee6`.
- Current final-candidate tag:
  `greenvpn-final-candidate-autorenew-20260716`.
- Previous final-candidate tag: `greenvpn-final-candidate-20260716`.
- Earlier technical-final code checkpoint:
  `1048312b75d05bf7b5a553927160a367cec6eece`.
- Final handoff tag: `greenvpn-technical-final-20260713`.
- Multiprotocol preview base: `d31c6d78337ce9d212d497e7e112085efd407f26`
  (`greenvpn-multiprotocol-preview-complete-20260713`).
- Stable rollback tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Windows 0.3.4 parity checkpoint:
  `649214dc4a42bfa2aafacd18e815c6159325c163`.
- Windows device-recovery and final-smoke checkpoint:
  `b4ac12f837a896637687d3d860ce56e2e5ba8d81`.
- Windows unsigned-publication checkpoint: the commit containing this handoff.
- Windows 0.3.5 installer-repair checkpoint: the commit containing this handoff.
- Admin console 0.9.121 checkpoint: the commit containing this handoff.
- Android 0.3.5 rewarded-ads checkpoint: the commit containing this handoff.
- Generated binaries belong in `C:\BlueVPN_Builds`, encrypted restore points in
  `C:\Users\gekto\GreenVPN_Checkpoints`, and secrets outside Git.

## Published Admin Console, 2026-07-17

- Operator URL: `https://admin.greenvpn.pro/`. Nginx Basic Auth is the outer
  gate; staff email/password, short-lived session, optional 2FA and backend RBAC
  remain the inner gate.
- Production API version is `0.9.122-ads.3` on both Russian control planes.
  Timeweb remains the only billing writer; RUVDS remains billing read-only.
- One dashboard exposes users, devices, subscriptions, pending payments,
  support workload, incidents and the Android/Windows split. The analytics view
  includes active users for 24 hours, 7 days and 30 days, DAU/MAU, auto-renew,
  saved payment-method counts, platform activity and client-version adoption.
- User, support, payment, auth and audit lists use server-side pagination. User
  search covers email, phone, numeric account id and device id; filters cover
  platform, subscription state, device state and sort order.
- The account card shows identity state, subscription/access override with a
  required operator reason, Android and Windows devices, orders, support history
  and audited account/device/session actions. Up to 100 selected users can be
  handled in one audited batch without reporting missing accounts as successes.
- CSV exports exist for users, payments, support and audit. They require the
  matching read permission, are written to audit, omit provider payment-method
  identifiers and escape spreadsheet formulas.
- Desktop and mobile layouts were physically rendered. Mobile navigation is a
  compact horizontal section bar; tables scroll inside their own container and
  the page has no horizontal overflow.
- Validation: 100 backend tests; Python/JavaScript compile; 264 unique HTML ids;
  live health, database indexes, analytics, pagination, CSV and CORS passed on
  both control planes. Backend SHA-256 is
  `E51399F0C4A36BAF2DAA474B7207EFA771293ED133279EE0A25588FE66A8C551`.
- Rollback:
  - Timeweb backend: `/root/greenvpn-admin-release-backups/20260717T181919Z-timeweb-0.9.121-admin.1`;
  - RUVDS backend: `/root/greenvpn-admin-release-backups/20260717T181612Z-ruvds-0.9.121-admin.1`;
  - Timeweb static: `/root/greenvpn-admin-static-backups/20260717T182028Z-admin-console`.

## Published product releases, 2026-07-18

- The customer server picker exposes logical locations only: `Авто`,
  `Нидерланды`, and `Лондон` when a healthy published London route exists.
  Physical nodes and transports stay internal. Every picker row, including
  `Авто`, has a numeric latency label; an unavailable measurement is displayed
  as `0 мс`.
- Production Android `0.3.5+2026071801`, package `pro.greenvpn.app`:
  `C:\BlueVPN_Builds\public_product_ads_20260718_r1\GreenVPN_Android_0.3.5_2026071801.apk`.
  SHA-256:
  `2C6DF6EB6F9D85E54CE7D9F9CD7FF03D551F715EC09067156CE30DA6437C09ED`.
- Test Android `0.3.5+2026071801`, package `pro.greenvpn.app.beta`:
  `C:\BlueVPN_Builds\public_product_ads_20260718_r1_test\GreenVPN_Android_0.3.5_2026071801.apk`.
  SHA-256:
  `4D34F487573BBB8CA32E2998D4866DC3DF47353A235A38C0FB36D65F22959FBB`.
- Both APKs are release signed, passed artifact verification and were published
  atomically on Timeweb and RUVDS Moscow. Stable and paid-beta Android manifests
  are mandatory and point to the matching hashes.
- Published Windows production installer:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.5_public_20260717_01\GreenVPN_Setup_0.3.5.exe`.
  Product/build: `0.3.5+1707`; SHA-256:
  `70450F03F0B1DFE2DFDB5D5D1BBF017A44B3AAFD5752C684422A049C62344F3B`.
  It is unsigned and was published by explicit owner instruction to production
  as mandatory on both RU control planes.
- Published Windows test installer:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.5_paid_beta_20260717_01\GreenVPN_Beta_Setup_0.3.5-paid-beta.1707.exe`.
  Version `0.3.5-paid-beta.1707`; SHA-256:
  `D5396C4A54ECBFE69750759AF0090E194BC4187397FE54DC5A3A11AF2700955E`.
  It remains optional and uses the isolated paid-beta API contour.

## Rewarded ads, 2026-07-18

- Production and paid-beta backends are `0.9.122-ads.3` on Timeweb and RUVDS
  Moscow. Timeweb remains the only billing writer and all four services are
  healthy.
- The Yandex rewarded block `R-M-19313018-1` is served only to Android 0.3.5
  users whose active plan is free/trial. One completed ad grants one new VPN
  connection. Active paid plans bypass the gate. The platform allow-list is
  exactly `android`, so Windows behavior is unchanged.
- The forced-session timer is disabled on every environment:
  `GREENVPN_FREE_AD_SESSION_TIMER_ENABLED=0` and session seconds are zero. A
  connected VPN is not interrupted for another ad. After a manual disconnect,
  the next free connection requires a new rewarded ad.
- Physical Samsung Android 9 test proved a real Yandex `AdActivity`, reward
  completion, synchronized one-connect grant consumption, VPN
  `CONNECTED`/`VALIDATED`, survival beyond the former three-minute cutoff and
  another ad on the following connection. The test tunnel was disconnected at
  handoff.
- Account deletion now removes ad challenges/grants and records replication
  tombstones by `public_id`. The disposable smoke account and four historical
  orphan ad rows were removed; both paid-beta databases report zero orphan ad
  rows and `PRAGMA quick_check=ok`.
- 100 backend tests and 31 Flutter tests pass, Flutter analysis is clean, all
  eight API manifests, both static paid-beta manifests and all eight download
  checks pass, and the public probe is 31/31. Exact production and test APKs
  downloaded from the primary site match the hashes above.
- Yandex Partner remains an external owner gate: add the application-store URL
  and complete the requested payout/legal profile. Do not enter bank, passport,
  tax or self-employment data on the owner's behalf.
- Rollback directories:
  - APK Timeweb: `/root/greenvpn-apk-release-backups/20260718T115642Z-timeweb-0.3.5-2026071801`;
  - APK RUVDS: `/root/greenvpn-apk-release-backups/20260718T115552Z-ruvds-0.3.5-2026071801`;
  - production backend Timeweb: `/root/greenvpn-public-product-backups/20260718T122021Z-timeweb-0.9.122-ads.3`;
  - production backend RUVDS: `/root/greenvpn-public-product-backups/20260718T121922Z-ruvds-0.9.122-ads.3`;
  - paid-beta backend Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T122017Z-paid-beta-backend-rewarded-ads-tombstones-20260718-r27`;
  - paid-beta backend RUVDS: `/root/greenvpn-paid-beta-backend-backups/20260718T121906Z-paid-beta-backend-rewarded-ads-tombstones-20260718-r27`;
  - static manifest Timeweb: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120557Z-android-0.3.5-2026071801`;
  - static manifest RUVDS: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120534Z-android-0.3.5-2026071801`.
  - orphan cleanup Timeweb: `/root/greenvpn-paid-beta-ad-orphan-cleanup-backups/20260718T122049Z`.

## Published Windows 0.3.5 installer repair, 2026-07-17

- Root cause of the external silent installation: browser downloads can carry
  `ZoneId=3`; the 0.3.4 IExpress entry point executed `install_ui.ps1` directly
  under `RemoteSigned`, so Windows rejected the unsigned extracted script before
  the UI and install transcript started.
- IExpress now launches `install_bootstrap.exe`, a native .NET Framework helper.
  It removes the Internet-zone stream only from this installer's extracted UI,
  install script, payload archive and icon, then retains `RemoteSigned` for the
  existing branded UI. It does not use `ExecutionPolicy Bypass`.
- Installation success now requires a real `greenvpn.exe`, desktop shortcut and
  Start menu shortcut. Both links are reopened and their targets checked before
  the installer can return success.
- The source bootstrap and exact compiled production/test bootstrap binaries
  passed MOTW simulations. Standard release gate: zero warnings/errors.
- Production `0.3.5+1707` is mandatory; test
  `0.3.5-paid-beta.1707` remains optional. Main/fallback public EXEs match their
  respective hashes byte-for-byte. Manifest/download check is fully green and
  the independent public surface probe is 31/31.
- Rollback:
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T201752Z-ruvds-0.3.5-1707`;
  - Timeweb Moscow: `/root/greenvpn-windows-release-backups/20260717T201835Z-timeweb-0.3.5-1707`.
- Authenticode is still a separate external gate. The current shell is not
  elevated, so a physical privileged install on this PC requires the owner to
  accept UAC and is not claimed by this checkpoint.
- Android 0.3.4 production UI was checked after an in-place update on physical
  Android 9 and Android 16/API 36. Both pickers contain exactly one `Авто`, one
  `Нидерланды` and one `Лондон` row; all carry numeric latency while the
  physical routes remain hidden. The earlier pre-London screenshot is
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716\evidence\android9-server-picker.png`.
  Production 0.3.3 previously connected specifically to London, reached Android
  `CONNECTED` and `VALIDATED`, and played YouTube to completion. Removing its
  activity stack left the foreground VPN service and `tun0` active; reopening
  restored the live England state. Test 0.3.3 independently connected to the
  same location through the paid-beta catalog. Both packages disconnected
  cleanly and were returned to `Автовыбор`.
- Auto-renew management now has one compact entry in Settings and a dedicated
  page for card-binding status and cancellation. The tariff page keeps only the
  purchase-time auto-renew switch and has no active-subscription cancellation
  action. Physical Android 9 QA confirmed the disabled/unlinked state without
  layout overlap. Evidence:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716_r3\evidence\android9-auto-renew-off.png`.
  SHA-256:
  `0A711DD99C1BA67E1AD07A267DB9FC762C89C5488AA53094EFFBC0B79EC4BAAB`.
- Build manifests are stored beside the production and test artifacts in
  `C:\BlueVPN_Builds\public_product_release_20260716_r6` and
  `C:\BlueVPN_Builds\public_product_release_20260716_r6_test`.
  They record package IDs, versions, build numbers, sizes, signing state and
  exact artifact hashes.
- The exact website APK was downloaded from both Russian public nodes; both
  files are byte-identical to the production artifact. After removing the old
  package, clean installs on Samsung Android 9 and Android 16 completed login,
  delayed idle, all primary taps, server selection and a real Netherlands VPN
  connection without a crash. Production API, both paid API ingresses and
  YouTube passed through the tunnel. Android 9 retained the tunnel after Home
  and removal from recent tasks, restored live state on reopen, and disconnected
  cleanly.
- Root cause of the superseded 0.3.2 Android 16 crash: standard WireGuard and
  AWG2 loaded separate Go shared runtimes into the same application process.
  The release removes the unsafe diagnostic version call, isolates AWG2 in
  `:greenvpn_awg2`, shares one standard-tunnel runtime between UI, watchdog and
  quick tile, and runs native commands off the main thread. Automatic recovery
  from an injected AWG2 stop to Hysteria2 was physically proven.
- `flutter analyze`, Flutter tests, backend tests, Android native unit
  tasks, both APK verifiers, public-surface probes, dependency audit, secret
  scan, standard release gate and strict payment gate are green.

## Published Windows 0.3.4, 2026-07-17

- A valid encrypted saved session now opens the product directly, matching
  Android instead of showing the login gate again.
- Closing the visible window hides it to the tray; launching the executable
  again restores the existing process and window.
- Tray connect and disconnect use the authenticated local service API on a
  background thread, enforce an HTTP success response and show Russian result
  notifications without blocking the UI.
- The updater accepts only hostful HTTPS public URLs and launches the downloaded
  installer directly without `cmd.exe`.
- The server picker exposes only `Auto`, `Netherlands` and `London`, each with
  numeric latency. Provider, physical node and transport names remain hidden.
- Windows selective routing consistently uses service wording; Android retains
  application/package wording. Tariff cards show one, three or six months, and
  settings keep the dedicated auto-renew management page.
- The installer has Russian visible copy and neutral Green VPN service wording.
  It does not expose the underlying tunnel implementation.
- The Windows-only public build explicitly leaves `transportCascade=false`.
  No server, catalog or anti-blocking preview deployment changed in this work.
- `flutter analyze`, 31 Flutter tests with two intentional skips, 42 backend
  tests, the Windows C++ build and the release gate are green.
- Physical UI checks passed for clean login, saved-session entry, tray hide and
  restore, primary navigation, logical server picker, tariff, settings and
  update pages. The authenticated service path was also proven: it correctly
  rejected a connect request while the owner's Amnezia tunnel was active.
- A Windows device retired automatically by the device-limit policy now rotates
  its local identity once, obtains a fresh config and preserves the saved
  session. Administrator-disabled devices do not bypass policy. The fix was
  physically proven against paid-beta after overwriting the protected hidden
  state file and fetching a new config from the control plane.
- The final elevated network transition passed with a fresh handshake, positive
  RX/TX, YouTube/API probes, DNS resolution, no direct DNS leak and 10/10 green
  protection checks. Cleanup removed the test tunnel and restored Amnezia,
  ordinary Internet access and both production API ingress paths. Evidence:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.4_rc_20260717_06\windows-network-transition-report.json`.
- The exact production and test bytes are published on Timeweb and RUVDS Moscow.
  All eight Android/Windows manifests, all eight download probes, the paid-beta
  static manifest and the independent 31-target public probe pass. Production
  Windows is mandatory; test Windows remains optional.
- Authenticode remains an acknowledged trust/reputation defect. Do not silently
  replace public 0.3.4 with different signed bytes under the same version; build
  and publish a higher signed successor so installed clients receive it.

## Live topology

| Role | Host | Current state |
| --- | --- | --- |
| Primary RU control plane | Timeweb Moscow `72.56.32.197` | production API, paid candidate API, site, SMTP, billing writer, DB sync |
| Fallback RU control plane | RUVDS Moscow `176.113.81.35` | production/paid failover, site mirror, SMTP, DB sync, billing read-only |
| Stable VPN NL1 | `37.220.85.211` | stable UDP tunnel active; obsolete Certbot/API TLS retired |
| Stable VPN London | `88.218.250.86` | existing VPS `2584554` active; preserved disk/config restored; production and paid-beta publish one logical `Лондон` |
| Stable VPN + preview NL2 | `5.129.216.42` | stable UDP tunnel plus five isolated hidden preview transports |
| Excluded host | `5.129.237.163` | not managed by this project; do not modify |

RUVDS support restored the existing London VM in place and confirmed it in
ticket `2026071628000134` on 2026-07-16 at 12:28 MSK. The provider API returned
`active`, SSH reopened and the original disk, IP and configuration were
preserved. No replacement VPS or second payment was created. At 14:09 MSK the
same ticket received our verified completion reply and request to close it.

Before repair, the root-only backup
`/root/greenvpn-london-recovery-backups/20260716T100956Z` captured WireGuard,
BlueVPN, nginx, routing/WARP scripts, systemd and firewall state and passed
archive/SHA-256 verification. The only confirmed missing runtime object was
`greenvpn-london-app-subnet-restore.service`; it was restored from the tracked
unit, enabled and proven idempotent. `wg0`, `wgcf`, nginx and backend are active,
both `10.10.0.0/24` and `10.66.66.0/24` routes/NAT are present, and there are no
failed units. The existing capacity reporter passed a manual apply and its
one-minute timer is enabled again.

Both Russian control planes passed remote provisioning, temporary peer and
client-config smoke against London in production and paid-beta. A separate
isolated network-namespace smoke from each control plane proved real handshake,
positive RX/TX, matching London egress and 3/3 API, Google and YouTube checks,
with complete cleanup. Publication gates were green on both databases before
the node was opened as the single logical location `Лондон`.

The former Timeweb KZ VPS `8360589` / `94.198.221.206` was proven inactive and
retired. Provider recovery image
`2d3d1ae6-899f-48f0-ba1e-985eb5e0344d`
(`greenvpn-kz1-retirement-20260713`) completed successfully and is the rollback
material. KZ is not in DNS, catalogs or assignment state.

## Stable public contour

- Site/API: `https://greenvpn.pro`, `https://api.greenvpn.pro`.
- Backend: `0.9.122-ads.3` on both RU control planes.
- Android: `0.3.5`, build `2026071801`, package `pro.greenvpn.app`, SHA-256
  `2C6DF6EB6F9D85E54CE7D9F9CD7FF03D551F715EC09067156CE30DA6437C09ED`.
- Android update is mandatory on Timeweb and RUVDS Moscow; both manifests report
  `required=true` and `fileReady=true`.
- Windows: `0.3.5+1707`, mandatory, unsigned, SHA-256
  `70450F03F0B1DFE2DFDB5D5D1BBF017A44B3AAFD5752C684422A049C62344F3B`.
- Public catalog contains only stable client-compatible endpoints. Server/provider
  implementation details are not shown in the client.
- Both production control planes publish the same three physical stable routes;
  Android groups them into `Нидерланды` and `Лондон` plus `Авто`.
- Login, bootstrap, catalog, downloads, legal routes and update manifests are
  available through primary and fallback Russian ingress.

## Paid public candidate

- Paths remain isolated at `/paid-beta` and `/paid-beta-api` until promotion.
- Both control planes currently report backend `0.9.122-ads.3`.
- Both SQLite databases pass `PRAGMA quick_check`.
- The public-product client marker permits the final public candidate to create
  a 249 RUB order for accounts previously enrolled in the paid-beta cohort;
  unmarked legacy clients remain rejected.
- Android test release: `0.3.5+2026071801`, package
  `pro.greenvpn.app.beta`, side-by-side with stable, SHA-256
  `4D34F487573BBB8CA32E2998D4866DC3DF47353A235A38C0FB36D65F22959FBB`.
- Windows candidate: `0.3.5-paid-beta.1707`, SHA-256
  `D5396C4A54ECBFE69750759AF0090E194BC4187397FE54DC5A3A11AF2700955E`.
  It is published on both RU nodes, technically tested, unsigned and optional.
- Product model: trial 3 days; 249/649/1099 RUB for 30/90/180 days; free Android
  connections require rewarded ads, paid plans have no ads, and there is no
  disconnect timer; auto-renew is opt-out after YooKassa approval.
- The real 249 RUB provider-backed payment smoke and the subsequent unlink
  smoke are complete. The paid period remains active through 2026-09-09;
  `auto_renew=0` and the saved payment method is absent on both synchronized
  control planes. No automatic charge candidate is due.

## Database and control-plane behavior

- Production and candidate DB sync timers are active on both RU nodes.
- Node identity ranges are disjoint. Inserts/updates and explicit deletes are
  replicated; deletes use `replication_tombstones`.
- Tombstones containing `user_id` are remapped through the email-based node ID
  map before application. Optional tables absent on both peers are skipped; a
  table present on only one peer remains a hard schema error.
- Snapshots are gzip-tested before merge. Live SQLite files are never replaced
  wholesale by peer snapshots.
- After the clock repair, explicit production cycles converged on both nodes to
  `inserted=0`, `updated=0`, `conflicts=0`, `errors=0`.
- Explicit paid-candidate cycles converged to zero changes with 201 skipped rows,
  zero conflicts and zero errors.
- Timeweb and RUVDS production DBs have no impossible future event timestamps.
  Candidate DB repair corrected values created while RUVDS clock was wrong;
  both nodes now report `eventFutureValues=0`.

## Server baseline and cleanup

- Timeweb Moscow: packages/SSH baseline applied; disk is 14%.
- RUVDS Moscow: Debian security baseline, Fail2ban, unattended upgrades,
  key-only SSH and chrony are active; clock offset is at microsecond scale;
  disk is 28%.
- London: historical recovery material and an unreferenced 539 MB plaintext DB
  duplicate were removed after verified checkpoints while preserving the latest
  known-good copy. Chrony is active and a
  controlled service stop/clock step corrected the former +3 hour skew. DB
  backup `/root/greenvpn-clock-fix-backups/20260713T143111Z` passed quick-check;
  tunnel, WARP, backend and nginx were restored and verified; disk is 46%.
  The 2026-07-16 provider recovery preserved that state. The missing app-subnet
  restore unit was reinstalled, the capacity timer was re-enabled, and complete
  control-plane plus physical Android smoke passed before publication.
- NL1: obsolete Certbot/API TLS retired; missing WireGuard `[Interface]` state
  was repaired from guarded data with the expected public-key fingerprint. A
  stale May one-time admin credential file was removed by the guarded ACL tool;
  disk is 39%.
- NL2: conflicting unused dnsmasq is disabled and masked; dnsdist remains the
  only public DNS frontend. OS/SSH baseline and current kernel are active, with
  no failed units; disk is 11%.
- Timeweb Moscow, NL1 and NL2 each report only provider-held
  `qemu-guest-agent`; actionable package updates are zero on every managed host.

## Isolated transport preview

- Only NL2 carries AWG2 UDP/1443, Hysteria2 UDP/2443, VLESS REALITY/XHTTP,
  Naive HTTPS TCP/8443 and dnstt behind dnsdist UDP/TCP/53.
- Stable UDP/443 remained active and unchanged through all canary work.
- Real Android data-plane/fail-closed/reconnect/background proofs exist for all
  five stages. Windows physical proofs exist for AWG2, Hysteria2 and VLESS;
  Naive non-disruptive SOCKS proof passed. These are preview evidence, not a
  stable release authorization.
- Reusable server procedure:
  `SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md`.
- Current readiness helpers include
  `check_hysteria2_canary_readiness.sh`,
  `check_vless_reality_canary_readiness.sh`, the existing Naive/dnstt checkers
  and AWG2 static readiness. No checker prints credentials.

## Verified gates

- Public surface probe: 31/31 targets green after Android 0.3.5 publication.
- Backend tests: 100 passed.
- `pip-audit`: no known vulnerabilities.
- `flutter analyze`: no issues.
- Flutter tests: 31 passed and 2 public-only tests skipped by design.
- Android debug/profile/release unit-test tasks: 343 tasks successful.
- Release gate: 0 warnings, 0 errors.
- Secret scan: tracked, untracked and complete Git history passed.
- Remaining build warnings are in third-party Pub packages (`file_picker` and
  `yandex_mobileads`), not project source.

## Restore points

- Android 0.3.5 online rollback directories:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260718T115642Z-timeweb-0.3.5-2026071801`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260718T115552Z-ruvds-0.3.5-2026071801`.
- Backend 0.9.122 production deployment backup directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260718T122021Z-timeweb-0.9.122-ads.3`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260718T121922Z-ruvds-0.9.122-ads.3`.
- Backend 0.9.122 paid-beta deployment backup directories:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T122017Z-paid-beta-backend-rewarded-ads-tombstones-20260718-r27`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260718T121906Z-paid-beta-backend-rewarded-ads-tombstones-20260718-r27`.

- Android 0.3.4 online rollback directories:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260717T090025Z-timeweb-0.3.4-2026071701`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260717T085953Z-ruvds-0.3.4-2026071701`.
  They retain the previous APK aliases and environment files with root-only
  permissions.
- Backend 0.9.120 production deployment backup directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260717T114255Z-timeweb-0.9.120-public.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260717T114344Z-ruvds-0.9.120-public.1`.
- Backend 0.9.120 paid-candidate deployment backup directories:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260717T114249Z-paid-beta-backend-windows-device-recovery-20260717-r24`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260717T114333Z-paid-beta-backend-windows-device-recovery-20260717-r24`.
- Previous backend 0.9.119 production rollback directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260716T175852Z-timeweb-0.9.119-public.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260716T175914Z-ruvds-0.9.119-public.1`.
- Previous backend 0.9.119 paid-candidate rollback directories:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260716T175858Z-paid-beta-backend-fallback-peer-20260716-r23`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260716T175919Z-paid-beta-backend-fallback-peer-20260716-r23`.
- Windows 0.3.4 pre-release rollback directories, containing the previous
  production/test EXEs and env files:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260717T122847Z-timeweb-0.3.4-1706`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T122919Z-ruvds-0.3.4-1706`.
- Windows static-manifest correction backups:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260717T123644Z-timeweb-0.3.4-1706`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260717T123748Z-ruvds-0.3.4-1706`.
- London runtime backup before the 2026-07-16 repair:
  `/root/greenvpn-london-recovery-backups/20260716T100956Z`.
- London catalog online DB backups, all `PRAGMA quick_check=ok`:
  - production Timeweb: `/root/greenvpn-london-catalog-backups/20260716T103621Z-timeweb`;
  - production RUVDS: `/root/greenvpn-london-catalog-backups/20260716T103621Z-ruvds-moscow`;
  - paid-beta Timeweb: `/root/greenvpn-london-catalog-backups/20260716T104858Z-timeweb-paid-beta`;
  - paid-beta RUVDS: `/root/greenvpn-london-catalog-backups/20260716T104858Z-ruvds-moscow-paid-beta`.
- Verified encrypted final-candidate checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_final_candidate_20260716_010736`.
- Final-candidate `server_state.7z` SHA-256:
  `B376020D3E28663C798CE65ED337D439A4E00CA7DFBB7B429AE722EA15197FEE`.
- Final-candidate `local_state.7z` SHA-256:
  `2D77820204CAE220610ABE7C8027AB14B3BA3D1479C2239E99125D6329AC9699`.
- The local archive records repository head
  `19d114cb616d2dc0eeb7e42afa13bab14d7aad44` with zero untracked files.
  The server archive contains Timeweb Moscow, RUVDS Moscow, NL1 and NL2.
  London was deliberately omitted because its provider state was `notpaid` at
  checkpoint time; its earlier recovery material remains preserved.
- Both archives use encrypted headers, pass `7z t`, reject a wrong password,
  have restricted ACLs and leave no plaintext staging or remote temporary
  files.
- Verified encrypted technical-final checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_technical_final_green_ci_20260713_185901`.
- Technical-final `server_state.7z` SHA-256:
  `86847313267BFCD2F06E11CF064AA5D8F2A77C403AB9C8997569577DCD139C68`.
- Technical-final `local_state.7z` SHA-256:
  `FA0B97F32F1323E092B9C5E042C46E48FC1FE6167534CEC5EC2DDB4363B3A39F`.
- The local archive records repository head
  `1048312b75d05bf7b5a553927160a367cec6eece` with a clean working tree.
- Both final archives use encrypted headers, pass `7z t`, reject a wrong
  password, have exact owner/SYSTEM/Administrators ACLs and leave no plaintext
  or password-rotation staging directory.
- Verified encrypted pre-cleanup checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_project_pre_cleanup_20260713_124114`.
- `server_state.7z` SHA-256:
  `89DF0C132CC1E12D9284BB57B752C5A9F07D059804C2015CC80715A462D03578`.
- `local_state.7z` SHA-256:
  `D1324849CFB9CC6A3CEA72AA65B36CDFEF33F6102433D017E4C9B118631F03EF`.
- The pre-cleanup archives use encrypted headers, pass `7z t`, have restricted
  ACLs and left no plaintext staging data.

## Remaining owner/external launch gates

1. Obtain an Authenticode code-signing certificate and build a higher-version
   signed Windows successor.
2. Atomically replace the temporary unsigned release on main and test, verify
   all manifests/downloads and retain deployment backups. Android, London and
   server contours are already complete.
3. In Yandex Partner, the owner must add the published application-store URL
   and complete the payout/legal profile before the displayed deadline. This
   requires personal bank, identity and tax data and cannot be automated.

Do not perform a real payment, enter SMS/bank codes or accept legal terms on
behalf of the owner.
