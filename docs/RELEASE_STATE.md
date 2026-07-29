# Green VPN Release State

## Current Release Closure (2026-07-29 MSK)

| Layer | Current state |
|---|---|
| Production backend | `0.9.152-release-ready.1` on Timeweb and RUVDS |
| Published Android | `0.3.19+2026072914`, signed and optional on Timeweb/RUVDS |
| Published Windows | `0.3.19+2914`, physically verified, optional and `NotSigned` |
| Published paid-beta Android | `0.3.19+2026072914`, package `pro.greenvpn.app.beta`, optional |
| Published paid-beta Windows | `0.3.19-paid-beta.1+2914`, optional and `NotSigned` |
| Product contract | permanent Free, guest-first |
| Free enforcement | quota off, rate off; stored policy `3 GB`, one device, `10/20 Mbit/s` |
| Money gates | sales/refunds/tax confirmation/renewal charges off |
| Advertising | Rewarded and forced disconnect off |
| Data plane | 16-route six-stage cascade physically green |
| Legacy foreign API | removed; `8000` closed and HTTP tombstone `410` |

The candidate source anchor is clean commit
`c52ba7d6b3f3cfbda49e63515013ab9a37eaf48a`.
Exact release hashes:

- Android production APK:
  `BCA7CF6A4AB2381A6EB44836726AFC07B460B87F0789BA88DC81CF84CD37F4FB`;
- Android paid-beta APK:
  `99EB6C2D44C955F43441039B5375CEC5AF925D19EDAFEE1D17042FAE6E2ED8A7`;
- Windows installer:
  `6D5E33B0EAB146C9E2EAA78E8B5F6636B9BCBDDC11D387A07C5B71CB6E9894FB`;
- Windows paid-beta installer:
  `E1451CED069941A431B383E74B20B8E938CD2758C99CBD129F45A731AF1B44D1`;
- Windows transport ZIP:
  `F0337840FB021AD4758B420203DAB47A0B52447399DA1AB911AF7B657C1D7D4D`.

The exact production-package Android APK passed upgrade over public `0.3.15`,
launch, real NL1 egress, production API, YouTube and clean disconnect. Exact
paid-beta Android, all 16 routes, Quick Tile, background failover, exact
Windows payload `63/63`, five Windows alternate transports and production
runtime failover also passed. NL2 was updated and rebooted one node at a time;
all services are active and no temporary recovery automation remains.

Both paid-beta env files now carry explicit off values for quota/rate
enforcement, sales, tax confirmation, refunds, renewal charges and all
Rewarded/test gates. A keyed value-blind comparison also proves exact
primary/fallback functional parity for the catalog, release, feature-flag and
owner-action tables in both contours.

Android and Windows production/paid-beta `0.3.19` release artifacts are
published as optional updates through both control planes. Dynamic and static
manifests pass, full body hashes pass `8/8`, public surface passes `31/31`,
both control planes have zero failed units and all four databases pass
`PRAGMA quick_check`.

Android rollback backups:

- Timeweb:
  `/root/greenvpn-apk-release-backups/20260729T094454Z-timeweb-0.3.19-2026072914`;
- RUVDS:
  `/root/greenvpn-apk-release-backups/20260729T094418Z-ruvds-0.3.19-2026072914`.

Windows rollback backups:

- Timeweb:
  `/root/greenvpn-windows-release-backups/20260729T145410Z-timeweb-0.3.19-2914`;
- RUVDS:
  `/root/greenvpn-windows-release-backups/20260729T145347Z-ruvds-0.3.19-2914`.

Windows `0.3.19` was published by explicit owner instruction with the
SmartScreen/reputation risk accepted. The exact production and paid-beta
installers remain `NotSigned`; no false trusted-signature metadata was
published. Authenticode remains a future trust improvement for a
higher-version successor. Paid sales remain closed until the owner resolves
the legal/tax/KYC receipt process. See
`FULL_PROJECT_CLOSURE_2026_07_29_RU.md`.

All sections below are historical snapshots and are not current instructions.

## Historical Launch Closure (2026-07-28 19:15 MSK)

Production and paid-beta backend `0.9.148-owner-boundary.1` are active on both
control planes. The protected owner packet reports exactly one owner blocker:
`windows_trust`. Rewarded advertising, forced disconnect, hard expiry,
production renewal execution and paid-beta quota enforcement remain disabled.

The one external action is to obtain an Authenticode code-signing certificate
with its private key. A Windows 10/11 operating-system license does not sign
applications. Windows SDK `signtool.exe` is already present; the current
preflight finds no valid local Code Signing EKU certificate.

The remaining engineering chain is prepared:

1. `finalize_windows_trusted_release.ps1` selects the valid certificate,
   signs owned payload binaries before compression, signs the bootstrap and
   signs the final installer after all resource changes.
2. Each stage is publisher-, timestamp-, Authenticode- and SHA-256-verified
   with JSON evidence.
3. The server publication script accepts evidence for production and paid-beta,
   rejects hash/identity mismatches and sets trusted readiness metadata only
   for a proven signed pair.
4. After the certificate is available, Codex performs reversible paid-beta and
   production physical smoke, atomic dual-control-plane publication, download
   verification and rollback verification. No additional owner input is
   planned.

Closure evidence also resolves the previous operational gaps:

- exact Android `0.3.15+2026072704` passed Android 16/API 36 install, cold
  launch, production VPN/egress/API/YouTube and clean disconnect;
- production and paid-beta catalogs have matching managed/public summaries;
- NL2 certificate synchronization is active, current and not due to expire
  until 2026-10-09;
