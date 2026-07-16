# Green VPN Current Handoff

Updated: 2026-07-16.

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
4. Stable production and public downloads are not promoted until the remaining
   launch gates pass.
5. AWG2, Hysteria2, VLESS REALITY/XHTTP, Naive HTTPS and dnstt remain isolated
   to NL2 `5.129.216.42`. The rollout runbook is documentation, not permission
   to deploy them elsewhere.
6. Ads and the forced VPN disconnect timer remain disabled.
7. Billing has one writer: Timeweb. RUVDS serves failover reads/auth/config but
   must reject first-payment creation and must not run the renewal executor.
8. Server maintenance is one node at a time after alternate control/data planes
   pass readiness. The owner Windows PC must not be rebooted by automation.

## Repository

- Root: `C:\Users\gekto\projects\bluevpn`.
- Active branch: `green-vpn-transport-canary-20260711`.
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
- Generated binaries belong in `C:\BlueVPN_Builds`, encrypted restore points in
  `C:\Users\gekto\GreenVPN_Checkpoints`, and secrets outside Git.

## Final product candidate checkpoint, 2026-07-16

- The customer server picker exposes logical locations only: `Авто`,
  `Нидерланды`, and `Англия` when a healthy published England route exists.
  Physical nodes and transports stay internal. Every picker row, including
  `Авто`, has a numeric latency label; an unavailable measurement is displayed
  as `0 мс`.
- Android candidate `0.3.0+2026071603`:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716_r3\GreenVPN_Android_0.3.0_final_candidate_2026071603_debug.apk`.
  SHA-256:
  `BA6BD7CD79A211853FCC0377E904174BF81FD8ECBB9472785FA8DB5F8FDE22D7`.
  It is a side-by-side debug-signed candidate package
  `pro.greenvpn.app.finalcandidate`, not the production APK to publish.
- Windows cascade candidate:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716_r3\windows\GreenVPN_Windows_0.3.0_final_candidate.zip`.
  SHA-256:
  `04D2AB4AD84F9B63641590BDFEE2600C702E79DEC29224B1B4E84A9B17F1FF37`.
  Its product/file version is `0.3.0+1603`; artifact verification passes.
  The Green VPN executables are still unsigned, so this ZIP is an internal
  candidate and must not be a mandatory public update.
- Android UI was checked on physical Android 9 and Android 16/API 36. On the
  physical phone the picker contained exactly one `Авто` row and one
  `Нидерланды` row; both always carried a numeric latency. The measured values
  changed from `16 мс` to `143 мс` on refresh, which also proves that the label
  is live rather than hard-coded. The screenshot is
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716\evidence\android9-server-picker.png`.
  The phone was restored to `Авто`, the candidate was stopped, and no active
  VPN agent remained. Full data-plane transport proofs remain the physical
  Android 9 evidence described in the transport diagnostic.
- Auto-renew management now has one compact entry in Settings and a dedicated
  page for card-binding status and cancellation. The tariff page keeps only the
  purchase-time auto-renew switch and has no active-subscription cancellation
  action. Physical Android 9 QA confirmed the disabled/unlinked state without
  layout overlap. Evidence:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716_r3\evidence\android9-auto-renew-off.png`.
  SHA-256:
  `0A711DD99C1BA67E1AD07A267DB9FC762C89C5488AA53094EFFBC0B79EC4BAAB`.
- Reproducible build manifest:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716_r3\final-candidate-manifest.json`.
  It records the clean source commit above and both artifact hashes.
- `flutter analyze`, 29 public-product Flutter tests, 87 backend tests, Android native unit
  tasks, both APK verifiers, public-surface probes, dependency audit, secret
  scan, standard release gate and strict payment gate are green.

## Live topology

| Role | Host | Current state |
| --- | --- | --- |
| Primary RU control plane | Timeweb Moscow `72.56.32.197` | production API, paid candidate API, site, SMTP, billing writer, DB sync |
| Fallback RU control plane | RUVDS Moscow `176.113.81.35` | production/paid failover, site mirror, SMTP, DB sync, billing read-only |
| Stable VPN NL1 | `37.220.85.211` | stable UDP tunnel active; obsolete Certbot/API TLS retired |
| Stable VPN London | `88.218.250.86` | paid; provider stuck at `initializing 100%`, SSH unavailable, ticket `2026071628000081`; intentionally unpublished |
| Stable VPN + preview NL2 | `5.129.216.42` | stable UDP tunnel plus five isolated hidden preview transports |
| Excluded host | `5.129.237.163` | not managed by this project; do not modify |

The former Timeweb KZ VPS `8360589` / `94.198.221.206` was proven inactive and
retired. Provider recovery image
`2d3d1ae6-899f-48f0-ba1e-985eb5e0344d`
(`greenvpn-kz1-retirement-20260713`) completed successfully and is the rollback
material. KZ is not in DNS, catalogs or assignment state.

## Stable public contour

- Site/API: `https://greenvpn.pro`, `https://api.greenvpn.pro`.
- Backend: `0.9.105` on both RU control planes.
- Android: `0.2.44`, build `2026070504`, SHA-256
  `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Windows SHA-256:
  `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Public catalog contains only stable client-compatible endpoints. Server/provider
  implementation details are not shown in the client.
- Login, bootstrap, catalog, downloads, legal routes and update manifests are
  available through primary and fallback Russian ingress.

## Paid public candidate

- Paths remain isolated at `/paid-beta` and `/paid-beta-api` until promotion.
- Both control planes run release
  `paid-beta-backend-public-client-20260716-r23`, backend
  `0.9.117-public-client.1`.
- The same immutable backend bundle and installer SHA-256 were applied to both
  nodes. Bundle SHA-256 is
  `158F938A8657BF6729380004B791B1095D9337EDD4DAA2C945B075DABF8DDE43`.
  Both SQLite databases pass `PRAGMA quick_check`.
- The public-product client marker permits the final public candidate to create
  a 249 RUB order for accounts previously enrolled in the paid-beta cohort;
  unmarked legacy clients remain rejected.
- Android candidate: `0.3.0-paid-beta.6`, package
  `pro.greenvpn.app.beta`, side-by-side with stable.
- Windows candidate: `0.3.0-paid-beta.11`, SHA-256
  `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32`.
  It is technically tested but unsigned and must not become mandatory.
- Product model: trial 3 days; 249/649/1099 RUB for 30/90/180 days; no ads or
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

- Public surface probe: 31/31 targets green after server maintenance.
- Backend tests: 87 passed.
- `pip-audit`: no known vulnerabilities.
- `flutter analyze`: no issues.
- Flutter tests: 29 passed in the public-product configuration; the ordinary
  suite remains green with public-only tests skipped by design.
- Android debug/profile/release unit-test tasks: successful.
- Release gate: 0 warnings, 0 errors.
- Secret scan: tracked, untracked and complete Git history passed.
- Remaining build warnings are in third-party Pub packages (`file_picker` and
  `yandex_mobileads`), not project source.

## Restore points

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

1. Obtain an Authenticode code-signing certificate and sign the Windows
   installer before mandatory public distribution.
2. RUVDS must finish unlocking the already-paid London VPS. Then preserve its
   disk/configs, run the documented recovery and data-plane smoke, and publish
   it server-side as the single logical location `Англия`.
3. After those gates, build production-signed Android and Windows artifacts,
   run final physical smoke, publish the
   candidate and only then enable forced update.

Do not perform a real payment, enter SMS/bank codes or accept legal terms on
behalf of the owner.
