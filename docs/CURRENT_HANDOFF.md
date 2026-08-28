# Green VPN Current Handoff

Updated: 2026-08-28 MSK.

This is the current operational entry point. Read it together with
`RELEASE_STATE.md`, `PROJECT_MAP_RU.md` and
`PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md`. Dated reports are evidence only.

## Local fixed-term subscription candidate, 2026-08-28

- Source `270a7fa8f6989ebe90be32fa1ddde78f51de2843` implements strict paid
  start/end periods, revision-bound extension quotes, duplicate-purchase
  protection, append-only history, immediate logical expiry, durable peer
  revocation, and reasoned admin grant/revoke. It is pushed and was built from
  a clean worktree.
- Android candidate `0.4.11+2026082805` is production-signed, size `56274061`,
  SHA-256
  `26F8D1D38085FFDC2F47777A0EE369938E5EEBB0C9EE8C9C3AF516D4769B6451`.
- Windows candidate `0.4.6+4637` is an unsigned ZIP, size `54278122`, SHA-256
  `E51330F9A3DA8FE882782EC71FFCCA0142AB69ED558EDE6789A14877A32F65AE`.
  The final ZIP includes `app/tools/greenvpn_standby_probe.ps1`.
- Backend candidate `0.9.165-subscription-lifecycle.1` is size `315136`,
  SHA-256
  `145FFEA587ADB39CD291EA71A86D96B3A142253D0B77A76B86CAF236524084FC`.
- Backend tests passed `234/234`; Flutter passed analyze, `140` default tests
  with `14` intentional skips, and `142` public-product tests with `12`
  intentional skips. Release gate is warnings `0`, errors `0`; parser and secret
  checks passed.
- Exact paths and the lifecycle contract are in
  `docs/SUBSCRIPTION_LIFECYCLE_2026_08_28_RU.md`. The first client root without
  `_v2` is retained as rejected packaging evidence because it omitted the
  standby probe.
- This is local candidate evidence only. No client was installed, no real
  payment or automatic charge was run, and no production node, manifest,
  download or VPN state was changed. Physical active/free-account acceptance
  and an explicitly authorized guarded production deployment remain separate
  gates.

## Current production, 2026-08-28

- Stable backend `0.9.164-autorenew-checkout.1` is deployed on fallback
  `176.113.81.35` and primary `72.56.32.197`. The Android payment-routing
  hotfix source is `0a47e07af795a446a1f24dffa46c8ee198cac809`.
- Stable Android is signed mandatory `0.4.10+2026082804`, size `56365761`,
  SHA-256
  `E12E609C38B1B05879999404E7BE0230E0111E1FB28B660EBBFF940769BACA46`.
  Stable Windows remains mandatory `0.4.6+4636`, `NotSigned`, byte-for-byte
  unchanged. Paid-beta is unchanged.
- Android `0.4.9` could race the primary and fallback API when reading the
  tariff catalog. The read-only fallback correctly advertised sales as
  unavailable, so the client sometimes disabled checkout even though the
  primary billing node was ready. All payment reads and mutations now prefer
  or require the primary writer; a retriable catalog failure may still fall
  back safely without enabling sales on the read-only node.
- One owner-approved YooKassa `249 RUB` transaction completed payment, official
  NPD sale receipt/email, activation, exactly one full refund, entitlement
  rollback and official cancellation receipt/email. No payment identifiers,
  receipt URLs or customer data are stored in Git.
- Primary is the only billing writer and has manual paid sales/refunds enabled.
  Fallback remains read-only with sales disabled. Automatic renewal charges are
  disabled on every contour. The client has explicit future auto-renew consent,
  but the current manual NPD catalog advertises `autoRenew=false`.
- Both Android manifests require minimum `0.4.10` with rollout `100%`. Android
  `0.4.9` receives `426`; `0.4.10` and update manifests receive `200`. Exact APK
  download readback passed on both nodes.
- Physical Android acceptance confirmed exact installed version/build and an
  enabled `Оплатить 249 ₽ за 1 месяц` button. The external WireGuard VPN owner
  remained unchanged; Green VPN did not perform a network transition or create
  a payment order. Strict public verification passed `12/12`; backend versions,
  stable Windows and both paid-beta clients remained unchanged.
- Canonical evidence and rollback paths:
  `docs/PAYMENT_ROUTING_ANDROID_0_4_10_ROLLOUT_2026_08_28_RU.md`.

## Historical YooKassa Manual NPD Backend, 2026-08-27

- Stable backend `0.9.159-yookassa-npd-manual.2` is deployed on fallback
  `176.113.81.35` and primary `72.56.32.197`; exact source commit is
  `a955a2a0adc30f2a4b1f139c77ed574fd9e19256`.
- Final backend-only bundle is `301964` bytes, SHA-256
  `6098E961B783392EA9ABC7C396E4B4BF15FFB26C44CC6382EA641AB1F64D1116`.
  It contains no secrets and changes neither clients nor the main site.
- A successful YooKassa payment now remains `paid_receipt_pending`. Access is
  activated only after an operator supplies an official `lknpd.nalog.ru`
  receipt, the backend rechecks the payment, and the receipt email is sent.
  Full refund revokes entitlement first and remains `refund_receipt_pending`
  until the FNS cancellation receipt is emailed.
- Production selects YooKassa and `yookassa_npd_manual`, but remains
  fail-closed: paid sales, operator confirmation, refund execution and
  automatic charges are disabled. Primary is the only billing writer;
  fallback remains read-only. YooKassa and SMTP credentials are present on
  both nodes, but no secret value was printed or copied into Git.
- The first `.1` deployment was safely superseded after protected readiness
  showed that an old `yookassa_54fz` payment could satisfy the new smoke gate.
  `.2` binds smoke evidence to the currently selected provider and exact
  receipt mode. Production now reports `successfulSmokeCandidates=0` and
  `smokeCompleted=false`, as required before a new real smoke.
- Both DBs return `quick_check=ok`, synchronized counts `66/66/3/99`, and
  explicit sync completed with `success/0`. Both stable APIs report `.2`;
  paid-beta remains `0.9.154-fusion-actions.1`. Admin static exact hashes are
  deployed and the surface remains protected with HTTP `401`.
- Remaining external gate: designate the real NPD operator, perform one real
  owner-controlled payment, register and email its FNS receipt, then perform a
  full refund, register and email the cancellation receipt, and verify the
  entitlement rollback. Only that evidence may enable paid sales; automatic
  charges remain a separate future gate.
- Exact deployment, rollback and verification evidence:
  `docs/YOOKASSA_MANUAL_NPD_BACKEND_DEPLOY_2026_08_27_RU.md`.

## Historical Prodamus NPD Backend, 2026-08-26

- Stable backend `0.9.158-prodamus-npd.2` is deployed on fallback
  `176.113.81.35` and primary `72.56.32.197`; exact source commit is
  `445dd15967c57a879fc9bc91a61509a69b7ecec8`.
- Backend-only bundle is `295414` bytes, SHA-256
  `8531A35742698233498FE27977BC4FFA8A2AA8AFA60ABB269B59C9D193C8EB77`.
  It contains no secrets and changes neither clients nor the main site.
- Prodamus payment-link, exact HMAC notification, idempotent activation,
  reconciliation, manual full-refund confirmation and atomic entitlement
  rollback are implemented. Direct admin activation is rejected.
- Production explicitly selects Prodamus but remains fail-closed: no payform,
  `SYS` or secret is installed; sales, NPD receipts, refunds and auto charges
  are disabled. Fallback rejects callbacks before reading the body.
- Both DBs return `quick_check=ok` and equal counts `66/66/3/99` after explicit
  sync. Strict verification passed `12/12`; all eight stable/paid-beta client
  bodies are unchanged. Email readiness remains true.
- The full Prodamus questionnaire was successfully submitted on 2026-08-26
  with two public channels, the public offer and required verification
  documents. Prodamus reported that an email confirmation was sent, but it had
  not arrived in inbox or spam at the time of this handoff. The stated review
  window is 1-3 business days. Provider approval, NPD partner confirmation,
  one real payment/full refund and sales enablement remain external gates.
- Exact deployment, rollback and evidence:
  `docs/PRODAMUS_NPD_BACKEND_DEPLOY_2026_08_26_RU.md`.

## Historical Robokassa NPD Backend, 2026-08-25

- Stable backend `0.9.157-robokassa-npd.1` is deployed on fallback
  `176.113.81.35` and primary `72.56.32.197`; exact source commit is
  `5fa411a4e1157543ff57cb04aef27ffadff79785`.
- Backend-only bundle is `287550` bytes, SHA-256
  `011C6B0E83A8AA0D29CD828892754EC63EA80E752682544B4FBF14DDD92C96A8`.
  It contains no secrets and changes neither clients nor the main site.
- Robokassa Invoice API, authoritative Invoice + OpStateExt activation,
  ResultURL validation, NPD receipt items and guarded full refund are present.
  Ambiguous invoice/refund creation is never retried automatically.
- Fallback is read-only for payment callbacks and provider polling. Primary is
  the only billing writer. Paid sales, refund execution and automatic charges
  remain disabled; Robokassa credentials and NPD partner confirmation are not
  installed, so `paymentsProductionReady=false` is intentional.
- Both DBs return `quick_check=ok` and equal business counts after explicit
  primary-then-fallback sync. Services and sync timers are active. Public
  verification passed `12/12`; all eight stable/paid-beta Android/Windows
  bodies remain byte-for-byte unchanged.
- Remaining external gates are the action-time consent to transfer INN and
  referral data to the NPD partner, Robokassa/Robocheck SMZ onboarding and one
  separately approved real payment plus full refund.
- Exact deployment and rollback evidence:
  `docs/ROBOKASSA_NPD_BACKEND_DEPLOY_2026_08_25_RU.md`.

## Main Site Cache and Visual Hotfix, 2026-08-25

- Owner review in an existing Yandex Browser profile exposed a real cache
  regression: new HTML was combined with stale CSS, and product screenshots
  became oversized. The fresh-profile-only acceptance was insufficient.
- Corrected production is live at `https://greenvpn.pro/`. Product screenshots
  are no longer referenced, packaged or present in either site webroot. The only
  image used by the page is the Green VPN application icon.
- HTML binds CSS through the new key `/styles.css?v=20260825-r2`. The page uses a
  restrained white/charcoal layout with green, blue and amber accents.
- Exact four-file hotfix bundle is `29407` bytes, SHA-256
  `0D9BBD8F6246894A2B3B127A5CF5265B3FD44490E4A152F0CFA84B173BD7DDFC`.
  Successful rollback roots are
  `/root/greenvpn-main-site-backups/20260825T142928Z` on fallback and
  `/root/greenvpn-main-site-backups/20260825T143004Z` on primary.
- All four live primary files match source SHA-256. Exact `2560 x 1336`,
  `1440 x 1050` and `390 x 844` checks have no overflow, broken assets or browser
  warnings/errors. The existing Yandex Browser tab was hard-refreshed after
  publication.
- Public manifest checks remain `10/10`, static manifests `2/2`, downloads
  `8/8`; release gate passed with warnings/errors `0/0`. Stable Android `0.4.7`,
  stable Windows `0.4.6`, paid-beta, backend, databases, VPN routing and
  Friendly Linnet `5.129.237.163` were not changed.
- Exact deployment and visual evidence:
  `docs/MAIN_SITE_REFRESH_2026_08_25_RU.md`.

## Android Mandatory Stable Rollout, 2026-08-24

- Owner-approved Android stable-only production is `0.4.7+2026082401` on
  fallback `176.113.81.35` and primary `72.56.32.197`.
- Exact signed APK is `56362397` bytes, SHA-256
  `4BA46905702F7A42DD46F768119050FF7F36A31869A2986C0928BBC6F40E5ED2`.
- Both stable/public-product manifests are exact, `required=true`, Android
  `minSupportedVersion=0.4.7`, `rolloutPercent=100` and `fileReady=true`.
  Android `0.4.6` receives `426`; Android `0.4.7` and update manifests receive
  `200`.
- All eight public artifact bodies passed SHA verification. Both production
  DBs pass `quick_check`; explicit primary-then-fallback sync succeeded; all
  backend, paid-beta, sync and probe units are active. Strict public verification
  passed `12/12`; analyze, `138` tests (`14` skipped) and release gate `0/0`
  passed.
- Windows stable remains `0.4.6+4636`; paid-beta Android/Windows and backend
  remain unchanged. Friendly Linnet `5.129.237.163` was not touched.
- Exact deployment, rollback and evidence record:
  `docs/ANDROID_MANDATORY_STABLE_ROLLOUT_2026_08_24_RU.md`.