- guarded retention reduced RUVDS disk use to 77% and Timeweb to 46%;
- real SMTP alert delivery passed in both contours.

## Current Transport Cascade Release (2026-07-28 MSK)

Production backend `0.9.148-owner-boundary.1`, catalog
`2026-07-28-public-transport-v1`, Android
`0.3.15+2026072704` and Windows `0.3.17+2608` are published through Timeweb
and RUVDS. Both platform updates are optional. Rewarded advertising and forced
disconnect remain disabled.

| Artifact | SHA-256 | Status |
|---|---|---|
| Android stable `pro.greenvpn.app` | `72C4672355722EB4111EAA36BC6794EB71F9E20F3DB6818093489B8A59F48288` | signed, exact release physically connected/disconnected, published on both sites |
| Android paid-beta `pro.greenvpn.app.rc` | `B12BEC69AA0F0C04F17C7E536C97AD8EA3F88FA38BD9BA8FBAFAA070033572D4` | signed, optional, published on both sites |
| Windows stable | `518A6BD61CBFD1C46B7460439963D2D6D48448BF2A7B14A1397D192D335934C4` | unsigned, optional, exact installer installed and runtime-failover checked, published on both sites |
| Windows paid-beta | `21CDE69380BB288A63E1D5BC56A7715A95B3DBF664B93EBE4E3002D65C987AC3` | unsigned, optional, published on both sites |

The public-product catalog on both control planes contains 16 routes:
3 WireGuard UDP, 3 AmneziaWG, 3 Hysteria2, 3 VLESS REALITY, 3 Naive HTTPS and
1 dnstt. The strict order is
`wireguard_udp -> amneziawg -> hysteria2 -> vless_reality -> naive_https -> dnstt`.
Every failed route must reach a clean VPN-down state before the next candidate;
failure to prove cleanup stops the cascade.

Physical Android checks passed all 16 routes and an injected
`amneziawg -> hysteria2` runtime recovery without overlapping engines. A
separate Quick Settings test passed all six protocol groups in the same order,
restored WireGuard after clearing cooldown and finished with zero residual VPN
records/processes. Exact stable APK UI connect, production traffic and clean
disconnect also passed. The phone was left with only stable `0.3.15` installed
and no active VPN.

The exact stable Windows installer was executed and its 63 critical payload
files were matched to bytes extracted from the same EXE. The full tunnel
survived app exit, the runtime monitor restored, and an injected active
WireGuard service failure recovered from `current_wg0` to
`ruvds-2584554-ld8`. Egress and network protection were verified, no transport
overlap occurred, all Green VPN components stopped during cleanup, the owner's
Amnezia tunnel and original egress were restored, and the temporary failsafe
was removed.

Eight dynamic manifests, two static manifests, all eight downloaded artifact
hashes and public surface `31/31` passed. Backend `162/162`, Flutter, Android
native tests/lint, release gate and complete secret scan passed.
The manifest verifier now uses the exact current release defaults and exits
nonzero on a mismatch; the body-hash verifier supports named partial retries
and cannot mask a download failure with temporary-directory cleanup.

Rewarded advertising, forced disconnect, production renewal execution and hard
expiry enforcement remain disabled. A pre-existing guarded Timeweb paid-beta
renewal timer remains enabled every 15 minutes; all 327 runs audited through
2026-07-28 17:00 MSK reported `executed=0`. RUVDS has no renewal timer. The
Windows rollout changed no payment, OTP, account, renewal or advertising state.

Known release gaps:

1. Windows installers are unsigned and may trigger SmartScreen/reputation
   warnings.
2. dnstt has one node and remains a low-throughput last resort.
3. The release branch is ahead of origin with a large mixed working tree and
   is not yet a clean reproducible release anchor. Legacy build/smoke scripts
   still contain dated default versions and need explicit-parameter guards or
   archival classification.
4. Lower sections of this append-only document are historical snapshots even
   where their original headings say `Current`; only the first section and
   `CURRENT_HANDOFF.md` are authoritative for present state.

## Current Production 0.3.14 Android Closure (2026-07-27)

Production backend `0.9.141-autorenew-optin.1` and mandatory Android
`0.3.14+2026072702` are active on Timeweb Moscow and RUVDS Moscow. Missing
`autoRenew` is fail-safe `false`; explicit `true` remains supported. Timeweb is
still the only billing writer. No existing subscription, order or saved
payment-method state was modified.

| Artifact | Identity | SHA-256 | Status |
|---|---|---|---|
| Android stable | `0.3.14+2026072702`, `pro.greenvpn.app`, 76760042 bytes | `FE7BF607CA5D37E85C6BB6AC569AD0DBF9DE5C42C73337DDCC54A161877D99EE` | signed, mandatory, published on both sites, physically checked |
| Android paid-beta | `0.3.14+2026072702`, `pro.greenvpn.app.rc`, 76760194 bytes | `FA1F8EC851D5F0EDC92C27EF0DCB945CB036CEF56762D173CB39AD9E7E611232` | signed, optional, published on both sites |
| Windows stable | `0.3.13+2604` | `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30` | mandatory, physically checked, still `NotSigned` |

Android stable passed guest-first launch, the `249/649/1099` RUB tariff set,
auto-renew off by default, standalone email restore, connect, real traffic and
clean disconnect. Physical download reached `30.176` Mbit/s. The phone was
left disconnected with stable `0.3.14` installed and app data preserved.

Windows `0.3.13` passed production provisioning, a fresh VPN handshake,
traffic, DNS/no-leak probes and clean disconnect. The independent owner
Amnezia tunnel service was restored to `Running`, and the temporary failsafe
task was removed. Evidence:
`C:\BlueVPN_Builds\windows_0.3.13_final_smoke_20260727\production-network-transition-report.json`.

