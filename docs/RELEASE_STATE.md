# Green VPN Release State

Updated: 2026-07-19.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.129-final-audit.5` |
| Fallback API | RUVDS Moscow, backend `0.9.129-final-audit.5` |
| Android | `0.3.7+2026071902`, package `pro.greenvpn.app`, mandatory |
| Android SHA-256 | `CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431` |
| Windows | `0.3.6+1808`, mandatory, unsigned |
| Windows SHA-256 | `0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA` |
| Ads/session timer | rewarded ads enabled for free Android connections; paid users exempt; forced disconnect timer disabled |

Android 0.3.7 is published on Timeweb and RUVDS Moscow. Both stable manifests
have `required=true` and `fileReady=true`; the previous APK is retained in the
root-only deployment backups listed under Rollback.

## Freemium And Windows Rewarded Beta, 2026-07-19

- Production remains unchanged at backend `0.9.129-final-audit.5`, Android
  `0.3.7` and Windows `0.3.6`. Its rewarded-ad platform allow-list is still
  exactly `android`; no test advertising path is enabled in production.
- The isolated paid-beta contour runs backend `0.9.131-freemium.2` on Timeweb
  and RUVDS Moscow. Free accounts cannot request `social_only` configs; the
  client also routes the locked control to the tariff page. Existing logical
  Netherlands and London entries remain free. New server-catalog drafts
  default to `premium`, and both the public catalog and config endpoint enforce
  that tier server-side.
- Paid-beta Android is `0.3.9+2026071902`, package
  `pro.greenvpn.app.beta`, SHA-256
  `2B016FCB70A8C50DD6D5F86DD2B326CFB82D636AA9CB39D1FB8BC25B38A91AFC`.
- Paid-beta Windows is unsigned `0.3.9-paid-beta.1902`, SHA-256
  `CE282C7BC56082F53DA030F047DA83F7FDD64315DD9C4FFE823B9C023BDBA8FC`.
  The exact public installer is installed on the owner PC, its app and system
  service are running, both common desktop and Start menu shortcuts exist, and
  the saved paid session opens the product without a crash. Evidence:
  `C:\BlueVPN_Builds\green_vpn_0.3.9_public_download_verify\windows-beta-current.png`.
- Paid-beta enables the ad gate for `android,windows`. Android keeps the real
  Yandex Mobile Ads rewarded unit. Windows uses `test_web` only in this closed
  contour. One completed challenge grants one config/connect operation and the
  forced disconnect timer is disabled. Production rejects `test_web` by code
  and configuration.
- The final deployment corrected the beta test flag contract: the deploy script
  and backend now share `GREENVPN_FREE_AD_TEST_WEB_ENABLED`, while the backend
  keeps the former key as a read-only compatibility fallback. The running
  process environments on both nodes report the canonical flag enabled.
- The current Windows beta session belongs to an active paid 249 RUB plan, so
  its live bootstrap correctly bypasses ads and leaves social-only routing
  available. Free-user denial, provider selection, reward completion and
  one-connect consumption are covered by the 128-test backend suite and 46
  Flutter tests; no disposable live account was created.
- Real production Windows rewarded ads are externally blocked until Yandex
  approves desktop Web Rewarded for site `api.greenvpn.pro` (site id
  `19615469`) and supplies a block id matching `R-A-N-N`. The support request
  is open. Production promotion must wait for that id and a real beta reward
  callback smoke; a local or fake completion button is forbidden.
- Paid-beta rollback directories:
  - backend Timeweb:
    `/root/greenvpn-paid-beta-backend-backups/20260719T125141Z-paid-beta-backend-freemium-20260719-r7`;
  - backend RUVDS Moscow:
    `/root/greenvpn-paid-beta-backend-backups/20260719T124934Z-paid-beta-backend-freemium-20260719-r7`;
  - client Timeweb:
    `/root/greenvpn-paid-beta-client-release-backups/20260719T103659Z-timeweb-0.3.9-paid-beta.1902-0.3.9-paid-beta.1902`;
  - client RUVDS Moscow:
    `/root/greenvpn-paid-beta-client-release-backups/20260719T103700Z-ruvds-0.3.9-paid-beta.1902-0.3.9-paid-beta.1902`;
  - Windows ad env Timeweb:
    `/root/greenvpn-rewarded-ads-backups/20260719T104843Z-paid-beta-windows`;
  - Windows ad env RUVDS Moscow:
    `/root/greenvpn-rewarded-ads-backups/20260719T104844Z-paid-beta-windows`.

## Final Full Audit, 2026-07-19

- Production and paid-beta services on both Russian control planes run backend
  `0.9.129-final-audit.5`. All four health endpoints are green, all databases
  pass `PRAGMA quick_check`, and explicit production and paid-beta sync cycles
  converge without conflicts or errors.
- The active-active merger now preserves the newest verified email and phone
  state independently from unrelated profile updates. Admin identity login
  throttling is keyed by identity across source IPs, preventing an IP rotation
  from bypassing the account-level limit.
- Operational retention is bounded and installed as a guarded timer on both
  nodes. It prunes only old operational telemetry after an online database
  backup; account, subscription, billing, support and catalog data are outside
  its deletion scope.
- Validation passed: 122 backend tests, 34 Flutter tests plus two intentional
  skips, clean Flutter analysis, Android unit tests and lint, dependency audit,
  90 PowerShell syntax checks, 64 project-owned Bash syntax checks, JavaScript
  parse, strict release gate, full current/untracked/history secret scan and
  `git diff --check`.
- Android production and test 0.3.7 were physically exercised on Android 9 and
  Android 16 across login, idle, every primary screen, location selection,
  connection, validated traffic, YouTube, background/task removal, restore and
  disconnect. Crash buffers remained empty.
- Windows 0.3.6 production and paid-beta packages passed complete package,
  native-bootstrap and browser MOTW checks. The installation matrix also
  proves clean install, reinstall while running, uninstall, rollback and
  recovery without disturbing the owner's existing VPN or Internet. The exact
  final public EXE still requires one owner-approved UAC run on the target PC;
  automation does not accept that elevation prompt.
- Public verification is green: 31/31 independent surface probes, eight API
  manifests, two static manifests and eight downloads. Main site, legal pages,
  admin static files and both mirrors match their expected hashes.

## Published Admin Console

| Component | Version/state |
| --- | --- |
| URL | `https://admin.greenvpn.pro/`, Basic Auth plus staff session/RBAC |
| Production backend | `0.9.129-final-audit.5` on Timeweb and RUVDS Moscow |
| Backend SHA-256 | `FB35FDA24856A64C3506107734CEAB8DCCC7B10B5B355950618784DB1661AFC8` |
| Static index SHA-256 | `68E8081DDE9674CD3B11CC70E910AF68C998C7F54C3AC918CFE15A4F9AAEBF83` |
| Static JavaScript SHA-256 | `A27BB2ABC8B8C908CC707DEF9A5D4B62F58CFE9630818E3CCB1157423BDBF528` |
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
| Primary/fallback backend | `0.9.131-freemium.2` |
| Android | `0.3.9+2026071902`, package `pro.greenvpn.app.beta`, optional |
| Android SHA-256 | `2B016FCB70A8C50DD6D5F86DD2B326CFB82D636AA9CB39D1FB8BC25B38A91AFC` |
| Windows | `0.3.9-paid-beta.1902`, optional, unsigned |
| Windows SHA-256 | `CE282C7BC56082F53DA030F047DA83F7FDD64315DD9C4FFE823B9C023BDBA8FC` |
| Plans | trial 3 days; 249/649/1099 RUB for 30/90/180 days |
| Auto-renew | recurring card binding approved; real save-method and unlink smoke passed on both control planes |
| Billing writer | Timeweb only |
| DB replication | active-active state merge with tombstones |
| Ads/session timer | Android real rewarded plus Windows closed `test_web`; paid users exempt; timer disabled |