## Historical Mandatory Stable Rollout, 2026-08-20

- Owner-approved stable production is Android `0.4.6+2026082001`, Windows
  `0.4.6+4636` and backend `0.9.156-mandatory-update.1` on fallback
  `176.113.81.35` and primary `72.56.32.197`.
- Android APK is `56351293` bytes, SHA-256
  `1D2D4015C4D1DD33E8CD31010F672AD901CBB09BE4065AF186980DF1E98F2210`,
  signed. Windows installer is `52809216` bytes, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`,
  `NotSigned`.
- Exact Android in-place physical smoke and exact Windows authoritative
  `full -> applications -> full` smoke passed. Windows selected egress matched
  `5.129.216.42`, selected YouTube returned `204`, Diagnostics visibly showed
  `Подключение: активно`, and cleanup restored external Amnezia/API/YouTube.
- Both stable/public-product manifests are exact, `required=true`,
  `minSupportedVersion=0.4.6`, `rolloutPercent=100` and `fileReady=true`.
  Old stable Android/Windows `0.4.5` requests return `426`; current `0.4.6` and
  update manifests return `200`.
- Four public downloads through primary and fallback matched the exact hashes
  and sizes. Both databases pass `quick_check`; backend, paid-beta and sync
  timers are healthy. Explicit post-release sync completed with no conflicts or
  errors, followed by another exact verification.
- Paid-beta bytes and backend version are unchanged. Paid sales, refunds,
  auto-renew, ads and forced disconnect remain disabled. Friendly Linnet
  `5.129.237.163` was not touched.
- Exact deployment, rollback and evidence record:
  `docs/FUSION_MANDATORY_STABLE_ROLLOUT_2026_08_20_RU.md`.

## Historical Fusion Windows Selected-App Candidate, 2026-08-20

- Exact Windows `0.4.6+4634` passed the selected-app physical routing acceptance,
  but owner review found a Diagnostics false negative while its tunnel was
  active. It is superseded and must not be published.
- Corrected clean-source candidate is `0.4.6+4635`. Installer size is
  `54026240`; SHA-256 is
  `0FBB24B4E79081A393D162130D593327B956D92453361A5944E89E661811ECB7`;
  Authenticode is `NotSigned`. Exact source anchor is
  `fcd0c6e8a83742aa71e4aabf480cfa9df19321d3`.
- Diagnostics now uses authenticated GreenVPNService status as authoritative;
  a denied direct `wg.exe` query can no longer turn a confirmed running tunnel
  into `inactive`. Package audit passed with `66` payload entries and no errors;
  analyze, `135` tests (`14` skipped), focused Fusion tests and release gate
  `0/0` passed.
- Exact `+4635` is installed and physically accepted. Installed app, AOT and
  service bytes match the package hashes; the exact install was retained after
  recovery. Evidence root is
  `C:\BlueVPN_Builds\fusion_production_windows_mode_smoke_20260820_b4635_diagnostics_v1`.
- One delayed detached `+4635` physical smoke passed the authoritative
  `full -> applications -> full` flow. Foreground used one candidate in
  `5.982` client-log seconds with probe and privileged takeover confirmed.
- Direct unselected, explicit SOCKS5 and selected-executable fingerprints were
  captured without storing raw addresses. Selected egress differed from direct,
  matched dedicated egress `5.129.216.42`, and selected YouTube returned `204`.
  Returned-full egress matched the initial full VPN.
- The process-router accepted both selected redirects on loopback and reached
  SOCKS5 upstream. Its stderr was empty; one later unattributed packet remained
  fail-closed during shutdown and did not create a direct fallback or leak.
- Full, applications and returned-full UI/runtime states were consistent. Five
  screenshots were visually inspected; required controls are visible, public
  IP/protocol/route remain hidden, and Diagnostics explicitly shows
  `Подключение: активно`.
- Cleanup restored external Amnezia, API `200` and YouTube `204`, with no
  managed Green tunnel, process-router, metric-`42739` routes or failsafes
  remaining. Exact `+4635` stayed installed.
- Builds `4630` through `4633` are rejected and must never be published. Earlier
  technically accepted `4610` is superseded by the selected-app acceptance and
  also must not be published.
- Stable production, backend, Android and public manifests remain unchanged.
  `productionPublished=false`; no production deployment was attempted.
- The owner accepted the remaining Fusion UI and chose not to repeat a live
  email login; auth/recovery automation is green. The targeted Diagnostics
  check passed, so Fusion UI/email acceptance is final for exact `+4635`.
  The Authenticode/unsigned SmartScreen gate was explicitly deferred, so
  stable-production promotion remains blocked and was not requested.
- Full exact evidence and remaining gates:
  `docs/FUSION_WINDOWS_SELECTED_APP_ACCEPTANCE_2026_08_20_RU.md`.

## Fusion Paid-Beta Closure, 2026-08-13

- Paid-beta backend `0.9.154-fusion-actions.1`, Android
  `0.4.6-paid-beta.1+2026081106` and Windows
  `0.4.6-paid-beta.2+4602` are deployed on both control planes.
- Stable production remains backend `0.9.153-update-channel-alias.4`, Android
  `0.3.19+2026072914` and Windows `0.3.26+3105`; exact public verification
  confirmed that production did not change.
- Exact paid-beta Android SHA-256 is
  `F2FF98B569C574910CEB4ED7BA18EBC33FD54013A1DD15DE808DEC69986F883D`;
  exact Windows SHA-256 is
  `B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3`.
- Android physical smoke passed connection, Netherlands-to-London route
  change, Activity recreation with London state preservation, pause/resume,
  real YouTube playback, corrected one-line diagnostics action and final
  cleanup. The phone was left without an active VPN.
- Exact Windows `0.4.6-paid-beta.2+4602` passed a delayed autonomous physical
  smoke with an independent deadman: Fusion visual contract, one foreground
  candidate, confirmed probe and privileged takeover, cached-route reuse and
  complete final recovery. Client-log connection time was `22.323` seconds on
  the fresh run and `16.257` seconds on the cached run. The external Amnezia
  tunnel, production API and YouTube were restored; no failsafe remained.
- Strict public release verification after the Windows update is `12/12` (`8`
  artifacts and `4` backends). Production Android, Windows and backend remained
  byte/version unchanged.
- Windows paid-beta remains `NotSigned`. The separate stable-runtime candidate
  advanced through rejected or superseded builds `4603`-`4609`; exact build
  `4610` passed its production-candidate physical smoke. It remains unpublished
  and still needs separate UI/email, SmartScreen/signing and stable-promotion
  owner decisions.
- Full evidence and rollback paths:
  `docs/FUSION_PAID_BETA_2026_08_11_RU.md`.

## Hard rules

1. Run `git status --short` before editing. Never reset or overwrite unrelated
   working-tree changes.
2. Never print, commit or place in ordinary archives API/payment/provider
   credentials, private keys, passwords, OTP values, full invite codes or full
   client profiles.
3. Never touch Friendly Linnet `5.129.237.163` without a new explicit owner
   instruction.
4. Android `0.4.7+2026082401` and Windows `0.4.6+4636` are stable production
   and mandatory. Minimum supported versions are Android `0.4.7` and Windows
   `0.4.6`. Paid-beta Android
   `0.4.6-paid-beta.1+2026081106` and Windows
   `0.4.6-paid-beta.2+4602` are isolated, public in the paid-beta contour and
   optional. Do not republish, force or roll them back without a verified exact
   artifact, alternate-node health and an atomic backup.
5. Public-product uses WireGuard UDP, AmneziaWG, Hysteria2, VLESS REALITY/XHTTP
   and Naive HTTPS on NL1, London and NL2. dnstt is the last-resort transport on
   NL2 only. Do not add nodes or change this order without a new guarded rollout.
6. Rewarded ads are temporarily disabled by the owner's 2026-07-22 instruction
   in production and paid-beta on both control planes. Keep the master gate,
   Android Rewarded, web Rewarded and beta `test_web` disabled until a new
   explicit owner instruction. The forced VPN disconnect timer must also remain
   disabled.
7. Billing has one writer: Timeweb. RUVDS serves failover reads/auth/config but
   must reject first-payment creation and must not run the renewal executor.
8. Server maintenance is one node at a time after alternate control/data planes
   pass readiness. The owner Windows PC must not be rebooted by automation.
9. Windows 0.4.6 is public and mandatory, but remains unsigned by explicit
   owner instruction with the SmartScreen risk accepted. Keep the `NotSigned`
   status visible in operations and expect Windows SmartScreen/reputation
   warnings until a higher signed successor is released. On 2026-08-02 the
   signing gate was explicitly deferred because no verified publicly trusted
   issuance route is available under the owner's current legal status. Recheck
   provider eligibility after an IP/legal-entity registration or when choosing
   Microsoft Store; do not store owner tax identifiers in the repository.
10. The admin console is a protected operator surface. Keep Nginx Basic Auth,
    `noindex`, frame denial, staff authentication, RBAC and audit enabled; never
    expose bootstrap tokens or payment/tunnel secrets in the UI or exports.
11. Stable production publishes Android `0.4.7+2026082401` and Windows
    `0.4.6+4636`. Both passed exact physical acceptance before publication;
    Windows selected-app routing and final recovery are confirmed. It is not a
    trusted/signed Windows release; do not conflate successful unsigned
    publication with Authenticode trust.

## Post-Release Control-Plane Helper Safety, 2026-08-02

- Owner decision recorded on 2026-08-02: `v1` is closed as a permanent-Free
  direct-download VPN. Advertising, paid sales and store distribution belong
  to later stages and require new explicit owner decisions.
- No client artifact, production backend/site runtime, database, payment flag,
  advertising flag or VPN route was deployed or changed. Backend source-only
  owner guidance was corrected and remains undeployed until a separate
  production go/no-go.
- Read-only owner/billing/monitoring helpers now use Timeweb
  `72.56.32.197` as the default control plane. External readiness keeps NL1
  `37.220.85.211` as a separate VPN endpoint and accepts legacy
  `-ServerHost` only as an alias for `-ControlPlaneHost`.
- Mutating legacy env/deploy wrappers no longer have an implicit server target;
  they require an explicit allowlisted Timeweb/RUVDS host. Legacy Android E2E
  server cleanup is disabled unless `-EnableServerCleanup` is supplied with an
  explicit control plane.
- Live read-only validation passed: external readiness `11 green / 0 yellow /
  0 red`, monitoring `2` agents covering `6` required targets, Flutter `89`
  tests with `6` intentional skips, backend `178/178`, and release gate
  `0 warnings / 0 errors`.
- The protected commercial launch packet still reports `payments` and
  `windows_trust` as owner-blocked. This is expected while paid sales and
  trusted Windows distribution remain disabled; it does not invalidate the
  already published permanent-Free direct-download release.

## Windows 0.3.26 Standby And Tray Publication, 2026-08-01

This is the current Windows publication entry point. The exact client source
anchor is `e6fd54054972811299abf708ccd46857a1c8b6c4`.

- Production installer:
  `C:\BlueVPN_Builds\public_product_20260801_b3105_standby_tray_candidate_v13_clean_e6fd540\GreenVPN_Setup_0.3.26.exe`,
  `55441408` bytes, SHA-256
  `1E5505E73B735A00E1C7C44BD1919F96F98EA8DC5F03497205EA39E89AAE00F6`.
  It is optional and `NotSigned`; the accepted SmartScreen risk remains.
- Foreground connect uses one candidate and does not wait for the full route
  cascade. Remaining routes are prepared and validated after connection, with
  ten-minute config-bound proofs used only for runtime recovery.
- Exact installed smoke completed foreground takeover in `23.019` seconds,
  accounted for all `15` standby routes and recovered an injected WireGuard
  failure through a prevalidated AmneziaWG route in `28.319` seconds without
  transport overlap. Evidence:
  `C:\BlueVPN_Builds\public_product_20260801_b3105_standby_tray_physical_v17_clean_e6fd540\windows-standby-tray-autonomous-summary.json`.
- Five tray lifecycle cycles retained one process and one icon despite eight
  duplicate launches per cycle. The connected UI state survived transient
  status loss while runtime failover remained armed.
- Validation: Flutter analyze clean, `19/19` focused policy tests, release gate
  `0` warnings / `0` errors, package audit `66` entries, manifest checks green,
  exact Windows public bodies `4/4` and public surface `31/31`.
- Stable and public-product on both control planes return `0.3.26+3105`,
  optional and `fileReady=true`. Rollback directories:
  `/root/greenvpn-windows-stable-release-backups/20260731T234229Z-timeweb-0.3.26-3105`
  and
  `/root/greenvpn-windows-stable-release-backups/20260731T234011Z-ruvds-0.3.26-3105`.
- A first RUVDS attempt was interrupted by the local SSH wrapper during a
  normal backend restart; the atomic transaction restored `0.3.25` before the
  successful retry. Failed-attempt backup:
  `/root/greenvpn-windows-stable-release-backups/20260731T233921Z-ruvds-0.3.26-3105`.
- Android, paid-beta, advertising, billing, refunds, renewal execution, VPN
  server routes and Friendly Linnet `5.129.237.163` were not changed.

## Historical Windows 0.3.25 Status Reconciliation Publication, 2026-07-31

This records the previous Windows publication. Its exact client source anchor
is `cad2bbbca1e27899c6730b59c412a94a977efb13`.

- Production installer:
  `C:\BlueVPN_Builds\public_product_20260731_b3104_status_reconcile_final\GreenVPN_Setup_0.3.25.exe`,
  `55404544` bytes, SHA-256
  `D93BE65841C2625D3B728EB409C762357A8DD6CAA744F1E032769BCBB21BE1FB`.
  It is optional and `NotSigned`; the existing owner acceptance of the
  SmartScreen/reputation risk remains in effect.
- Root cause: the ordinary non-elevated UI could not query `wg.exe`, interpreted
  that diagnostic failure as a real disconnect after resume and disarmed the
  runtime monitor even though the privileged service and `BlueVPNDev1` tunnel
  remained active.
- Resolution: Windows status now comes first from the authenticated privileged
  local service. A transient or incomplete snapshot is `unknown` and preserves
  the last known UI state; resume performs an immediate read plus retry, and a
  five-second reconciliation loop repairs later drift without reconnecting the
  tunnel.
- Physical defect smoke used the exact runtime extracted from the final
  installer while `WireGuardTunnel$BlueVPNDev1` remained running. Before and
  after a real minimize/restore cycle the accessibility tree showed `Включено`
  and `Отключить VPN`; API health was `200` and YouTube `generate_204` was `204`.
  Evidence:
  `C:\BlueVPN_Builds\public_product_20260731_b3104_status_reconcile_final\windows-ui-status-reconciliation-smoke.json`.
- Validation: Flutter analysis clean; client tests `80` passed / `6` skipped;
  exact installer package audit passed with `65` payload entries; all stable,
  public-product and unchanged paid-beta manifests passed; four complete
  Windows public bodies matched `4/4`; public surface passed `31/31`.
- Publication is active on both production control planes. Stable and
  public-product manifests return `0.3.25+3104`, optional and `fileReady=true`.
  Atomic rollback directories are
  `/root/greenvpn-windows-stable-release-backups/20260731T171003Z-timeweb-0.3.25-3104`
  and
  `/root/greenvpn-windows-stable-release-backups/20260731T171359Z-ruvds-0.3.25-3104`.
- The first Timeweb apply attempt exposed a Python-heredoc indentation defect in
  the release script. Its transaction restored `0.3.24`, the old public body
  hash and backend health before the script was corrected, all five embedded
  Python blocks were compiled, and the successful apply was retried. The failed
  attempt backup is
  `/root/greenvpn-windows-stable-release-backups/20260731T170812Z-timeweb-0.3.25-3104`.
- Android, paid-beta, advertising, billing, refunds, renewal execution, VPN
  server routes and Friendly Linnet `5.129.237.163` were not changed.

## Historical Windows 0.3.24 Fast Cache And Recovery Publication, 2026-07-31

This records the previous Windows publication. Its exact client source anchor
is `ab0e87b4734ae159005f4ed31f6c9a57bedd5284`.

- Production installer:
  `C:\BlueVPN_Builds\public_product_20260731_b3103_fast_cache_v3\GreenVPN_Setup_0.3.24.exe`,
  `55401472` bytes, SHA-256
  `A6938B0EBA54BF0CC4CE029F8A3365D28DB63FA280A2E897B63FEA079F02FA38`.
  It is optional and `NotSigned`; the owner accepted the existing SmartScreen
  risk for unsigned publication.
- Foreground connect uses one candidate and accepts the real YouTube data-plane
  probe as runtime health. Deeper catalog/fallback work remains in the
  background, while the last confirmed route and protocol are kept in the user
  state directory for the next connection.
- Exact-package autonomous physical smoke passed twice with AmneziaWG already
  active. The clean-cache run selected only `current_wg0` / `wireguard_udp`,
  confirmed the probe and privileged takeover in `20.139` seconds wall time
  (`14.115` seconds in the app log). The cached repeat used the same one route
  and completed in `17.373` seconds wall time (`12.203` seconds in the app log).
  Cleanup restored `AmneziaWGTunnel$device20_full`, stopped Green VPN, removed
  the failsafe and preserved public health and YouTube access.
- Validation before publication: Flutter tests `75` passed / `6` skipped,
  Flutter analysis clean, release gate clean and the exact installer package
  audit passed.
- Publication verification: stable/public-product manifests on both control
  planes return `0.3.24+3103`, optional and `fileReady=true`; all four Windows
  production/paid-beta public bodies matched their exact SHA-256 and size; the
  external public-surface probe passed `31/31`.
- Atomic rollback:
  `/root/greenvpn-windows-stable-release-backups/20260731T155944Z-timeweb-0.3.24-3103`
  and
  `/root/greenvpn-windows-stable-release-backups/20260731T160110Z-ruvds-0.3.24-3103`.
- Paid-beta Windows remains `0.3.21-paid-beta.1+3001`. Android, advertising,
  billing, refunds, renewal execution, VPN server routes and Friendly Linnet
  `5.129.237.163` were not changed.

## Historical Windows 0.3.22 Instant Foreground Connect Publication, 2026-07-31

The exact client source anchor was
`412cdd54645fcd50f5711cc6b9e14ffdff6bb242`. The production installer was
`C:\BlueVPN_Builds\public_product_20260731_b3101_commit412cdd5\GreenVPN_Setup_0.3.22.exe`,
`55400960` bytes, SHA-256
`5F2EA0EC09DE7BE7932DF22328F3B95243445B09FBF38F41DBE59D9F66DDF197`.
It was optional and `NotSigned`. Automated validation and publication checks
passed, but Codex did not run a post-install physical connection smoke for that
artifact. Rollback directories were
`/root/greenvpn-windows-stable-release-backups/20260731T040115Z-timeweb-0.3.22-3101`
and
`/root/greenvpn-windows-stable-release-backups/20260731T040044Z-ruvds-0.3.22-3101`.

## Historical Windows 0.3.21 Fast Connect And Takeover Closure, 2026-07-30

This section records the previous Windows/backend operational state. The exact
Windows source anchor was `b6f60de44efdeaa5b89aa9097a8b87affa40e78d`.

- Production installer:
  `C:\BlueVPN_Builds\public_product_20260730_b3001_takeover_v4\GreenVPN_Setup_0.3.21.exe`,
  `55400960` bytes, SHA-256
  `0D98EDBDBA4FFFA6B94F5C0D04CF3461C0C8E5F57AEC57FB201D678ED45A5E85`.
- Paid-beta installer:
  `C:\BlueVPN_Builds\paid_beta_20260730_b3001_takeover_v4\GreenVPN_Beta_Setup_0.3.21-paid-beta.1.exe`,
  `55383040` bytes, SHA-256
  `34D838226281190EB6B867D87884B4C9AF066FD69C7D49D05D045713530338CA`.
  Both updates are optional and `NotSigned`.
- Exact production runtime/failover evidence:
  `C:\BlueVPN_Builds\public_product_20260730_b3001_takeover_v4\windows-public-runtime-failover-physical.json`.
- Autonomous competing-VPN summary:
  `C:\BlueVPN_Builds\public_product_20260730_b3001_takeover_v4\windows-competing-vpn-takeover-autonomous-summary.json`.
  All three repeats used one WireGuard candidate, confirmed the real probe and
  privileged takeover, then restored AmneziaWG and removed the failsafe.
  Application-log connect time was `4.092-4.131` seconds; full smoke wall time
  was `9.355-9.617` seconds.
- Backend `0.9.153-update-channel-alias.4` is active on both production and
  paid-beta contours. `channel=public-product` now returns the exact `stable`
  Windows manifest on both primary and fallback.
- Bidirectional production/paid-beta replication passes with zero conflicts
  and errors. Both DBs pass `PRAGMA quick_check`, both timers are active and
  both nodes have zero failed units. The final replication fix is commit
  `8aac1bb3095853060fc3931c3573ba2a6b2c7240`.
- Final checks: backend `178/178`, client `72` passed / `6` skipped, release
  gate clean, manifests/downloads `20/20`, exact public bodies `8/8` and public
  surface `31/31`.
- Windows rollback:
  `/root/greenvpn-windows-release-backups/20260730T204906Z-timeweb-0.3.21-3001`
  and
  `/root/greenvpn-windows-release-backups/20260730T204609Z-ruvds-0.3.21-3001`.
- Android artifacts, sales, refunds, renewal execution, Rewarded ads, forced
  disconnect, server routes and Friendly Linnet `5.129.237.163` were not
  changed.

## Historical Windows Connection Latency Hotfix, 2026-07-29

This section overrides the older Windows release values below. The clean source
anchor is `790c4b66aa9eb1dacaecca388d4dba93185e28a9`.

- Two real owner-click runs on public `0.3.19` took `93.7` and `96.3` seconds.
  Catalog/config preparation was only about `5-7` seconds. Most delay came from
  an approximately `59` second WireGuard wait, repeated heavyweight diagnostics
  and a serial post-connect probe.
- Windows WireGuard confirmation is now bounded, repeated status checks are
  lightweight, YouTube probes run concurrently and the last successful route is
  preferred for 24 hours.
- A separate root cause made the app miss an already-running external VPN:
  PowerShell diagnostics used `runInShell: true`, which returned exit code zero
  but dropped the service-list output. Direct `powershell.exe -NoProfile
  -NonInteractive` execution preserves the output. A competing VPN now produces
  one explicit failure and stops the route cascade without cooling down routes.
- Exact installed `0.3.20+2921` physically detected the owner's active AmneziaWG
  in `11.277` seconds, attempted one candidate only, started no second route and
  left every Green VPN component stopped. AmneziaWG remained `Running` and
  public health remained HTTP `200`. This proof comes from the primary
  application log. Four generic UI smoke-wrapper attempts failed to observe the
  localized competing-VPN result, although each cleanup passed; do not cite
  those wrapper JSON files as successful physical reports.
- With AmneziaWG temporarily paused, the immediately preceding candidate using
  the same successful-connect path established the system tunnel and a YouTube
  `204` probe in about `9.9` seconds. Exact `2921` success was not repeated
  automatically because the owner Amnezia process runs at higher Windows
  integrity and cannot be paused from the non-elevated Codex process. The
  `2921` product change after that proof is limited to competing-VPN detection
  and early cascade termination.
- Production installer:
  `C:\BlueVPN_Builds\public_product_20260729_b2921\GreenVPN_Setup_0.3.20.exe`,
  `55393280` bytes,
  SHA-256 `96F6AE8EBAD2F597693D824625125CC97CB39DEC3E1B7D8E352D335EF5F49D24`.
- Paid-beta installer:
  `C:\BlueVPN_Builds\paid_beta_20260729_b2921\GreenVPN_Beta_Setup_0.3.20-paid-beta.1.exe`,
  `55374848` bytes,
  SHA-256 `A9EAEDB0FBA007ADB1B28FFDD993011C04741E97EAAE859FD4A9D1F833176D18`.
  Both installers are `NotSigned`.
- Production and paid-beta Windows artifacts are optional on Timeweb Moscow and
  RUVDS. Atomic rollback directories are
  `/root/greenvpn-windows-release-backups/20260729T195124Z-timeweb-0.3.20-2921`
  and
  `/root/greenvpn-windows-release-backups/20260729T194711Z-ruvds-0.3.20-2921`.
- Validation passed: Flutter analyze, `68` passed / `6` skipped tests, release
  gate `0` warnings / `0` errors, production and paid-beta package audits,
  dynamic/static manifests, exact public bodies `8/8` and public surface
  `31/31`. Both services are active on both control planes. Guarded retention
  kept the new RUVDS rollback and reduced root use from `85%` to `79%`.
- Android, backend feature flags, billing, Rewarded ads and forced disconnect
  were not changed. The local PC is left with `0.3.20+2921` installed, Green VPN
  disconnected and the owner's AmneziaWG service running.
- Separate confirmed residual: the Windows public-product build sends
  `channel=public-product` to `/api/v1/updates/manifest`, while both current
  backends accept `stable` for the published Windows release and return HTTP
  `400` for `public-product`. Direct site downloads and the published files are
  healthy, but in-app update discovery for this build is not. Resolve this with
  a separately tested server alias or a higher client build; do not silently
  replace the already-published `0.3.20` bytes.

## Authoritative Closure, 2026-07-29

This section overrides older `Current` sections below when they conflict.
The complete evidence map is
`FULL_PROJECT_CLOSURE_2026_07_29_RU.md`.

- Source anchor for the candidate is clean commit
  `c52ba7d6b3f3cfbda49e63515013ab9a37eaf48a`. Application version is
  `0.3.19`, Android build `2026072914`, Windows build `2914`.
- Production and paid-beta backend `0.9.152-release-ready.1` are active on
  Timeweb `72.56.32.197` and RUVDS `176.113.81.35`. Both databases pass
  `PRAGMA quick_check`; synchronization and probes are healthy.
- The frozen product contract is permanent Free and guest-first. Email is
  requested only before payment or to restore an existing account. The stored
  Free policy is `3 GB/month`, one device and `10/20 Mbit/s`, but quota and rate
  enforcement are disabled. These values and enforcement flags are server-side
  and do not require a client rebuild.
- Paid sales, refund execution, tax workflow confirmation, automatic renewal
  charges, rewarded ads and forced disconnect are disabled on both contours.
  Paid-beta now records every related deny value explicitly in both root-only
  env files instead of relying on backend defaults. Rollback copies are under
  `/root/greenvpn-paid-beta-explicit-failclosed-backups/20260729T072608Z`
  on Timeweb and
  `/root/greenvpn-paid-beta-explicit-failclosed-backups/20260729T072610Z`
  on RUVDS.
  The stale Timeweb paid-beta renewal timer was disabled and a manual run
  proved `enabled=False`, `executed=0`, `failed=0`.
- A keyed value-blind comparison proves exact Timeweb/RUVDS functional parity
  inside production and inside paid-beta for the server catalog, app releases,
  feature flags and owner-action statuses. Expected node-local health
  timestamps are not treated as contract drift.
- Old backends on NL1 `37.220.85.211` and London `88.218.250.86` are removed.
  Their unit is `not-found`, port `8000` is closed, port 80 returns deliberate
  `410`, and legacy DB/env copies were deleted only after the encrypted
  checkpoint passed a full archive test.
- The side-by-side Android final-candidate SHA-256 is
  `16A48F555D2640717A87D3B8927A08F859F05A1169E4DA3D02ED324218A5D990`.
  The exact production-package APK SHA-256 is
  `BCA7CF6A4AB2381A6EB44836726AFC07B460B87F0789BA88DC81CF84CD37F4FB`.
  It passed an upgrade over public `0.3.15`, launch, real VPN through NL1,
  production API, YouTube and clean disconnect before publication.
- Exact Windows production installer SHA-256 is
  `6D5E33B0EAB146C9E2EAA78E8B5F6636B9BCBDDC11D387A07C5B71CB6E9894FB`.
  All `63/63` installed payload files match, the five alternate transports
  passed, runtime failure recovered without overlap, and the temporary network
  failsafe was removed. Exact paid-beta installer SHA-256 is
  `E1451CED069941A431B383E74B20B8E938CD2758C99CBD129F45A731AF1B44D1`.
  Both installers remain `NotSigned`.
- Android post-maintenance proof passed all `16/16` routes and strict Quick
  Tile order
  `wireguard_udp -> amneziawg -> hysteria2 -> vless_reality -> naive_https -> dnstt`.
  Test packages, VPN state, cooldown and temporary tile were removed.
- NL2 received pending `glibc` and kernel maintenance, rebooted successfully,
  and no longer requires reboot. A deterministic systemd dependency now starts
  `danted` after `wg0`; all transports are active and failed units are zero.
- Android production and paid-beta `0.3.19+2026072914` are published through
  Timeweb and RUVDS as optional updates. Production SHA-256 is
  `BCA7CF6A4AB2381A6EB44836726AFC07B460B87F0789BA88DC81CF84CD37F4FB`;
  paid-beta SHA-256 is
  `99EB6C2D44C955F43441039B5375CEC5AF925D19EDAFEE1D17042FAE6E2ED8A7`.
- Windows production `0.3.19+2914` and paid-beta
  `0.3.19-paid-beta.1+2914` are published through both control planes as
  optional updates. The owner explicitly accepted unsigned publication and
  SmartScreen/reputation risk. Current dynamic/static manifests pass, all
  eight full public download hashes match, and public surface passes `31/31`.
- Android rollback backups are
  `/root/greenvpn-apk-release-backups/20260729T094454Z-timeweb-0.3.19-2026072914`
  and
  `/root/greenvpn-apk-release-backups/20260729T094418Z-ruvds-0.3.19-2026072914`.
- Windows rollback backups are
  `/root/greenvpn-windows-release-backups/20260729T145410Z-timeweb-0.3.19-2914`
  and
  `/root/greenvpn-windows-release-backups/20260729T145347Z-ruvds-0.3.19-2914`.
- Authenticode certificate access is now a trust/reputation improvement for a
  higher signed Windows successor, not an unpublished-release blocker.
  Legal/tax/KYC decisions apply only if paid sales are enabled. Google Play and
  rewarded ads are optional future scopes.

## Historical Launch Closure, 2026-07-28 20:12 MSK

- Production and paid-beta backend `0.9.148-owner-boundary.1` are active on
  Timeweb and RUVDS. Both SQLite databases pass `PRAGMA quick_check`; Timeweb
  remains the only production billing writer.
- The protected owner launch packet has exactly one owner blocker and one
  pending owner action: `windows_trust`. All other launch areas are either
  ready or intentionally disabled by policy.
- The missing item is an Authenticode code-signing certificate with a usable
  private key. This is not a Windows 10/11 operating-system license. Windows SDK
  `signtool.exe` is already installed; local preflight currently finds zero
  valid code-signing certificates.
- `scripts/windows/finalize_windows_trusted_release.ps1` now auto-detects a
  valid Code Signing EKU certificate, builds production and isolated paid-beta
  installers, signs the Green VPN app/service before payload compression,
  signs the bootstrap, signs the final IExpress EXE only after resource
  updates, verifies publisher/timestamp/hash and emits immutable JSON evidence.
- `scripts/server/install_windows_public_product_release.sh` accepts both
  signing reports, binds them to the exact production/test SHA-256 values and
  publishes trusted metadata only when both reports prove the same valid
  signing identity. Unsigned publication clears trusted metadata instead of
  producing a false-green readiness result.
- The exact public Android `0.3.15+2026072704` artifact also passed a clean
  Android 16/API 36 emulator install, cold launch, production tunnel,
  recognized NL1 egress, API/YouTube probes and clean disconnect. The generated
  guest/device was removed through guarded admin cleanup, both databases were
  synchronized and the emulator was left without Green VPN or probe packages.
- Paid-beta and production catalog summaries now match:
  `managedTotal=18`, `managedActive=16`, `managedHealthy=16`,
  `clientConfigReady=17`, `publicClientServers=3`, `eligible=3`.
- NL2 certificate synchronization was already installed and healthy:
  source/destination certificates match, the timer is active, both Naive HTTPS
  and Hysteria services are active and the certificate expires
  2026-10-09. No TLS mutation was needed.
- Guarded release-backup retention is active on both control planes. RUVDS disk
  use fell from 80% to 77%; Timeweb from 58% to 46%. The latest rollback sets
  remain retained.
- Final live verification passed on both control planes: production and
  paid-beta SQLite databases return `PRAGMA quick_check=ok`, both backend
  services and both database-sync timers are active, and systemd reports zero
  failed units.
- The full pre-certificate checkpoint is
  `C:\Users\gekto\GreenVPN_Checkpoints\launch_closure_20260728_193808`.
  Its Git all-refs bundle is complete; encrypted local/server archives pass
  `7z t` and match their recorded SHA-256 values. Plaintext staging and remote
  temporary snapshot files are absent.
- Real SMTP alert delivery passed in production and paid-beta. Telegram is
  optional and is not a launch blocker.
- Rewarded ads, forced disconnect, hard expiry, production renewal execution
  and paid-beta quota enforcement remain disabled. No payment, OTP, KYC,
  contract or renewal charge was initiated during closure.

## Current Public Transport Cascade, 2026-07-28 MSK

- Production backend `0.9.148-owner-boundary.1` is active on both control
  planes. Catalog identity is `2026-07-28-public-transport-v1`. The
  public-product catalog contains 16 routes on each control plane:
  3 WireGuard UDP, 3 AmneziaWG, 3 Hysteria2, 3 VLESS REALITY, 3 Naive HTTPS and
  1 dnstt.
- The fixed client order is:
  `wireguard_udp -> amneziawg -> hysteria2 -> vless_reality -> naive_https -> dnstt`.
  Within one protocol, healthy low-latency routes win. A failed candidate must
  be fully disconnected; the cascade stops fail-closed if clean-down cannot be
  proven.
- Android production is signed `0.3.15+2026072704`, package
  `pro.greenvpn.app`, size `76764418`, SHA-256
  `72C4672355722EB4111EAA36BC6794EB71F9E20F3DB6818093489B8A59F48288`.
  Android paid-beta is signed `0.3.15+2026072704`, package
  `pro.greenvpn.app.rc`, size `76764470`, SHA-256
  `B12BEC69AA0F0C04F17C7E536C97AD8EA3F88FA38BD9BA8FBAFAA070033572D4`.
  Both are optional and published through both control planes.
- Android physical proof passed all 16 exact routes, production API, external
  egress, YouTube and clean-down. Injected AmneziaWG failure recovered through
  Hysteria2 with no engine overlap. A separate Quick Settings proof passed all
  six protocol groups in strict order, restored WireGuard after cooldown reset
  and finished with no VPN record or transport process.
- Windows production is unsigned `0.3.17+2608`, size `55388672`, SHA-256
  `518A6BD61CBFD1C46B7460439963D2D6D48448BF2A7B14A1397D192D335934C4`.
  Windows paid-beta is unsigned `0.3.17+2608`, size `55372800`, SHA-256
  `21CDE69380BB288A63E1D5BC56A7715A95B3DBF664B93EBE4E3002D65C987AC3`.
  Both are optional and published through both control planes. The exact stable
  installer was installed on the owner PC. Its service survived app exit; an
  injected active WireGuard service failure recovered to another guarded route
  with verified egress, no transport overlap and complete cleanup.
- Publication verification passed eight dynamic manifests, two static
  manifests, all eight exact download hashes, public surface `31/31`, release
  gate `0 warnings / 0 errors`, backend `162/162`, Flutter tests, Android
  native tests/lint and the tracked/untracked/history secret scan.
- `check_public_download_manifests.ps1` is pinned to this release and exits
  nonzero on any mismatch. `verify_public_release_download_hashes.ps1` supports
  a named partial retry and recursively removes its own temporary directory
  without masking the original download or hash failure.
- Windows publication evidence is
  `C:\BlueVPN_Builds\public_product_20260728_windows_runtime_failover_acl_6\publication-evidence.json`;
  the post-publication surface report is in the same directory as
  `public_surface_after_publish.json`.
- Current physical evidence:
  `C:\BlueVPN_Builds\public_product_transport_cascade_20260727_b2704\android_public_product_transport_matrix_physical_public_product.json`,
  `C:\BlueVPN_Builds\public_product_transport_cascade_20260727_b2704\android_quick_tile_strict_cascade_physical.json`
  and
  `C:\BlueVPN_Builds\public_product_transport_cascade_20260727_b2704\android_exact_release_smoke.json`.
  Windows exact-installer execution is recorded in
  `C:\BlueVPN_Builds\public_product_20260728_windows_runtime_failover_acl_6\windows_runtime_failover_physical.json`;
  the corrected payload-verification and runtime-failover proof is
  `C:\BlueVPN_Builds\public_product_20260728_windows_runtime_failover_acl_6\windows_runtime_failover_physical_retry1.json`.
- Android rollback backups:
  RUVDS `/root/greenvpn-apk-release-backups/20260727T220440Z-ruvds-0.3.15-2026072704`;
  Timeweb `/root/greenvpn-apk-release-backups/20260727T220752Z-timeweb-0.3.15-2026072704`.
- Backend rollback backups:
  RUVDS
  `/root/greenvpn-public-product-backups/20260728T162921Z-ruvds-0.9.148-owner-boundary.1`;
  Timeweb
  `/root/greenvpn-public-product-backups/20260728T163058Z-timeweb-0.9.148-owner-boundary.1`.
- Paid-beta backend rollback backups:
  RUVDS
  `/root/greenvpn-paid-beta-backend-backups/20260728T162846Z-paid-beta-backend-owner-boundary-20260728-r1`;
  Timeweb
  `/root/greenvpn-paid-beta-backend-backups/20260728T163037Z-paid-beta-backend-owner-boundary-20260728-r1`.
- Windows rollback backups:
  RUVDS
  `/root/greenvpn-windows-release-backups/20260728T133211Z-ruvds-0.3.17-2608`;
  Timeweb
  `/root/greenvpn-windows-release-backups/20260728T133747Z-timeweb-0.3.17-2608`.
- Rewarded advertising, forced disconnect and hard expiry enforcement remain
  disabled. Production renewal execution is disabled. A pre-existing guarded
  Timeweb paid-beta renewal timer remains enabled every 15 minutes; all 327
  runs audited through 2026-07-28 17:00 MSK reported `executed=0`, while RUVDS
  has no renewal timer. No payment, OTP, account, renewal or advertising state
  was changed by this Windows rollout.
- The only external owner blocker is Windows code signing. The single-node
  dnstt last resort and the mixed dirty working tree remain internal
  engineering risks, not owner actions. TLS synchronization, Android 16
  compatibility, paid-beta catalog parity and guarded disk retention are
  verified.
- Repository closure is still outstanding. The transport branch is ahead of
  origin and has a large mixed working tree; it is not a reproducible release
  anchor. Several legacy build/smoke scripts retain dated version defaults and
  must either require explicit release parameters or move into a clearly
  historical namespace before the next release.

## Latest Production Closure Check, 2026-07-27

- Production backend `0.9.141-autorenew-optin.1` is active on Timeweb Moscow
  and RUVDS Moscow. Missing `autoRenew` now defaults to `false`; only an
  explicit client opt-in returns `true`. Timeweb remains the sole billing
  writer. The existing paid subscription, saved payment method flag and
  activated order were not changed.
- Mandatory Android is signed `0.3.14+2026072702`, package
  `pro.greenvpn.app`, size `76760042`, SHA-256
  `FE7BF607CA5D37E85C6BB6AC569AD0DBF9DE5C42C73337DDCC54A161877D99EE`.
  Optional paid-beta is package `pro.greenvpn.app.rc`, size `76760194`,
  SHA-256
  `FA1F8EC851D5F0EDC92C27EF0DCB945CB036CEF56762D173CB39AD9E7E611232`.
  Both exact artifacts are published through both control planes.
- Physical Android smoke passed guest-first launch, tariff display
  `249/649/1099` RUB, auto-renew off by default, explicit account restore,
  connect, real tunnel traffic, clean disconnect and no crash/ANR. Measured
  download was `30.176` Mbit/s. The phone was left disconnected with stable
  `0.3.14` installed and its local data preserved.
- Mandatory Windows remains unsigned `0.3.13+2604`, SHA-256
  `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30`.
  Production provisioning, fresh handshake, traffic, DNS/no-leak probes and
  clean disconnect passed. The owner's independent
  `AmneziaWGTunnel$device20_full` service was restored to `Running`; the
  Green VPN smoke failsafe task was removed.
- Exact-byte checks passed for all four Android URLs. Eight dynamic manifests,
  two static manifests, eight download endpoints, public-surface `31/31`,
  external readiness `12 green / 0 yellow / 0 red`, and the strict release
  gate `0 warnings / 0 errors` passed.
- Paid-beta free tier is enabled with quota enforcement off, stored limit
  `3` GB, one device and `10` Mbit/s profile. London, NL1 and NL2 usage
  reporters have active timers and last result `success`. Both paid-beta
  databases agree on `21` traffic rows and byte totals
  `rx=17136`, `tx=38932`.
- Production expiry enforcement remains off. The only current expiry warning
  is three unreviewed guest Trial subscriptions inside the seven-day window,
  all without a verified retention email; there are no expired-active
  subscriptions. Do not turn this expected guest state into a hard block.
- Rewarded advertising and the forced disconnect timer remain disabled in
  every contour. Automatic renewal charge execution also remains disabled.
  Enabling ads, charges, a launch promotion or hard expiry enforcement is a
  separate owner/business decision.
- Windows rollback readiness is green. Previous production installer
  `0.3.12`, SHA-256
  `79F5E201F8F798906C9A7FF5F837B9C5AD08B4890DEB3DF0B7F3F2E3C4EC0FE7`,
  is published as a dedicated rollback through both mirrors. The sole
  critical Windows distribution blocker is now the unsigned installer.
  Telegram alerts additionally need an owner-created bot token/chat id, but
  monitoring itself is green.
- Evidence:
  - Windows:
    `C:\BlueVPN_Builds\windows_0.3.13_final_smoke_20260727\production-network-transition-report.json`;
  - Android physical smoke:
    `C:\BlueVPN_Builds\android_autorenew_optin_production_20260727_b2702\physical_stable_smoke`;
  - Android public verification:
    `C:\BlueVPN_Builds\android_autorenew_optin_production_20260727_b2702\public_release_verification`.
- Production backend rollback:
  - RUVDS:
    `/root/greenvpn-public-product-backups/20260727T044740Z-ruvds-0.9.141-autorenew-optin.1`;
  - Timeweb:
    `/root/greenvpn-public-product-backups/20260727T044850Z-timeweb-0.9.141-autorenew-optin.1`.
- Android rollback:
  - RUVDS:
    `/root/greenvpn-apk-release-backups/20260727T045823Z-ruvds-0.3.14-2026072702`;
  - Timeweb:
    `/root/greenvpn-apk-release-backups/20260727T050009Z-timeweb-0.3.14-2026072702`.
- Windows rollback configuration:
  - RUVDS:
    `/root/greenvpn-release-rollback-backups/20260727T052740Z-ruvds-production-windows-0.3.12`;
  - Timeweb:
    `/root/greenvpn-release-rollback-backups/20260727T052815Z-timeweb-production-windows-0.3.12`.

## Latest Android Checkout Check, 2026-07-27

- The owner approved Android-only work. Windows was not launched, installed,
  rebuilt or connected.
- Side-by-side RC `pro.greenvpn.app.rc` is locally installed as
  `0.3.14+2026072701`. Production `pro.greenvpn.app` remains
  `0.3.13+2026072604`.
- RC APK:
  `C:\BlueVPN_Builds\android_autorenew_optin_20260727\GreenVPN_Android_0.3.14_2026072701.apk`,
  SHA-256
  `92B97AB029373348B7FDC963AB759C6D603FE8F45E7F22CA2DF9EC6B1C3EDE7D`.
  It is not a production publication.
- Exact clean-device behavior passed: guest-first launch, free profile,
  249/649/1099 RUB plans, auto-renew off by default, payment email gate before
  order creation, no OTP, no order, no charge and no VPN transition.
- Paid-beta backend on both control planes is
  `0.9.141-autorenew-optin.1`, release
  `paid-beta-backend-autorenew-optin-20260727-r1`. Missing `autoRenew` now
  defaults to false server-side. Production backend was not changed.
- Backend `148/148`, Flutter `58 passed / 6 platform skips`, analysis,
  APK signing and physical UI checks passed. Both paid-beta databases pass
  `PRAGMA quick_check`; services and sync timers are active; primary and
  fallback public paid-beta health are green.
- All temporary guests and VPN peers created during this smoke were removed
  and synchronized. RC is stopped with cleared local data.
- The real paid account remains active and identical on both production
  databases through `2026-08-24T23:13:22.297175+00:00`, with
  `auto_renew=1` and one activated 249 RUB order. Production Android currently
  has a guest local session; use the standalone existing-account email sign-in
  to restore it. Do not create another payment.
- Backend rollback:
  Timeweb
  `/root/greenvpn-paid-beta-backend-backups/20260727T035234Z-paid-beta-backend-autorenew-optin-20260727-r1`;
  RUVDS
  `/root/greenvpn-paid-beta-backend-backups/20260727T035243Z-paid-beta-backend-autorenew-optin-20260727-r1`.

## Latest Owner Restore And Site Check, 2026-07-26

- The owner completed the real standalone production sign-in on Windows
  `0.3.13`. Timeweb and RUVDS contain the same successful Windows
  `checkout_email_verify` event for the same existing account. The local
  Windows client persisted the session and received HTTP 200 from
  `/api/v1/subscription/me`.
- The account is verified and has active `green_30d` access through
  `2026-08-24T23:13:22.297175+00:00`, five devices and `auto_renew=1`.
  Android `0.3.13` physically shows
  `Текущий: Green VPN — 1 месяц`; Android and Windows resolve to the same
  backend account.
- Restore did not create a new payment: the account still has one existing
  activated 249 RUB order and zero orders created in the last six hours.
  Windows was not connected, so its device/config row is intentionally not
  counted until first provisioning. No VPN route was changed.
- The main-site sentence beginning
  `Попробуйте Green VPN бесплатно 3 дня` was removed entirely. Both servers
  have identical `index.html` SHA-256
  `AF112FD5C5EE9DD58CBD509DE4E15EE6A949CB12D01CEBFD8E4BB7906C07B9B0`.
  The public primary page returns 200, retains both client downloads and
  contains neither the removed sentence nor the intermediate neutral text.
- Site rollback:
  - RUVDS: `/root/greenvpn-main-site-backups/20260726T065207Z`;
  - Timeweb: `/root/greenvpn-main-site-backups/20260726T065359Z`.
- The RUVDS storage incident is resolved. Root use fell from 97% with about
  635 MB free to 67% with about 6.3 GB free; steady-state I/O wait is 0% and
  local production/paid-beta health is HTTP 200 at about 3 ms. Timeweb is 53%
  used with about 18 GB free. No host/backend restart, reboot, route change or
  business-record deletion occurred.
- Root cause was continuous full SQLite replication (30-second production and
  10-second paid-beta timers), unbounded release backups and 21 days of
  high-volume probe observations. Observation retention is now seven days
  with `30000/12000/30000` row caps; release backup retention keeps four
  recent directories in each allowlisted high-volume root.
- Sync is serialized locally, queued for up to 240 seconds, limited by a
  five-minute service timeout and staggered by calendar. Timeweb runs
  production at `:00/:10/:20/:30/:40/:50` and paid-beta at `:02/:32` UTC;
  RUVDS runs production at `:05/:15/:25/:35/:45/:55` and paid-beta at
  `:17/:47` UTC.
- All four databases passed `PRAGMA quick_check`, manual sync completed in all
  four directions with zero conflicts/errors, and the failed RUVDS probes
  passed after recovery. The first staggered calendar cycles passed on
  Timeweb production/paid-beta and RUVDS production; the external public
  surface passed `31/31`. Current sync rollback:
  Timeweb `/root/greenvpn-db-sync-safety-backups/20260726T075834Z`;
  RUVDS `/root/greenvpn-db-sync-safety-backups/20260726T075840Z`.

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
- Android 0.3.6 account-switch checkpoint: the commit containing this handoff.
- Generated binaries belong in `C:\BlueVPN_Builds`, encrypted restore points in
  `C:\Users\gekto\GreenVPN_Checkpoints`, and secrets outside Git.

## Current Production Account Restore 0.3.13, 2026-07-26

- The owner explicitly approved installation on Android and Windows and
  publication through both production sites. Production backend is
  `0.9.140-account-restore.1` on Timeweb Moscow and RUVDS Moscow; Timeweb is
  still the only billing writer.
- Mandatory production artifacts:
  - Android `0.3.13+2026072604`, package `pro.greenvpn.app`, signed, SHA-256
    `C296936053773BFCF8F8BB9E9A1CD2267A669832FCD451112F9DC4429B8C1629`;
  - Windows `0.3.13+2604`, unsigned, SHA-256
    `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30`.
- Both production manifests use `required=true`. Both isolated paid-beta
  manifests retain the exact `.rc`/test artifacts with `required=false`.
  Rewarded ads and the forced disconnect timer remain disabled everywhere.
- Android and Windows were installed and physically checked. Both expose a
  standalone `Уже есть подписка? / Войти по email` action distinct from
  checkout. Android was left disconnected and stopped. Green VPN on Windows
  was left disconnected; the independent `pc_valentine` WireGuard route was
  preserved unchanged. Windows services are automatic and running.
- Deployment itself used no purchase email, OTP, new order or payment. The
  later owner-driven sign-in verified restoration on both platforms without a
  new order. The remaining owner-only product check is Windows
  provisioning/connect-disconnect.
- Release-time verification passed: external manifest/download checker `18/18`; complete
  production downloads from both sites match exact hashes; public-surface
  probe `31/31`; all production and paid-beta database quick checks; two-way
  manual sync; matching release-row digests; active services and zero failed
  units. The resolved storage-incident section above is the current operational
  health snapshot.
- Rollback:
  - backend RUVDS:
    `/root/greenvpn-public-product-backups/20260726T010132Z-ruvds-0.9.140-account-restore.1`;
  - backend Timeweb:
    `/root/greenvpn-public-product-backups/20260726T010847Z-timeweb-0.9.140-account-restore.1`;
  - Android RUVDS:
    `/root/greenvpn-apk-release-backups/20260726T010937Z-ruvds-0.3.13-2026072604`;
  - Android Timeweb:
    `/root/greenvpn-apk-release-backups/20260726T012414Z-timeweb-0.3.13-2026072604`;
  - Windows RUVDS:
    `/root/greenvpn-windows-release-backups/20260726T011630Z-ruvds-0.3.13-2604`;
  - Windows Timeweb:
    `/root/greenvpn-windows-release-backups/20260726T012434Z-timeweb-0.3.13-2604`.
- Operational-retention snapshots:
  RUVDS `/root/greenvpn-operational-retention-backups/20260726T010307Z`;
  Timeweb `/root/greenvpn-operational-retention-backups/20260726T010854Z`.
- The unsigned Windows installer remains the main distribution trust defect.

## Previous Isolated Account-Restore Candidate 0.3.13, 2026-07-26

- This is the pre-promotion checkpoint. Production was still mandatory
  `0.3.12`; both isolated paid-beta control planes published `0.3.13` with
  `required=false`.
- The product journeys are deliberately independent:
  - guest start/refresh does not require email;
  - standalone `Войти по email` restores an existing account/subscription and
    does not create an order or open YooKassa;
  - `Оплатить` remains only for a new purchase and verifies email first;
  - expired guest state refreshes as guest, while expired account state asks
    for sign-in.
- Exact client artifacts:
  - Android `0.3.13+2026072604`, package `pro.greenvpn.app.rc`, signed,
    SHA-256
    `82772195710B468E0CF45B468D0AB36B95365A8C8541B47098951B44413BBEBA`;
  - Windows `0.3.13+2604`, unsigned, SHA-256
    `6E4A33C902FE47FD9B14173B12426F25C9F1F601D6CA94321EDC883D5EF0A507`.
- Paid-beta backend is `0.9.140-account-restore.1`, release
  `paid-beta-backend-account-restore-20260726-r2`, on both nodes. Dedicated
  access recovery endpoints are
  `/api/v1/auth/access/email/start` and
  `/api/v1/auth/access/email/verify`; backend archive SHA-256 is
  `BF0854C3BEC78853B5C52120106EA9875620BB34394D92B7A77913AACDE19384`.
- Verification passed: Flutter analyze; Flutter
  `57 passed / 6 platform skips`; backend `86/86`; Python compile;
  `git diff --check`; local release gate `0 errors / 0 warnings`; exact
  primary/fallback downloads; both database quick checks; conflict-free manual
  sync; active services/timers; public-surface probe `31/31`.
- Exact Android b2604 physical UI passed:
  - Home shows `Бесплатный` and a standalone existing-subscription sign-in;
  - Tariff shows `Бесплатный тариф`, 249/649/1099 RUB and standalone sign-in;
  - Settings shows `Бесплатный профиль / Без регистрации` and restore action;
  - restore dialog says `Войти в аккаунт`, asks for the subscription email and
    contains no payment/receipt language;
  - the phone was left disconnected.
- Windows physical installation is intentionally pending. The owner PC has an
  active `pc_valentine` WireGuard tunnel; the candidate shares the stable
  single-instance/service identity, so installation could interrupt the
  route. A portable launch raised the already running stable `0.3.12` process
  and therefore was not counted as b2604 evidence. No Windows adapter, route
  or service state was changed.
- Rollback:
  - backend Timeweb:
    `/root/greenvpn-paid-beta-backend-backups/20260725T235341Z-paid-beta-backend-account-restore-20260726-r2`;
  - backend RUVDS:
    `/root/greenvpn-paid-beta-backend-backups/20260725T235423Z-paid-beta-backend-account-restore-20260726-r2`;
  - client Timeweb:
    `/root/greenvpn-paid-beta-client-release-backups/20260726T002604Z-timeweb-0.3.13-0.3.13`;
  - client RUVDS:
    `/root/greenvpn-paid-beta-client-release-backups/20260726T002627Z-ruvds-0.3.13-0.3.13`.
- Remaining owner-only sequence:
  1. use the real purchase email and OTP in standalone sign-in;
  2. verify paid entitlement with no new order/YooKassa page;
  3. verify the same entitlement on the second platform;
  4. approve a short Windows VPN interruption window and install/smoke the
     exact b2604 installer;
  5. only then decide on a separately approved production promotion.

## Previous Production Guest-First 0.3.12, 2026-07-26

- The owner explicitly approved production publication. Both Timeweb Moscow
  and RUVDS Moscow now publish mandatory stable `0.3.12` clients:
  - Android `0.3.12+2026072506`, package `pro.greenvpn.app`, signed, SHA-256
    `6FEBDE9FDBC6E2624FC57F8C18459B432A4F54D3A73A7CC18CB1302777CFCC33`;
  - Windows `0.3.12+2506`, unsigned, SHA-256
    `79F5E201F8F798906C9A7FF5F837B9C5AD08B4890DEB3DF0B7F3F2E3C4EC0FE7`.
- The isolated paid-beta artifacts remain `0.3.12` with `required=false`:
  Android SHA-256
  `B3EFBB0ECEC7108993BE2776B23CAEF013F62952E5BCA7761DBA34F1671801DA`
  and Windows SHA-256
  `F8AE5B1439D21BF2B3EE0EF39843FA54501AF50DEC6F3D4CFD016D04824F2BC8`.
  Paid-beta Android keeps package `pro.greenvpn.app.rc`.
- Production backend is `0.9.139-guest-first.1` on both control planes. Public
  bootstrap uses `guest` as primary, `email_code` as fallback and exposes only
  `guest`, `email_code` and `email_password`; no phone method is present.
  Billing remains single-writer on Timeweb.
- `https://greenvpn.pro/`, its privacy page and the fallback backend landing
  now describe the same contract: automatic guest profile, email only before
  payment or account recovery, three tariffs at 249/649/1099 RUB and no claim
  that advertising is active. Rewarded advertising and the forced disconnect
  timer remain disabled in production and paid-beta on both nodes.