Validation passed: backend `148/148`; exact-byte verification for all four
Android URLs; eight dynamic and two static manifests; eight download
endpoints; public surface `31/31`; external readiness
`12 green / 0 yellow / 0 red`; strict release gate
`0 warnings / 0 errors`. Both control-plane services, sync, probes and
retention are healthy.

Paid-beta keeps free access enabled with quota enforcement off, stored
`3` GB limit, one-device policy and `10` Mbit/s profile. London, NL1 and NL2
usage reporters have active timers and last result `success`; both databases
agree on `21` rows, `rx=17136`, `tx=38932`. Quota-exhaustion blocking has not
been enabled or physically exercised.

Rewarded ads, forced disconnect, automatic renewal charges and hard expiry
enforcement remain disabled. The three current expiry warnings are unreviewed
guest Trial rows without verified retention email; there are no
expired-active rows.

Windows rollback readiness is now green. Previous production installer
`0.3.12`, SHA-256
`79F5E201F8F798906C9A7FF5F837B9C5AD08B4890DEB3DF0B7F3F2E3C4EC0FE7`,
is published as a dedicated rollback through both mirrors; protected update
readiness reports `productionReady=true`, `rollbackReady=true` and no
rollback blockers/warnings on both nodes. Public launch closure now has one
critical Windows distribution blocker: code signing/trust. Telegram alerts
need owner-provided credentials; monitoring itself is green.

Rollback:

- Backend, RUVDS:
  `/root/greenvpn-public-product-backups/20260727T044740Z-ruvds-0.9.141-autorenew-optin.1`;
- Backend, Timeweb:
  `/root/greenvpn-public-product-backups/20260727T044850Z-timeweb-0.9.141-autorenew-optin.1`;
- Android, RUVDS:
  `/root/greenvpn-apk-release-backups/20260727T045823Z-ruvds-0.3.14-2026072702`;
- Android, Timeweb:
  `/root/greenvpn-apk-release-backups/20260727T050009Z-timeweb-0.3.14-2026072702`.
- Windows rollback config, RUVDS:
  `/root/greenvpn-release-rollback-backups/20260727T052740Z-ruvds-production-windows-0.3.12`;
- Windows rollback config, Timeweb:
  `/root/greenvpn-release-rollback-backups/20260727T052815Z-timeweb-production-windows-0.3.12`.

## Android No-Charge Checkout Smoke And Auto-Renew Opt-In (2026-07-27)

The owner approved Android-only work and explicitly excluded Windows from this
checkpoint. Windows processes, services, installation and network state were
not changed.

The installed side-by-side RC is Android `0.3.14+2026072701`, package
`pro.greenvpn.app.rc`. Its signed APK is
`C:\BlueVPN_Builds\android_autorenew_optin_20260727\GreenVPN_Android_0.3.14_2026072701.apk`,
size `76760190`, SHA-256
`92B97AB029373348B7FDC963AB759C6D603FE8F45E7F22CA2DF9EC6B1C3EDE7D`.
It is installed only on the owner Android device and is not published as a
production update. Production Android remains `0.3.13+2026072604`, package
`pro.greenvpn.app`.

A clean physical RC launch created a free guest and opened the product without
a login gate. The fixed 249/649/1099 RUB terms were visible. For a new guest,
the auto-renew switch is now off by default. Tapping `Оплатить 249 ₽ за 1
месяц` opened the dedicated `Email для оплаты` gate with `Получить код`; no
email was entered, no OTP was sent, no YooKassa page or order was created, no
charge was approved and no VPN connection was started. Logcat contained no
fatal crash or ANR.

The defensive server default was changed from auto-renew on to explicit opt-in.
The deployed paid-beta backend is `0.9.141-autorenew-optin.1`, release
`paid-beta-backend-autorenew-optin-20260727-r1`, on both Timeweb and RUVDS.
The live/backend source comparison contained only the four intended default
changes. Production backend was not changed. Rollback:

- Timeweb:
  `/root/greenvpn-paid-beta-backend-backups/20260727T035234Z-paid-beta-backend-autorenew-optin-20260727-r1`;
- RUVDS:
  `/root/greenvpn-paid-beta-backend-backups/20260727T035243Z-paid-beta-backend-autorenew-optin-20260727-r1`.

Validation: backend tests `148/148`; Flutter tests `58 passed / 6 platform
skips`; Flutter analysis has no issues; `git diff --check` passed. Both
paid-beta services and sync timers are active, both databases pass
`PRAGMA quick_check`, manual synchronization succeeds and the public primary
and fallback paid-beta health endpoints report `ok=true`. All guests and peers
created by this physical smoke were removed from both synchronized databases;
the RC was left stopped with cleared local data.

The existing production subscription was not modified: both production
databases still contain one active `green_30d` subscription through
`2026-08-24T23:13:22.297175+00:00`, `auto_renew=1` and exactly one activated
249 RUB order. The production Android app currently opens as a local guest, so
restoring the existing account requires `Войти по email`; it does not require
or justify another payment.

## Owner Account Restore And Site Copy Check (2026-07-26)

The owner completed the real standalone email-code sign-in on production
Windows `0.3.13`. Both control-plane databases contain the same successful
`checkout_email_verify` event for Windows `0.3.13` and the same target account.
The local Windows log records `session persisted after auth` followed by
`GET /api/v1/subscription/me status=200`.