The candidate is isolated at `/paid-beta` and `/paid-beta-api`. It is not a
closed-first-20 product anymore, but those paths remain the safe staging contour
until public promotion.

## Published Android Product Release

| Component | Version/state |
| --- | --- |
| Customer location model | one row per location; `Авто / Нидерланды / Лондон`; physical routes hidden |
| Latency model | every picker row, including `Авто`, shows `N мс`; missing measurement becomes `0 мс` |
| Source base | Android 0.3.6 account-switch release plus final lifecycle hardening |
| Android production | `0.3.7+2026071902`, package `pro.greenvpn.app`, release signed |
| Android production SHA-256 | `CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431` |
| Android test | `0.3.7+2026071902`, package `pro.greenvpn.app.beta`, release signed |
| Android test SHA-256 | `910D7C8D03E224484050EFB4AE845C0B2DD6FC592B85B7A3FF8B1475DE21E5C5` |
| Windows production | `0.3.6+1808`, mandatory, unsigned |
| Windows production SHA-256 | `0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA` |
| Windows test | `0.3.6-paid-beta.1808`, optional, unsigned |
| Windows test SHA-256 | `19BCCFB0866CAC69F78B9F6A3BFBC8C9A0AFE293876D95E3091179FEEBAB2AF4` |
| YooKassa | real 249 RUB payment, saved-method verification and unlink smoke complete |
| London | existing VPS `2584554` restored in place; production and paid-beta catalogs publish one logical `Лондон` location |