- Exact production Android passed owner-device physical smoke: clean guest
  start, all three tariffs, payment-time email gate, Android VPN permission,
  connected and validated real tunnel, public API reachability and clean
  disconnect. The phone was left disconnected.
- The exact production Windows installer replaced the paid-beta payload.
  Registry/application identity is `0.3.12+2506`, installed payload hashes
  match the stable artifact, `GreenVPNService` is automatic and running, and
  the application process launches and responds. Desktop visual capture failed
  in the automation layer and no Windows tunnel transition was performed
  because that would alter the owner's Windows network. Do not represent this
  as a completed Windows tunnel smoke. The installer is unsigned.
- Verification after publication:
  - backend tests `144/144`;
  - final local release gate `0` errors and `0` warnings;
  - eight API manifests, two static paid-beta manifests and eight download
    checks pass;
  - full primary/fallback production downloads match the exact SHA-256 values;
  - public-surface probe `31/31`;
  - both production databases have `26` users and `26` subscriptions, both
    paid-beta databases have `5` users, all pass `PRAGMA quick_check`;
  - manual sync succeeds in both directions, services and timers are active,
    and fresh backend warning count is zero.
- Release automation defect caught during publication:
  `install_android_public_product_release.sh` previously hard-coded
  `required=true` for paid-beta and the obsolete
  `pro.greenvpn.app.beta` identity. It now takes explicit production/test
  required flags, defaults paid-beta to `false`, publishes
  `pro.greenvpn.app.rc`, verifies the result and waits up to 90 seconds for
  backend health. The first RUVDS Android attempt was superseded by the
  corrected atomic deployment before final verification.