The target account is email-verified and has active `green_30d` access through
`2026-08-24T23:13:22.297175+00:00`, five allowed devices and `auto_renew=1`.
Android `0.3.13` physically shows
`Текущий: Green VPN — 1 месяц`; the Android and Windows events resolve to the
same backend account. No new billing order was created during restore: the
account still has one existing activated 249 RUB order and
`orders_last_6h=0`. No Windows config/connect operation was performed, so the
Windows device row will be created on first provisioning rather than by this
sign-in-only check. VPN routes were not changed.

The sentence beginning `Попробуйте Green VPN бесплатно 3 дня` was removed
entirely from the main site. Exact `index.html` SHA-256
`AF112FD5C5EE9DD58CBD509DE4E15EE6A949CB12D01CEBFD8E4BB7906C07B9B0`
is installed on Timeweb and RUVDS. Public `https://greenvpn.pro/` returns 200,
contains both download actions and contains neither the removed copy nor an
intermediate replacement. Rollback:

- RUVDS: `/root/greenvpn-main-site-backups/20260726T065207Z`;
- Timeweb: `/root/greenvpn-main-site-backups/20260726T065359Z`.

## RUVDS Storage Incident Resolved (2026-07-26)

RUVDS reached 97% root-filesystem use, 95-99% I/O wait and load 23-27 because
full SQLite snapshots were running every 30 seconds for production and every
10 seconds for paid-beta while dozens of full release/database rollbacks had
accumulated. Retention also kept high-volume probe observations for 21 days
and ended every pass with a full `PRAGMA quick_check`.

The incident was resolved without rebooting either host, restarting a backend,
changing a VPN route or touching payment/account business records:

- sync/probe/retention work was isolated before cleanup;
- 42 superseded RUVDS rollback directories were removed after an exact dry
  run while the current and previous release rollback were retained; the
  removal manifest is
  `/root/greenvpn-storage-remediation-20260726T1023Z/removed-paths.txt`;
- automatic release-backup retention now keeps at most four directories in
  each allowlisted high-volume backup root on both nodes;
- probe observations now have seven-day retention plus hard limits of
  `30000/12000/30000` rows; normal retention no longer performs a full
  database scan and runs four times daily;
- production and paid-beta sync share one local outgoing mutex, wait in a
  queue rather than overlap, and have a five-minute systemd timeout;
- calendar sync is staggered in UTC: Timeweb production at
  `:00/:10/:20/:30/:40/:50` and paid-beta at `:02/:32`; RUVDS production at
  `:05/:15/:25/:35/:45/:55` and paid-beta at `:17/:47`.

Consistent pre-vacuum gzip snapshots are retained under
`/root/greenvpn-storage-remediation-20260726T1023Z` on each node. Controlled
vacuum reduced Timeweb databases from 236.8/158.6 MB to 99.4/70.9 MB and
RUVDS databases from 72.9/149.1 MB to 67.6/68.8 MB. All four databases passed
`PRAGMA quick_check`; four manual directional syncs completed with zero
conflicts/errors; RUVDS production and paid-beta probes completed
successfully. Root storage is now 53% used with about 18 GB free on Timeweb
and 67% used with about 6.3 GB free on RUVDS. Local health is HTTP 200 at
about 3 ms and steady-state RUVDS I/O wait returned to 0%.

The first calendar cycles also passed: Timeweb production
`08:00:00-08:00:25 UTC`, Timeweb paid-beta `08:02:00-08:02:27 UTC` and
RUVDS production `08:05:01-08:05:39 UTC`, all with zero conflicts/errors.
The post-incident external public-surface probe passed `31/31`; primary and
fallback APIs, sites, manifests and exact public downloads all returned 200.

Final sync-safety rollback:

- Timeweb:
  `/root/greenvpn-db-sync-safety-backups/20260726T075834Z`;
- RUVDS:
  `/root/greenvpn-db-sync-safety-backups/20260726T075840Z`.

## Current Production Account Restore 0.3.13 (2026-07-26)

The owner explicitly approved installation and publication on Android,
Windows and both production sites. Production backend
`0.9.140-account-restore.1` and mandatory `0.3.13` clients are active on
Timeweb Moscow and RUVDS Moscow. Timeweb remains the only billing writer.
Rewarded ads and the forced disconnect timer remain disabled.

| Artifact | Identity | SHA-256 | Status |
|---|---|---|---|
| Android | `0.3.13+2026072604`, `pro.greenvpn.app`, `Green VPN` | `C296936053773BFCF8F8BB9E9A1CD2267A669832FCD451112F9DC4429B8C1629` | signed, mandatory, installed and physically checked |
| Windows | `0.3.13+2604` | `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30` | `NotSigned`, mandatory, installed and physically checked |

The exact Android artifact was updated in place on the owner phone. Home,
Tariff and the standalone account-restore dialog were checked; the phone was
left disconnected and the app was stopped. The exact Windows installer was
installed over stable, registry and file versions report `0.3.13`, and
`GreenVPNService` plus `WireGuardManager` are automatic and running. The
standalone `Уже есть подписка? / Войти по email` action is visible and is
separate from checkout. Green VPN remained disconnected; the owner's
independent `pc_valentine` WireGuard route was preserved unchanged.

Both production contours publish Android and Windows with `required=true`.
Both isolated paid-beta contours retain the `.rc` Android package and exact
test artifacts with `required=false`. The production backend exposes
`/api/v1/auth/access/email/start` and
`/api/v1/auth/access/email/verify`; no email, OTP, order or payment action was
performed during deployment.