Production and test APKs are published on both Russian control planes. The
customer-facing stable and paid-beta update manifests force 0.3.7 and all four
public APK aliases are ready.

## Confirmed Test-account Cleanup

- Six production and one paid-beta identities were confirmed as Codex-created
  test, payment-shape, webhook, preview or incomplete-registration accounts.
  Ambiguous identities, phone-generated identities and every real-looking
  customer account were excluded from the operation.
- The production account count changed from 31 to 25 on each control plane;
  paid-beta changed from 2 to 1. The complete preserved identity digest and the
  protected `users`/`devices`/`subscriptions`/`billing_orders` state match the
  pre-delete backup on both nodes.
- Account deletion now removes endpoint and transport assignments, client route
  telemetry, invite/funnel rows, ad grants/challenges and every other user-owned
  row before the user. It removes the live/configured peer and records all
  replicated natural-key tombstones so a peer cannot be resurrected by sync.
- Post-delete verification reports zero candidate-dependent rows and zero old
  public-key hits in live `wg0` or `/etc/wireguard/wg0.conf` on both nodes.
  Explicit production and paid-beta sync cycles succeeded and did not restore
  any deleted identity.
- Backend `0.9.124-admin-cleanup.1` is deployed on all four services. Source
  `main.py` SHA-256 is
  `94E3879A429CF618CAC02817D2199736B9249BAED994E586222C63E673B1295E`;
  the synchronized state-merge script SHA-256 is
  `BC1A55F94913EEA3759ABC4A058A3FE1F75932B9BBD576F2C2FF906CDF2F6457`.
- Validation: 102 backend tests, Python compile, shell syntax, SQLite
  `quick_check`, protected-state digest, explicit sync and all four public
  health endpoints. The admin origin still returns the expected unauthenticated
  `401` at the outer Basic Auth gate.

## Rewarded Ads Activation

- Backend `0.9.124-admin-cleanup.1` is deployed on production and paid-beta
  services on both Russian control planes. It preserves the rewarded-ad policy
  of `0.9.123-ads.1` unchanged while adding complete account cleanup.
- Yandex rewarded block `R-M-19313018-1` is enabled for Android 0.3.5 and newer
  clients on free/trial plans. A completed ad grants exactly one new VPN
  connection. Paid active subscriptions bypass the gate. Windows is unchanged.
- `GREENVPN_FREE_AD_SESSION_TIMER_ENABLED=0` and session seconds are zero on
  all four service environments. Once connected, a free session is not ended
  by an advertising timer; the next ad is requested only after the user
  disconnects and starts another connection.
- Physical Samsung Android 9 smoke used the isolated test package and a
  disposable free account. The real Yandex `AdActivity` rendered, completing
  the reward produced a one-connect grant on both synchronized databases, and
  the VPN reached Android `CONNECTED` and `VALIDATED`. It remained connected
  beyond the previous three-minute cutoff. After manual disconnect, the next
  connect opened another rewarded ad. The test VPN was left disconnected.
- Account deletion now removes ad challenges and grants and records their
  `public_id` tombstones. The disposable smoke account was deleted, two older
  orphan challenge rows and two orphan grant rows were removed from a verified
  backup, and both paid-beta databases converged to zero orphan ad rows.
- Android 0.3.6 recognizes the sanitized ownership-conflict response when the
  same physical phone signs into another account. It rotates only the local
  per-account device identity, retries bootstrap and leaves the original
  account and its subscription unchanged.
- Validation: 102 backend tests, 32 Flutter tests with two intentional skips,
  clean Flutter analysis, 8/8 API manifests, 2/2 static paid-beta manifests,
  8/8 download checks and the independent 31/31 public-surface probe. Primary
  website APK downloads match their exact production/test SHA-256 values.
- External monetization gate: the Yandex Partner app and rewarded block are
  active but the partner profile still requires owner-supplied payout/legal
  details and the application-store URL. Yandex can pause serving or withhold
  payouts until those account requirements are completed.

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

- Both RU control planes run production and paid-beta backend
  `0.9.129-final-audit.5` and pass health, schema, SQLite quick-check and
  explicit bidirectional state synchronization.
- Admin/backend validation: 122 backend unit tests, Python and JavaScript
  syntax, unique HTML ids, desktop/mobile UI, live analytics/pagination/CSV,
  retention controls and CORS.
- Production and candidate sync timers are active. Latest explicit production
  cycles on both nodes: zero inserts/updates, zero conflicts/errors.
- Public site, legal pages, downloads, manifests and all three API surfaces pass
  the independent 31-target probe. Eight API manifests, two static manifests
  and eight artifact download checks match the final release hashes.