- Current rollback:
  - backend RUVDS:
    `/root/greenvpn-public-product-backups/20260725T223750Z-ruvds-0.9.139-guest-first.1`;
  - backend Timeweb:
    `/root/greenvpn-public-product-backups/20260725T224049Z-timeweb-0.9.139-guest-first.1`;
  - main site RUVDS:
    `/root/greenvpn-main-site-backups/20260725T223241Z`;
  - main site Timeweb:
    `/root/greenvpn-main-site-backups/20260725T223437Z`;
  - Android RUVDS corrected deployment:
    `/root/greenvpn-apk-release-backups/20260725T221755Z-ruvds-0.3.12-2026072506`;
  - Android Timeweb:
    `/root/greenvpn-apk-release-backups/20260725T222248Z-timeweb-0.3.12-2026072506`;
  - Windows RUVDS:
    `/root/greenvpn-windows-release-backups/20260725T222005Z-ruvds-0.3.12-2506`;
  - Windows Timeweb:
    `/root/greenvpn-windows-release-backups/20260725T222307Z-timeweb-0.3.12-2506`.
- Release bundles:
  - final backend archive SHA-256
    `25C3901BB2CD4E7BB65F0B2B78F63477E3268B153B87A49E2DC98E50B2BA2F41`;
  - final backend `main.py` SHA-256
    `6DC9BF293140D4E8C75D209D3F4D3DBF2BD409356A61246ACEB906B95D19B200`;
  - main-site archive SHA-256
    `461B22BD5BEB6E916993D7CABDA7610F220D6EDEF64AD4A965BFD691C92A6277`.