External verification passed: eight API manifests, two static manifests and
eight download HEAD checks (`18/18`); complete Android and Windows downloads
from both public sites match the exact production hashes; public-surface probe
`31/31`; production and paid-beta database `quick_check=ok`; manual
synchronization succeeds on both nodes; release-row digests match; services
are active with zero failed units.

Production rollback:

- Backend, RUVDS Moscow:
  `/root/greenvpn-public-product-backups/20260726T010132Z-ruvds-0.9.140-account-restore.1`;
- Backend, Timeweb Moscow:
  `/root/greenvpn-public-product-backups/20260726T010847Z-timeweb-0.9.140-account-restore.1`;
- Android, RUVDS Moscow:
  `/root/greenvpn-apk-release-backups/20260726T010937Z-ruvds-0.3.13-2026072604`;
- Android, Timeweb Moscow:
  `/root/greenvpn-apk-release-backups/20260726T012414Z-timeweb-0.3.13-2026072604`;
- Windows, RUVDS Moscow:
  `/root/greenvpn-windows-release-backups/20260726T011630Z-ruvds-0.3.13-2604`;
- Windows, Timeweb Moscow:
  `/root/greenvpn-windows-release-backups/20260726T012434Z-timeweb-0.3.13-2604`.

Operational-retention snapshots are
`/root/greenvpn-operational-retention-backups/20260726T010307Z` on RUVDS and
`/root/greenvpn-operational-retention-backups/20260726T010854Z` on Timeweb.
The subsequent owner check confirmed restoration on Android and Windows
without a new YooKassa order. Remaining owner-only product work is the exact
Windows provisioning/connect-disconnect transition. The unsigned Windows
installer remains the principal distribution trust risk.

## Previous Isolated Paid-Beta Account Restore 0.3.13 (2026-07-26)

This is the pre-promotion checkpoint. Production remained mandatory `0.3.12`
at that time; this candidate was published only
through both isolated paid-beta control planes with `required=false`.
Rewarded ads and the forced disconnect timer remain disabled.

The authentication and billing journeys are now separate:

- first launch creates or refreshes a guest without forcing email;
- `Войти по email` restores an existing account/subscription and never creates
  a billing order or opens YooKassa;
- `Оплатить` is only for buying a new subscription and asks for a verified
  email before checkout;
- an expired guest is refreshed as a guest, while an expired account session
  asks the user to sign in again.

Paid-beta backend `0.9.140-account-restore.1`, release
`paid-beta-backend-account-restore-20260726-r2`, is active on Timeweb and
RUVDS Moscow. It exposes dedicated
`/api/v1/auth/access/email/start` and
`/api/v1/auth/access/email/verify` endpoints. The backend archive SHA-256 is
`BF0854C3BEC78853B5C52120106EA9875620BB34394D92B7A77913AACDE19384`.

| Artifact | Identity | SHA-256 | Status |
|---|---|---|---|
| Android | `0.3.13+2026072604`, `pro.greenvpn.app.rc`, `Green VPN` | `82772195710B468E0CF45B468D0AB36B95365A8C8541B47098951B44413BBEBA` | signed, physically checked |
| Windows | `0.3.13+2604` | `6E4A33C902FE47FD9B14173B12426F25C9F1F601D6CA94321EDC883D5EF0A507` | `NotSigned`, exact public bytes checked |

Verification: Flutter analyze has no issues; Flutter tests
`57 passed / 6 platform skips`; backend tests `86/86`; Python compile and
`git diff --check` passed; the final local release gate reports
`0 errors / 0 warnings`. Both paid-beta manifests and full primary/fallback
downloads match the exact sizes and hashes. Both databases pass
`PRAGMA quick_check`; manual synchronization succeeds without conflicts; all
services and timers are active; the public-surface probe passes `31/31`.

The exact Android b2604 APK was installed side by side on the owner device.
Home shows `Бесплатный`, Tariff shows `Бесплатный тариф` and all
249/649/1099 RUB options, Settings shows the guest profile, and all three
surfaces provide an independent existing-subscription sign-in action. The
restore dialog says `Войти в аккаунт`, requests the subscription email and
contains no payment or receipt wording. The phone was left disconnected.

The Windows installer was not installed over stable `0.3.12`: the owner PC
currently has an active `pc_valentine` WireGuard tunnel, and replacing the
shared single-instance application/service could interrupt that route.
Portable launch correctly refused a second instance and raised the already
running stable process, so it is not evidence of b2604 UI behavior. No Windows
route, adapter or service state was changed.

Rollback:

- Backend, Timeweb:
  `/root/greenvpn-paid-beta-backend-backups/20260725T235341Z-paid-beta-backend-account-restore-20260726-r2`;
- Backend, RUVDS:
  `/root/greenvpn-paid-beta-backend-backups/20260725T235423Z-paid-beta-backend-account-restore-20260726-r2`;
- Client, Timeweb:
  `/root/greenvpn-paid-beta-client-release-backups/20260726T002604Z-timeweb-0.3.13-0.3.13`;
- Client, RUVDS:
  `/root/greenvpn-paid-beta-client-release-backups/20260726T002627Z-ruvds-0.3.13-0.3.13`.

Remaining owner-only gates are: enter the real purchase email and OTP in the
standalone sign-in dialog, verify that the paid entitlement appears without a
new order/YooKassa page, repeat that entitlement check on the second platform,
and perform the exact Windows installation/UI smoke during an explicitly
approved VPN interruption window. Production promotion still requires a new
separate owner approval.

## Previous Production Guest-First 0.3.12 (2026-07-26)

The owner explicitly approved production publication. Both control planes now
serve the mandatory stable artifacts below, and production backend
`0.9.139-guest-first.1` implements automatic guest start with email required
only before payment or account recovery.