- Login/bootstrap/config failover, session persistence, Android background and
  custom per-app routing were physically proven.
- Windows side-by-side install, reboot persistence, VPN/DNS transition,
  competing-VPN restoration, uninstall recovery and clean reinstall were proven.
- Android/Flutter/backend/native tests, analyzer, Android lint, dependency
  audit, release gate and full current/untracked/Git-history secret scan are
  green.
- Final stable artifacts are Android `0.3.7+2026071902` and Windows
  `0.3.6+1808`; candidate artifacts use the same Android build and Windows
  `0.3.6-paid-beta.1808`.
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
   signed successor to the temporary public 0.3.6 release. Until then Windows
   SmartScreen/reputation warnings remain expected.
2. On one owner-controlled Windows PC, approve the UAC prompt for the exact
   public 0.3.6 download and confirm its final desktop/Start-menu launch. All
   autonomous package, MOTW, install/reinstall/uninstall/rollback checks are
   already complete.
3. Raise the SMS.ru production daily limit and perform one positive login-code
   delivery. Negative-path and provider-readiness checks are complete.
4. Supply the Telegram alert bot token and destination chat id, then run one
   delivery smoke. Monitoring itself is active; only this external notification
   channel lacks owner credentials.
5. Complete the Yandex Partner payout/legal profile and add the published app
   store URL before the partner deadline. These fields require the owner's bank,
   identity, tax and store-account data and must not be submitted by automation.

Android and the server-side location pool are published. No confirmed Android,
London or Russian control-plane defect remains.

## Rollback

- Backend 0.9.129 production deployment backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260719T020158Z-timeweb-0.9.129-final-audit.5`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260719T020119Z-ruvds-0.9.129-final-audit.5`.
- Backend 0.9.129 paid-beta deployment backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260719T020213Z-backend-final-audit-20260719-r5`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260719T020132Z-backend-final-audit-20260719-r5`.
- Operational-retention installation backups:
  - Timeweb: `/root/greenvpn-operational-retention-backups/20260719T020204Z`;
  - RUVDS Moscow: `/root/greenvpn-operational-retention-backups/20260719T020123Z`.
- Android 0.3.7 deployment backups:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260719T013304Z-timeweb-0.3.7-2026071902`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260719T013212Z-ruvds-0.3.7-2026071902`.
- Windows 0.3.6 deployment backups after release-state synchronization:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260719T014119Z-timeweb-0.3.6-1808`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260719T014044Z-ruvds-0.3.6-1808`.
- Backend 0.9.124 production deployment backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260718T184055Z-timeweb-0.9.124-admin-cleanup.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260718T184000Z-ruvds-0.9.124-admin-cleanup.1`.
- Backend 0.9.124 paid-beta deployment backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T184108Z-account-delete-complete-20260718-r29`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260718T184022Z-account-delete-complete-20260718-r29`.
- Root-only pre-delete database backups and cleanup manifests:
  - Timeweb: `/root/greenvpn-agent-user-cleanup-backups/20260718T184419Z-timeweb`;
  - RUVDS Moscow: `/root/greenvpn-agent-user-cleanup-backups/20260718T184357Z-ruvds`.
  Database rollback is not sufficient by itself: any intentionally restored
  test identity must receive a controlled peer re-provision before use.
- Android 0.3.6 deployment backups:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260718T170717Z-timeweb-0.3.6-2026071802`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260718T170502Z-ruvds-0.3.6-2026071802`.
- Backend 0.9.123 production deployment backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260718T165718Z-timeweb-0.9.123-ads.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260718T165626Z-ruvds-0.9.123-ads.1`.
- Backend 0.9.123 paid-beta deployment backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T165737Z-paid-beta-backend-ad-min-version-20260718-r28`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260718T165631Z-paid-beta-backend-ad-min-version-20260718-r28`.
- Rewarded-ad environment backups:
  - Timeweb production: `/root/greenvpn-rewarded-ads-backups/20260718T115726Z-production`;
  - Timeweb paid-beta: `/root/greenvpn-rewarded-ads-backups/20260718T113926Z-paid-beta`;
  - RUVDS production: `/root/greenvpn-rewarded-ads-backups/20260718T115711Z-production`;
  - RUVDS paid-beta: `/root/greenvpn-rewarded-ads-backups/20260718T113912Z-paid-beta`.
- Paid-beta static-manifest backups:
  - Timeweb: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120557Z-android-0.3.5-2026071801`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120534Z-android-0.3.5-2026071801`.
- Orphan-ad cleanup backup before the replication-safe cleanup:
  `/root/greenvpn-paid-beta-ad-orphan-cleanup-backups/20260718T122049Z` on Timeweb.

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