## Superseded Paid-Beta Release Candidate 0.3.11, 2026-07-25

- Exact public paid-beta artifacts are now published through both control
  planes, but production was not changed:
  - Android `0.3.11+2026072505`,
    package `pro.greenvpn.app.rc`, label `Green VPN`, SHA-256
    `04F82EFA95B1D5F2D12BD81EC8B77204C79B674EDBAA0E4FA990F7AEC184BFCE`;
  - Windows `0.3.11+2505`, unsigned, SHA-256
    `A416F9E6C7DDD8BC9A22289344CD9F756A0F7B570A8ADDA4B83D34F99F55859F`.
- Both API manifests, both static manifests, all eight primary/fallback
  download checks and full-byte downloads through both public ingress routes
  match. The static manifests have `isolated=true`,
  `productionPublished=false`, package `pro.greenvpn.app.rc` and label
  `Green VPN`. The public-surface probe passes 31/31.
- The exact Android artifact passed owner-device physical smoke: no visible
  `Beta`, email-code delivery, temporary password login, free mode with the
  traffic cap disabled, the 249/649/1099 RUB tariff selector, real Android VPN
  permission, validated `tun0`, public API reachability and clean disconnect.
  The temporary account and peer were removed; both candidate databases have
  zero smoke users and pass `PRAGMA quick_check`.