| Artifact | Identity | SHA-256 | Status |
|---|---|---|---|
| Android | `0.3.12+2026072506`, `pro.greenvpn.app`, `Green VPN` | `6FEBDE9FDBC6E2624FC57F8C18459B432A4F54D3A73A7CC18CB1302777CFCC33` | signed, mandatory |
| Windows | `0.3.12+2506` | `79F5E201F8F798906C9A7FF5F837B9C5AD08B4890DEB3DF0B7F3F2E3C4EC0FE7` | `NotSigned`, mandatory |

The public bootstrap uses `guest` as primary and `email_code` as fallback,
exposes only `guest`, `email_code` and `email_password`, and contains no phone
method. Timeweb remains the only billing writer. The main site, static privacy
page, backend privacy page and fallback landing agree on guest-first behavior,
the 249/649/1099 RUB tariffs and payment-time email confirmation. Rewarded ads
and the forced disconnect timer remain disabled on both contours and nodes.

The exact stable Android APK passed a physical smoke on the owner device:
automatic guest start, tariff selector, payment-time email gate, Android VPN
permission, connected and validated real tunnel, public API reachability and
clean disconnect. The phone was left disconnected.

The exact stable Windows installer replaced the prior paid-beta payload.
Registry/application identity is `0.3.12+2506`, installed payload hashes match,
`GreenVPNService` is automatic and running, and the application process
launches and responds. Browser-based desktop capture failed in the automation
layer, and a Windows tunnel transition was not performed because it would
change the owner's active network. The unsigned installer remains a release
risk and this is not a complete Windows tunnel smoke.

Checks after publication: backend `144/144`; final local release gate
`0 errors / 0 warnings`; eight API manifests; two static paid-beta manifests;
eight download checks; exact full-byte primary/fallback production downloads;
public-surface probe `31/31`; both production databases `quick_check=ok` with
`26` users and subscriptions; both paid-beta databases `quick_check=ok` with
`5` users; manual two-way sync successful; services and timers active; zero
fresh backend warnings.

Rollback:

- Backend, RUVDS Moscow:
  `/root/greenvpn-public-product-backups/20260725T223750Z-ruvds-0.9.139-guest-first.1`;
- Backend, Timeweb Moscow:
  `/root/greenvpn-public-product-backups/20260725T224049Z-timeweb-0.9.139-guest-first.1`;
- Main site, RUVDS Moscow:
  `/root/greenvpn-main-site-backups/20260725T223241Z`;
- Main site, Timeweb Moscow:
  `/root/greenvpn-main-site-backups/20260725T223437Z`;
- Android, RUVDS Moscow:
  `/root/greenvpn-apk-release-backups/20260725T221755Z-ruvds-0.3.12-2026072506`;
- Android, Timeweb Moscow:
  `/root/greenvpn-apk-release-backups/20260725T222248Z-timeweb-0.3.12-2026072506`;
- Windows, RUVDS Moscow:
  `/root/greenvpn-windows-release-backups/20260725T222005Z-ruvds-0.3.12-2506`;
- Windows, Timeweb Moscow:
  `/root/greenvpn-windows-release-backups/20260725T222307Z-timeweb-0.3.12-2506`.

The Android publication script defect discovered during rollout is fixed:
paid-beta no longer inherits mandatory-update state or the obsolete
`pro.greenvpn.app.beta` identity. It now defaults paid-beta to
`required=false`, uses `pro.greenvpn.app.rc`, verifies the result and allows a
90-second backend health window.

## Previous Isolated Paid-Beta Guest-First 0.3.12 (2026-07-25)

The exact `0.3.12` client artifacts are published through both isolated
paid-beta control planes with `required=false`. They remain separate from the
mandatory stable artifacts and use the `.rc` Android package identity.

| Artifact | Identity | SHA-256 | Status |
|---|---|---|---|
| Android | `0.3.12+2026072506`, `pro.greenvpn.app.rc`, `Green VPN` | `B3EFBB0ECEC7108993BE2776B23CAEF013F62952E5BCA7761DBA34F1671801DA` | signed, verified |
| Windows | `0.3.12+2506` | `F8AE5B1439D21BF2B3EE0EF39843FA54501AF50DEC6F3D4CFD016D04824F2BC8` | `NotSigned` |

The matching source removes phone/SMS login from public surfaces, creates a
guest session on first launch and requires a verified email before billing.
Existing email recovery also transfers the current device away from the
temporary guest. The server refuses billing for guests and unverified users.

Checks: Flutter analyze passed; Flutter `52 passed / 6 platform skips`;
backend `85/85`; local release gate `0 errors / 0 warnings`; Android signature,
Hysteria2 and dnstt artifact verification passed.

Both API manifests and both static manifests match the identities and hashes
above, with `isolated=true`, `productionPublished=false`, `fileReady=true` and
`required=false`. Full downloads through both public ingress routes are
byte-identical to the expected artifacts. The public-surface probe passes
`31/31`.

The exact public Android APK passed a clean-install physical smoke after all
five older Green VPN packages were removed. First launch created a guest and
opened the main VPN screen without email or visible `Beta`; the 249/649/1099
RUB tariffs and payment-time email gate are present. Android VPN permission,
validated tunnel, API reachability and clean disconnect passed. Only
`pro.greenvpn.app.rc` version `0.3.12` remains installed and the phone is
disconnected.

The old Windows `0.3.6` installation was removed and the exact public `0.3.12`
installer was installed. Registry version is `0.3.12`, executable version is
`0.3.12+2506`, the service is automatic and running, and first launch opens the
guest VPN screen without email or visible `Beta`. Windows tunnel testing
remains owner-only because it changes the owner's network. The installer is
unsigned.