- The exact Windows installer is installed as `Green VPN 0.3.11`; the service
  is automatic and running, and the application opens on the unified
  authentication screen without visible `Beta`. It remains unsigned, and no
  Windows VPN/network smoke was performed because automation must not alter the
  owner's Windows network.
- Paid-beta backend was subsequently updated to
  `0.9.136-guest-first.1` on both nodes. The published `0.3.11` artifacts are
  unchanged; email-code and password recovery remain available, while public
  phone/SMS authentication has been removed.
- Client rollback directories:
  - RUVDS:
    `/root/greenvpn-paid-beta-client-release-backups/20260725T191930Z-ruvds-0.3.11-0.3.11`;
  - Timeweb:
    `/root/greenvpn-paid-beta-client-release-backups/20260725T192136Z-timeweb-0.3.11-0.3.11`.
- Production remains backend `0.9.129-site-quality.1`, Android `0.3.7` SHA-256
  `CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431`
  and Windows `0.3.6` SHA-256
  `0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA`
  on both nodes. Do not promote 0.3.11 to production without separate owner
  approval.

## Previous Isolated Paid-Beta Guest-First 0.3.12, 2026-07-25

- Source implements the new guest-first contract:
  - a clean install creates an anonymous server session automatically;
  - phone/SMS login is absent from client UI, public auth routes, bootstrap and
    release readiness;
  - a verified email code is required immediately before billing order
    creation;
  - a new email upgrades the same guest, while an existing email restores the
    existing account and transfers the current device;
  - guest tokens are revoked when the guest is upgraded or switched;
  - backend rejects guest/unverified billing with
    `email_verification_required`.
- Exact isolated artifacts remain published through both paid-beta control
  planes with `required=false`. The same guest-first version has since been
  published separately to production:
  - Android `0.3.12+2026072506`, package `pro.greenvpn.app.rc`, label
    `Green VPN`, signed, SHA-256
    `B3EFBB0ECEC7108993BE2776B23CAEF013F62952E5BCA7761DBA34F1671801DA`;
  - Windows `0.3.12+2506`, unsigned, SHA-256
    `F8AE5B1439D21BF2B3EE0EF39843FA54501AF50DEC6F3D4CFD016D04824F2BC8`.
- Artifact manifest:
  `C:\BlueVPN_Builds\guest_first_20260725_0.3.12\paid-beta-artifacts.json`.
  It records `isolated=true`, `productionPublished=false`, paid-beta API
  origins and Rewarded ads disabled.
- Verification: Flutter analyze passed, all Flutter tests passed
  (`52 passed`, `6 platform skips`), backend policy suite passed (`85/85`),
  local release gate passed with `0` errors and `0` warnings, APK signature and
  transport verifiers passed.
- Both API manifests and both static manifests match `0.3.12`, report
  `isolated=true`, `productionPublished=false`, `fileReady=true` and
  `required=false`. Full Android and Windows downloads through both public
  ingress routes are byte-identical to the expected hashes. The independent
  public-surface probe passes `31/31`.
- Physical Android smoke used the exact primary public download after removing
  all five older Green VPN test/stable packages. A clean launch created a guest
  session and opened the VPN screen without an email gate or visible `Beta`.
  The 249/649/1099 RUB tariff selector is present, and pressing payment opens
  `Email для оплаты`. Android VPN permission, a validated tunnel, public API
  reachability and a clean disconnect passed. The device is left disconnected
  with only `pro.greenvpn.app.rc` version `0.3.12` installed.
- The old Windows `0.3.6` installation was removed and the exact primary public
  `0.3.12` installer was installed. Registry version is `0.3.12`, executable
  version is `0.3.12+2506`, `GreenVPNService` is automatic and running, and a
  clean launch opens the guest VPN screen without an email gate or visible
  `Beta`. Windows tunnel smoke remains owner-only because it changes the
  owner's network. The installer remains unsigned.
- The matching backend is deployed only to paid-beta on Timeweb Moscow and
  RUVDS Moscow as `0.9.136-guest-first.1`, release
  `paid-beta-backend-guest-first-20260725-r1`. Both public paid-beta health
  routes and bootstraps agree on `guest` as the primary method and expose only
  `guest`, `email_code` and `email_password`; no phone method is present.
- Backend rollback directories:
  - RUVDS Moscow:
    `/root/greenvpn-paid-beta-backend-backups/20260725T201136Z-paid-beta-backend-guest-first-20260725-r1`;
  - Timeweb Moscow:
    `/root/greenvpn-paid-beta-backend-backups/20260725T201321Z-paid-beta-backend-guest-first-20260725-r1`.
- Client rollback directories:
  - RUVDS Moscow:
    `/root/greenvpn-paid-beta-client-release-backups/20260725T203532Z-ruvds-0.3.12-0.3.12`;
  - Timeweb Moscow:
    `/root/greenvpn-paid-beta-client-release-backups/20260725T203648Z-timeweb-0.3.12-0.3.12`.
- Both paid-beta services and DB sync timers are active. A guest endpoint smoke
  succeeded; its single temporary user was removed through the admin API and
  the tombstone was synchronized to both nodes. Both databases pass
  `PRAGMA quick_check`, manual sync completed with exit status `0`, and the
  secretless public-surface probe passes `31/31`.
- Remaining paid-beta-only owner gates are real email-code delivery from the
  payment gate and a Windows VPN/network transition. Do not create a payment
  or change the owner's Windows route without explicit action-time approval.
- Production promotion was separately approved and completed on 2026-07-26;
  the current production state is recorded above.

## Rewarded Ads Temporarily Disabled, 2026-07-22

- The owner explicitly requested that advertising inside Green VPN be disabled
  for now. No client binary was republished: the server-side gate is the
  authoritative control and existing clients fetch it before a connection.
- Production and paid-beta on Timeweb Moscow `72.56.32.197` and RUVDS Moscow
  `176.113.81.35` now run with `GREENVPN_FREE_AD_GATE_ENABLED=0`, an empty
  `GREENVPN_FREE_AD_GATE_PLATFORMS`,
  `GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED=0`,
  `GREENVPN_YANDEX_REWARDED_WEB_ENABLED=0` and
  `GREENVPN_FREE_AD_TEST_WEB_ENABLED=0`. The session timer remains disabled.
- Environment files and the actual `/proc` environments of all four running
  services match. Production and paid-beta health are green on both public
  routes, all four SQLite databases pass `PRAGMA quick_check`, both database
  sync timers are active, recent service error logs are empty, and the
  secretless public-surface probe passes 31/31.
- Runtime rollback directories:
  - RUVDS production:
    `/root/greenvpn-rewarded-ads-backups/20260722T202003Z-production`;
  - RUVDS paid-beta Android:
    `/root/greenvpn-rewarded-ads-backups/20260722T202014Z-paid-beta`;
  - RUVDS paid-beta Windows:
    `/root/greenvpn-rewarded-ads-backups/20260722T202022Z-paid-beta-windows`;
  - Timeweb production:
    `/root/greenvpn-rewarded-ads-backups/20260722T202149Z-production`;
  - Timeweb paid-beta Android:
    `/root/greenvpn-rewarded-ads-backups/20260722T202157Z-paid-beta`;
  - Timeweb paid-beta Windows:
    `/root/greenvpn-rewarded-ads-backups/20260722T202205Z-paid-beta-windows`.
- The ad SDK, challenge tables and provider integration remain dormant in the
  current source and binaries. Do not remove or reactivate them without a new
  product decision and a fresh beta-to-production gate.

## Current Freemium And Windows Ads Candidate, 2026-07-19

- Production clients remain unchanged at Android `0.3.7` and Windows `0.3.6`;
  Windows ads remain disabled. The production backend is
  `0.9.129-site-quality.1`, a landing-page-only revision based on the prior
  production source rather than the newer paid-beta source.
- Paid-beta on both Russian control planes is backend
  `0.9.131-freemium.2`. Existing Netherlands and London locations are free;
  future catalog drafts default to premium. Free accounts cannot use
  `social_only`, and premium locations are rejected server-side even if an old
  or modified client attempts to request them.
- Paid-beta Android `0.3.9+2026071902` SHA-256:
  `2B016FCB70A8C50DD6D5F86DD2B326CFB82D636AA9CB39D1FB8BC25B38A91AFC`.
- Paid-beta Windows `0.3.9-paid-beta.1902` SHA-256:
  `CE282C7BC56082F53DA030F047DA83F7FDD64315DD9C4FFE823B9C023BDBA8FC`.
  It is installed at `C:\Program Files\Green VPN Beta`, its app and
  `GreenVPNBetaService` are running, and the common desktop and Start menu
  shortcuts exist. The app opened the preserved paid session without a crash.
- Paid-beta retains the same implemented ad contract on both control planes,
  but its runtime gate and platform allow-list are now disabled. Android
  Rewarded and Windows `test_web` are both off. Production also has an empty
  advertising platform allow-list and no test provider.
- `0.9.131` fixes the environment contract found during final verification:
  both deploy and runtime use `GREENVPN_FREE_AD_TEST_WEB_ENABLED`; the old
  `GREENVPN_AD_TEST_WEB_ENABLED` remains only as a compatibility fallback.
  `/proc` inspection of both running paid-beta services confirms the canonical
  flag is now `0` and effective.
- Current Windows beta account is paid, so live bootstrap correctly reports no
  ad requirement. The free contract is covered without adding another live
  account: 130 backend tests and 46 Flutter tests verify UI/server entitlement,
  challenge completion and one-connect consumption.
- Yandex site `api.greenvpn.pro`, id `19615469`, was rejected for site
  quality/content rather than a stated categorical VPN prohibition. Yandex
  support advised improving unique content, navigation and working controls;
  the earliest permitted resubmission is 2026-08-18 12:55 MSK. A follow-up
  confirmed that a compliant new site can be added and that Rewarded has no
  minimum traffic threshold. Yandex promised a separate answer within 24 hours
  on whether Windows WebView2 visits count as site traffic. Do not resubmit
  early and do not promote Windows ads until `greenvpn.pro` passes moderation,
  a real `R-A-N-N` block id exists and a real paid-beta callback smoke passes.
- A concrete moderation defect was fixed: the API landing page Android button
  returned 404. Production `0.9.129-site-quality.1` now uses
  `/download/android`, exposes matching Windows and Android cards, and labels
  the no-ad benefit accurately as paid-only. Both control planes pass database
  and service checks, the browser-rendered page is correct, and the independent
  public-surface probe is 31/31. Main SHA-256:
  `A811BF8450E5DC003FEFA4BDF1FBF583EC1B1DF591C21699FC37A03ACCD26E7A`.
- Alternative Rewarded inquiries were sent from the project mailbox to
  MediaToday, Monetag, ayeT Studios, AppLixir and Adsterra. The decision order
  is Yandex first; MediaToday if direct RUB payout plus Windows S2S verification
  are confirmed; Monetag if non-Telegram Rewarded and WebMoney/USDT are
  confirmed; ayeT if Russian payout is confirmed; AppLixir after its traffic
  threshold is met; Adsterra only with explicit written approval for an
  incentivized Rewarded flow. Google is not a Russian payout fallback.
- Client rollback:
  `/root/greenvpn-paid-beta-client-release-backups/20260719T103659Z-timeweb-0.3.9-paid-beta.1902-0.3.9-paid-beta.1902`
  and
  `/root/greenvpn-paid-beta-client-release-backups/20260719T103700Z-ruvds-0.3.9-paid-beta.1902-0.3.9-paid-beta.1902`.
- Backend rollback:
  `/root/greenvpn-paid-beta-backend-backups/20260719T125141Z-paid-beta-backend-freemium-20260719-r7`
  on Timeweb and
  `/root/greenvpn-paid-beta-backend-backups/20260719T124934Z-paid-beta-backend-freemium-20260719-r7`
  on RUVDS Moscow. Bundle SHA-256:
  `C1C5A1BEFA2610118B2BFE59474AF09E0A7CA253E6575FBA50DE9EB973877519`.

## Final audit checkpoint, 2026-07-19

- At this original audit checkpoint, production and paid-beta on Timeweb and
  RUVDS Moscow ran backend `0.9.129-final-audit.5`; `main.py` SHA-256 was
  `FB35FDA24856A64C3506107734CEAB8DCCC7B10B5B355950618784DB1661AFC8`.
  All four services are healthy, both databases on each node pass
  `PRAGMA quick_check`, and explicit state sync converges without errors. The
  current production and paid-beta revisions are recorded in the section above.
- Active-active identity merge preserves independently newer verified email and
  phone state. Admin identity login throttling applies across source IPs.
  Guarded operational-retention timers are active on both nodes and exclude
  accounts, subscriptions, billing, support and catalogs from pruning.
- Production Android is `0.3.7+2026071902`, SHA-256
  `CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431`.
  Test Android is the same version, SHA-256
  `910D7C8D03E224484050EFB4AE845C0B2DD6FC592B85B7A3FF8B1475DE21E5C5`.
  Both are release signed, published on both mirrors and mandatory.
- Production Windows is unsigned `0.3.6+1808`, SHA-256
  `0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA`.
  Paid-beta Windows is unsigned `0.3.6-paid-beta.1808`, SHA-256
  `19BCCFB0866CAC69F78B9F6A3BFBC8C9A0AFE293876D95E3091179FEEBAB2AF4`.
  Native bootstrap, browser MOTW, package contents and the complete prior
  install/reinstall/uninstall/rollback matrix pass. The exact final public EXE
  needs only an owner-approved UAC install on a target PC; automation must not
  accept that elevation prompt.
- Validation: 122 backend tests; 34 Flutter tests and two intentional skips;
  clean Flutter analysis; Android unit tests and lint; no dependency findings;
  90 PowerShell and 64 project-owned Bash syntax checks; JavaScript parse;
  strict release gate; complete current/untracked/history secret scan.
- Public verification is 31/31 surfaces, eight API manifests, two static
  manifests and eight downloads. Main site, legal pages, admin assets and both
  artifact mirrors match the expected hashes.
- Lower dated sections are retained as historical evidence. The versions and
  gates in this checkpoint and the Stable/Paid sections below are authoritative.

## Published Admin Console, 2026-07-19

- Operator URL: `https://admin.greenvpn.pro/`. Nginx Basic Auth is the outer
  gate; staff email/password, short-lived session, optional 2FA and backend RBAC
  remain the inner gate.
- Production API version is `0.9.129-site-quality.1` on both Russian control planes.
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
- Validation: 122 backend tests; Python/JavaScript compile; 264 unique HTML ids;
  live health, database indexes, analytics, pagination, CSV and CORS passed on
  both control planes. Backend SHA-256 is
  `A811BF8450E5DC003FEFA4BDF1FBF583EC1B1DF591C21699FC37A03ACCD26E7A`
  after the site-only production revision; admin static assets are unchanged.