The matching paid-beta backend is `0.9.136-guest-first.1`, release
`paid-beta-backend-guest-first-20260725-r1`, on both control planes. Public
paid-beta bootstrap uses `guest` as primary and exposes `guest`, `email_code`
and `email_password`, with no phone method. Both services and sync timers are
active, both databases pass `PRAGMA quick_check`, the temporary guest smoke
account was removed and synchronized, and the public-surface probe passes
`31/31`.

Rollback:

- Backend, RUVDS Moscow:
  `/root/greenvpn-paid-beta-backend-backups/20260725T201136Z-paid-beta-backend-guest-first-20260725-r1`;
- Backend, Timeweb Moscow:
  `/root/greenvpn-paid-beta-backend-backups/20260725T201321Z-paid-beta-backend-guest-first-20260725-r1`.
- Client, RUVDS Moscow:
  `/root/greenvpn-paid-beta-client-release-backups/20260725T203532Z-ruvds-0.3.12-0.3.12`;
- Client, Timeweb Moscow:
  `/root/greenvpn-paid-beta-client-release-backups/20260725T203648Z-timeweb-0.3.12-0.3.12`.

Remaining paid-beta-only gates: owner-driven real email-code delivery from the
payment gate and a Windows VPN/network transition. Production promotion was
separately approved and completed on 2026-07-26.