- Rollback:
  - Timeweb backend: `/root/greenvpn-admin-release-backups/20260717T181919Z-timeweb-0.9.121-admin.1`;
  - RUVDS backend: `/root/greenvpn-admin-release-backups/20260717T181612Z-ruvds-0.9.121-admin.1`;
  - Timeweb static: `/root/greenvpn-admin-static-backups/20260717T182028Z-admin-console`.

## Published product releases, 2026-07-19

- The customer server picker exposes logical locations only: `Авто`,
  `Нидерланды`, and `Лондон` when a healthy published London route exists.
  Physical nodes and transports stay internal. Every picker row, including
  `Авто`, has a numeric latency label; an unavailable measurement is displayed
  as `0 мс`.
- Production Android `0.3.7+2026071902`, package `pro.greenvpn.app`:
  `C:\BlueVPN_Builds\public_product_final_audit_20260719_r2\GreenVPN_Android_0.3.7_2026071902.apk`.
  SHA-256:
  `CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431`.
- Test Android `0.3.7+2026071902`, package `pro.greenvpn.app.beta`:
  `C:\BlueVPN_Builds\public_product_final_audit_20260719_r2_test\GreenVPN_Android_0.3.7_2026071902.apk`.
  SHA-256:
  `910D7C8D03E224484050EFB4AE845C0B2DD6FC592B85B7A3FF8B1475DE21E5C5`.
- Both APKs are release signed, passed artifact verification and were published
  atomically on Timeweb and RUVDS Moscow. Stable and paid-beta Android manifests
  are mandatory and point to the matching hashes.
- Published Windows production installer:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.6_final_20260719_r2\GreenVPN_Setup_0.3.6.exe`.
  Product/build: `0.3.6+1808`; SHA-256:
  `0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA`.
  It is unsigned and was published by explicit owner instruction to production
  as mandatory on both RU control planes.
- Published Windows test installer:
  `C:\BlueVPN_Builds\green_vpn_windows_0.3.6_paid_beta_final_20260719_r2\GreenVPN_Beta_Setup_0.3.6-paid-beta.1808.exe`.
  Version `0.3.6-paid-beta.1808`; SHA-256:
  `19BCCFB0866CAC69F78B9F6A3BFBC8C9A0AFE293876D95E3091179FEEBAB2AF4`.
  It remains optional and uses the isolated paid-beta API contour.

## Rewarded ads, 2026-07-18

- Production and paid-beta backends are `0.9.124-admin-cleanup.1` on Timeweb and RUVDS
  Moscow. Timeweb remains the only billing writer and all four services are
  healthy.
- The Yandex rewarded block `R-M-19313018-1` is served to Android 0.3.5 and newer
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
- Physical production 0.3.6 smoke preserved a second-account session on a
  phone already registered to the owner's original account. The client
  recognized the sanitized ownership conflict, rotated its local device
  identity, retried bootstrap successfully and opened the real rewarded ad.
  The ad was not completed by automation and the VPN was left disconnected.
- Account deletion now removes ad challenges/grants and records replication
  tombstones by `public_id`. The disposable smoke account and four historical
  orphan ad rows were removed; both paid-beta databases report zero orphan ad
  rows and `PRAGMA quick_check=ok`.
- 102 backend tests and 32 Flutter tests pass, Flutter analysis is clean, all
  eight API manifests, both static paid-beta manifests and all eight download
  checks pass, and the public probe is 31/31. Exact production and test APKs
  downloaded from the primary site match the hashes above.
- Yandex Partner remains an external owner gate: add the application-store URL
  and complete the requested payout/legal profile. Do not enter bank, passport,
  tax or self-employment data on the owner's behalf.
- Rollback directories:
  - APK Timeweb: `/root/greenvpn-apk-release-backups/20260718T170717Z-timeweb-0.3.6-2026071802`;
  - APK RUVDS: `/root/greenvpn-apk-release-backups/20260718T170502Z-ruvds-0.3.6-2026071802`;
  - production backend Timeweb: `/root/greenvpn-public-product-backups/20260718T165718Z-timeweb-0.9.123-ads.1`;
  - production backend RUVDS: `/root/greenvpn-public-product-backups/20260718T165626Z-ruvds-0.9.123-ads.1`;
  - paid-beta backend Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T165737Z-paid-beta-backend-ad-min-version-20260718-r28`;
  - paid-beta backend RUVDS: `/root/greenvpn-paid-beta-backend-backups/20260718T165631Z-paid-beta-backend-ad-min-version-20260718-r28`;
  - static manifest Timeweb: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120557Z-android-0.3.5-2026071801`;
  - static manifest RUVDS: `/root/greenvpn-paid-beta-static-manifest-backups/20260718T120534Z-android-0.3.5-2026071801`.
  - orphan cleanup Timeweb: `/root/greenvpn-paid-beta-ad-orphan-cleanup-backups/20260718T122049Z`.

## Confirmed Codex test-account cleanup, 2026-07-18

- Exactly six production identities and one paid-beta identity were attributed
  to Codex test/smoke work. All ambiguous, phone-generated and real-looking
  customer identities were excluded. Production now contains 25 users and
  paid-beta contains one user on both control planes.
- Before deletion, both SQLite databases on each node were backed up online to
  root-only directories. The complete preserved identity digest and protected
  account core state match those backups after deletion and after explicit
  Timeweb/RUVDS sync cycles.
- Backend `0.9.124-admin-cleanup.1` deletes every user-owned database row,
  endpoint/transport assignment and route event; it removes the configured/live
  peer and emits replication tombstones for all synchronized records. The sync
  merger also removes complete account dependents when applying a user
  tombstone.
- Post-cleanup checks on both nodes: `PRAGMA quick_check=ok`, zero candidate
  dependents, zero old-key hits in live/configured `wg0`, active sync timers and
  all four public health endpoints green. Backend tests: 102 passed.
- Source hashes:
  - `main.py`: `94E3879A429CF618CAC02817D2199736B9249BAED994E586222C63E673B1295E`;
  - state sync: `BC1A55F94913EEA3759ABC4A058A3FE1F75932B9BBD576F2C2FF906CDF2F6457`.
- Cleanup backups:
  - Timeweb: `/root/greenvpn-agent-user-cleanup-backups/20260718T184419Z-timeweb`;
  - RUVDS Moscow: `/root/greenvpn-agent-user-cleanup-backups/20260718T184357Z-ruvds`.
- Backend deployment rollback:
  - production Timeweb: `/root/greenvpn-public-product-backups/20260718T184055Z-timeweb-0.9.124-admin-cleanup.1`;
  - production RUVDS: `/root/greenvpn-public-product-backups/20260718T184000Z-ruvds-0.9.124-admin-cleanup.1`;
  - paid-beta Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T184108Z-account-delete-complete-20260718-r29`;
  - paid-beta RUVDS: `/root/greenvpn-paid-beta-backend-backups/20260718T184022Z-account-delete-complete-20260718-r29`.

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
- Backend: `0.9.140-account-restore.1` on both RU control planes.
- Android: `0.3.13+2026072604`, package `pro.greenvpn.app`, SHA-256
  `C296936053773BFCF8F8BB9E9A1CD2267A669832FCD451112F9DC4429B8C1629`.
- Windows: `0.3.13+2604`, mandatory, unsigned, SHA-256
  `4BBF8334D528780DE9AB36CDEF21D60010EC0E8EA0FBBA17753C6828A304CF30`.
- Android and Windows updates are mandatory on Timeweb and RUVDS Moscow; all
  stable manifests report `required=true` and `fileReady=true`.
- Authentication starts with an automatic guest profile. Email confirmation
  is required only before payment or for recovery; public phone/SMS login is
  absent.
- Public catalog contains only stable client-compatible endpoints. Server/provider
  implementation details are not shown in the client.
- Both production control planes publish the same three physical stable routes;
  Android groups them into `Нидерланды` and `Лондон` plus `Авто`.
- Login, bootstrap, catalog, downloads, legal routes and update manifests are
  available through primary and fallback Russian ingress.

## Isolated paid-beta contour

- Paths remain isolated at `/paid-beta` and `/paid-beta-api`.
- Both paid-beta control planes currently report backend
  `0.9.140-account-restore.1`.
- Both SQLite databases pass `PRAGMA quick_check`.
- The public-product client marker permits the final public candidate to create
  a 249 RUB order for accounts previously enrolled in the paid-beta cohort;
  unmarked legacy clients remain rejected.
- Android test release: `0.3.13+2026072604`, package
  `pro.greenvpn.app.rc`, side-by-side with stable, SHA-256
  `82772195710B468E0CF45B468D0AB36B95365A8C8541B47098951B44413BBEBA`.
- Windows candidate: `0.3.13+2604`, SHA-256
  `6E4A33C902FE47FD9B14173B12426F25C9F1F601D6CA94321EDC883D5EF0A507`.
  It is published on both RU nodes, technically tested, unsigned and optional.
- Product model: automatic guest start, trial 3 days and 249/649/1099 RUB for
  30/90/180 days. Paid-beta free tier is enabled with quota enforcement
  disabled and a 10 Mbit/s configured speed. Rewarded ads and the disconnect
  timer are disabled. Auto-renew requires explicit payment-method consent.
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

- Public surface probe: 31/31 targets green after the final release publication.
- Backend tests: 122 passed.
- `pip-audit`: no known vulnerabilities.
- `flutter analyze`: no issues.
- Flutter tests: 34 passed and 2 public-only tests skipped by design.
- Android application unit-test task and lint: successful.
- Release gate: 0 warnings, 0 errors.
- Secret scan: tracked, untracked and complete Git history passed.
- Remaining build warnings are in third-party Pub packages (`file_picker` and
  `yandex_mobileads`), not project source.

## Restore points

- Backend 0.9.129 site-quality production deployment directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260719T141823Z-timeweb-0.9.129-site-quality.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260719T141622Z-ruvds-0.9.129-site-quality.1`.
- Backend 0.9.129 production deployment directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260719T020158Z-timeweb-0.9.129-final-audit.5`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260719T020119Z-ruvds-0.9.129-final-audit.5`.
- Backend 0.9.129 paid-beta deployment directories:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260719T020213Z-backend-final-audit-20260719-r5`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260719T020132Z-backend-final-audit-20260719-r5`.
- Operational-retention installation directories:
  - Timeweb: `/root/greenvpn-operational-retention-backups/20260719T020204Z`;
  - RUVDS Moscow: `/root/greenvpn-operational-retention-backups/20260719T020123Z`.
- Android 0.3.7 online rollback directories:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260719T013304Z-timeweb-0.3.7-2026071902`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260719T013212Z-ruvds-0.3.7-2026071902`.
- Windows 0.3.6 release-state rollback directories:
  - Timeweb: `/root/greenvpn-windows-release-backups/20260719T014119Z-timeweb-0.3.6-1808`;
  - RUVDS Moscow: `/root/greenvpn-windows-release-backups/20260719T014044Z-ruvds-0.3.6-1808`.
- Android 0.3.6 online rollback directories:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260718T170717Z-timeweb-0.3.6-2026071802`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260718T170502Z-ruvds-0.3.6-2026071802`.
- Backend 0.9.123 production deployment backup directories:
  - Timeweb: `/root/greenvpn-public-product-backups/20260718T165718Z-timeweb-0.9.123-ads.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260718T165626Z-ruvds-0.9.123-ads.1`.
- Backend 0.9.123 paid-beta deployment backup directories:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260718T165737Z-paid-beta-backend-ad-min-version-20260718-r28`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260718T165631Z-paid-beta-backend-ad-min-version-20260718-r28`.

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
2. On an owner-controlled Windows PC, confirm the visible `0.3.12` guest screen
   and explicitly approve one real connect/disconnect tunnel transition. The
   exact installer, payload and service are already installed and verified.
3. Before buying traffic for paid conversion, complete one owner-driven
   payment journey: guest start, real email code, YooKassa payment, receipt,
   entitlement on both platforms and refund/cancellation handling. Automation
   must not enter the OTP or approve the payment.
4. Supply the Telegram monitoring bot token and destination chat id and perform
   one alert-delivery smoke.
5. Advertising remains an optional later monetization project, not a launch
   dependency. Keep it disabled until a provider gives written approval for
   the exact VPN/WebView2 rewarded flow, payout terms are usable in Russia and
   a real isolated callback smoke succeeds.

Do not perform a real payment, enter SMS/bank codes or accept legal terms on
behalf of the owner.