Updated: 2026-07-26.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.140-account-restore.1` |
| Fallback API | RUVDS Moscow, backend `0.9.140-account-restore.1` |
| Android | `0.3.13+2026072604`, package `pro.greenvpn.app`, mandatory |
| Android SHA-256 | `C296936053773BFCF8F8BB9E9A1CD2267A669832FCD451112F9DC4429B8C1629` |
| Windows | `0.3.13+2604`, mandatory, unsigned |
| Windows SHA-256 | `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30` |
| Ads/session timer | all rewarded ads temporarily disabled in production and paid-beta; forced disconnect timer disabled |

Android and Windows 0.3.13 are published on Timeweb and RUVDS Moscow. Both
stable manifests have `required=true` and `fileReady=true`; previous artifacts
are retained in the root-only deployment backups listed above.

## Superseded Isolated Paid-Beta 0.3.11, 2026-07-25

| Surface | Current paid-beta state |
|---|---|
| Backend | `0.9.136-guest-first.1` on Timeweb and RUVDS Moscow |
| Android | `0.3.11+2026072505`, `pro.greenvpn.app.rc`, label `Green VPN` |
| Android SHA-256 | `04F82EFA95B1D5F2D12BD81EC8B77204C79B674EDBAA0E4FA990F7AEC184BFCE` |
| Windows | `0.3.11+2505`, unsigned, installed locally as `Green VPN` |
| Windows SHA-256 | `A416F9E6C7DDD8BC9A22289344CD9F756A0F7B570A8ADDA4B83D34F99F55859F` |
| Authentication | guest-first backend active; email code/password recovery; no public phone/SMS routes |
| Free mode | traffic cap disabled for launch preparation; server rate floor at least 10 Mbit/s |
| Ads | disabled |
| Production | unchanged |

The exact Android artifact passed a physical owner-device smoke including
email-code delivery, temporary password login, free entitlement, all three
tariffs, Android VPN permission, validated tunnel, API reachability and clean
disconnect. The temporary user and peer were removed. The exact Windows
installer is installed, its service is running automatically and its
authentication screen has no visible `Beta`; Windows tunnel testing remains
outside automation because it would change the owner's network.

Both primary/fallback API manifests and static manifests match the exact
artifacts. Full downloads through both public ingress routes match their
SHA-256 values, all public manifest/download checks pass, both databases pass
`PRAGMA quick_check`, both sync timers are active, recent service error logs
are empty, and the public-surface probe passes 31/31.

Rollback:

- RUVDS:
  `/root/greenvpn-paid-beta-client-release-backups/20260725T191930Z-ruvds-0.3.11-0.3.11`;
- Timeweb:
  `/root/greenvpn-paid-beta-client-release-backups/20260725T192136Z-timeweb-0.3.11-0.3.11`.

## Rewarded Ads Temporarily Disabled, 2026-07-22

- By explicit owner instruction, advertising inside Green VPN is disabled for
  now. This is a server-side runtime change; the published Android and Windows
  artifacts and their mandatory update manifests are unchanged.
- On Timeweb Moscow and RUVDS Moscow, both production and paid-beta have the
  master ad gate disabled and an empty platform allow-list. Android Rewarded is
  disabled everywhere; web Rewarded and the closed Windows `test_web` provider
  are disabled in paid-beta. The forced disconnect timer remains disabled.
- All four service process environments match their root-only env files. Both
  production and paid-beta public health routes are green, all databases pass
  `PRAGMA quick_check`, database sync timers are active, recent service error
  logs are empty, and the public-surface probe passes 31/31.
- Rollback directories for this runtime-only change are recorded in
  `CURRENT_HANDOFF.md`. Re-enable no advertising flag without a new explicit
  owner instruction and a fresh isolated beta verification.

## Freemium And Windows Rewarded Beta, 2026-07-19

- Production clients remain Android `0.3.7` and Windows `0.3.6`. The production
  backend is `0.9.129-site-quality.1`, a site-only revision based on the prior
  production source. Its current runtime rewarded-ad allow-list is empty and
  no test advertising path is enabled in production.
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
- Paid-beta retains the implemented ad-gate contract for future testing, but
  the runtime gate and platform allow-list are currently disabled. Android
  Rewarded and Windows `test_web` are both off. Production continues to reject
  `test_web` by code and configuration, and the forced disconnect timer is off.
- The final deployment corrected the beta test flag contract: the deploy script
  and backend share `GREENVPN_FREE_AD_TEST_WEB_ENABLED`, while the backend keeps
  the former key as a read-only compatibility fallback. The running process
  environments on both nodes now report the canonical flag disabled.
- The current Windows beta session belongs to an active paid 249 RUB plan, so
  its live bootstrap correctly bypasses ads and leaves social-only routing
  available. Free-user denial, provider selection, reward completion and
  one-connect consumption are covered by the 130-test backend suite and 46
  Flutter tests; no disposable live account was created.
- Yandex rejected site `api.greenvpn.pro` (id `19615469`) for site
  quality/content and advised improving unique content, navigation and working
  controls. The earliest permitted resubmission is 2026-08-18 12:55 MSK. A
  follow-up confirmed that a compliant new site may be added and that Rewarded
  has no minimum traffic threshold. Yandex promised a separate answer within
  24 hours on whether Windows WebView2 visits count as site traffic. Production
  promotion still requires `greenvpn.pro` moderation, a real `R-A-N-N` block id
  and a real beta callback smoke; local or fake reward completion is forbidden.
- One matching public defect was fixed in `0.9.129-site-quality.1`: the API
  landing Android control returned 404. It now uses `/download/android`, shows
  matching Windows and Android download cards, and states accurately that the
  no-ad benefit belongs to paid subscriptions. Both nodes passed guarded deploy,
  SQLite quick-check and browser inspection; the public-surface probe is 31/31.
  Production `main.py` SHA-256:
  `A811BF8450E5DC003FEFA4BDF1FBF583EC1B1DF591C21699FC37A03ACCD26E7A`.
- Rewarded-provider inquiries are pending with MediaToday, Monetag, ayeT
  Studios, AppLixir and Adsterra. Selection priority is Yandex, then MediaToday
  for direct RUB payout, Monetag for confirmed non-Telegram Rewarded plus
  WebMoney/USDT, ayeT for its stronger S2S-capable web SDK if Russian payout is
  available, AppLixir after its audience threshold, and Adsterra only with an
  explicit approved incentivized format. Google is not a viable Russian payout
  fallback.
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

- Production services on both Russian control planes run
  `0.9.129-site-quality.1`; paid-beta services run `0.9.131-freemium.2`. All
  four health endpoints are green, all databases pass `PRAGMA quick_check`,
  and explicit production and paid-beta sync cycles converge without conflicts
  or errors.
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
| Production backend | `0.9.129-site-quality.1` on Timeweb and RUVDS Moscow |
| Backend SHA-256 | `A811BF8450E5DC003FEFA4BDF1FBF583EC1B1DF591C21699FC37A03ACCD26E7A` |
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
| Ads/session timer | rewarded ads and closed `test_web` temporarily disabled; timer disabled |

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
  `0.9.140-account-restore.1`; health, schema, SQLite quick-check
  and explicit bidirectional state synchronization pass.
- Current backend validation: 144 backend unit tests, Python and JavaScript
  syntax, unique HTML ids, desktop/mobile UI, live analytics/pagination/CSV,
  retention controls and CORS.
- Production and candidate sync timers are active. Latest explicit production
  cycles on both nodes: zero inserts/updates, zero conflicts/errors.
- Public site, legal pages, downloads, manifests and all three API surfaces pass
  the independent 31-target probe. Eight API manifests, two static manifests
  and eight artifact download checks match the final release hashes.
- Login/bootstrap/config failover, session persistence, Android background and
  custom per-app routing were physically proven.
- The exact Windows 0.3.13 stable installer, payload, registry identity,
  service startup and process launch were proven. Earlier releases proved the
  broader install/reboot/VPN restoration matrix, but an exact 0.3.13 Windows
  tunnel transition remains owner-driven.
- Android/Flutter/backend/native tests, analyzer, Android lint, dependency
  audit, release gate and full current/untracked/Git-history secret scan are
  green.
- Final stable artifacts are Android `0.3.13+2026072604` and Windows
  `0.3.13+2604`; isolated candidate artifacts are also 0.3.13 with distinct
  hashes and the Android `.rc` package identity.
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
   signed successor to the public 0.3.13 release. Until then Windows
   SmartScreen/reputation warnings remain expected.
2. On one owner-controlled Windows PC, explicitly approve one real
   connect/disconnect tunnel transition. The exact public 0.3.13 installer,
   UI, payload and services are already installed and verified.
3. Before buying paid acquisition, complete one owner-driven end-to-end payment
   journey: guest start, real email code, YooKassa payment, receipt,
   cross-platform entitlement and refund/cancellation. Automation must not
   enter the OTP or approve the charge.
4. Supply the Telegram alert bot token and destination chat id, then run one
   delivery smoke. Monitoring itself is active; only this external notification
   channel lacks owner credentials.
5. Advertising remains optional and disabled. Reconsider it only after written
   approval for the exact VPN/WebView2 rewarded flow, usable Russian payout
   terms and a real isolated completion/callback smoke.

Android, Windows and the server-side location pool are published. Account
restoration is verified. Remaining explicit gates are Windows trust, the exact
0.3.13 Windows tunnel transition and the owner-driven payment/refund journey.

## Rollback

- Backend 0.9.129 site-quality production deployment backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260719T141823Z-timeweb-0.9.129-site-quality.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260719T141622Z-ruvds-0.9.129-site-quality.1`.
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
