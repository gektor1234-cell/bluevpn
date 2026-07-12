# Green VPN Current Handoff

Last updated: 2026-07-12.

## Hard rules

- Start with `git status --short`, then read this file and `PAID_BETA_EXECUTION_PLAN_2026_07_10_RU.md`.
- Never print or commit API keys, passwords, provider/payment credentials, private keys, admin tokens, OTP values or full invite codes.
- Do not touch Friendly Linnet `5.129.237.163`.
- Production stable, the main site and public downloads remain frozen until explicit owner approval.
- Paid beta work goes only to `/paid-beta` and `/paid-beta-api`.
- Ads and forced disconnect timer stay disabled.
- The public-product candidate uses opt-out auto-renew; the executor is enabled only on Timeweb beta and disabled on RUVDS.
- The former first-20 invite launch is superseded by the public-product candidate. Do not generate old invite packages unless explicitly requested.

## Repository and checkpoints

- Root: `C:\Users\gekto\projects\bluevpn`.
- Stable/public-product base branch: `green-vpn-paid-beta-20260710`.
- Active isolated transport branch: `green-vpn-transport-canary-20260711`.
- Stable tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Stable local checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\pre_paid_beta_20260710_103722`.
- Stable server snapshots: `/root/greenvpn-pre-paid-beta-20260710T103821`.
- Previous beta tag/checkpoint: `greenvpn-paid-beta-technical-ready-20260710` and `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_technical_ready_20260710T110614Z`.
- Final owner-gate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_owner_gate_ready_20260710`, `/root/greenvpn-paid-beta-owner-gate-ready-20260710`, `greenvpn-paid-beta-owner-gate-ready-20260710`.
- Windows candidate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_candidate_ready_20260710`, `greenvpn-paid-beta-windows-candidate-ready-20260710`.
- Windows owner-gate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_owner_gate_passed_20260711`, `greenvpn-paid-beta-windows-owner-gate-passed-20260711`.
- Billing guard checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_billing_single_writer_20260711`, `greenvpn-paid-beta-billing-single-writer-20260711`.
- Real-payment/sync checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_real_payment_sync_ready_20260711`, `greenvpn-paid-beta-real-payment-sync-ready-20260711`.
- Public billing-guard checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\public_candidate_billing_guard_20260711`, `greenvpn-public-candidate-billing-guard-20260711`.
- Five-stage preview checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\five_stage_transport_preview_20260712`; latest proven code commit before this documentation update is `5ed6e8e`.
- Private Windows session/config recovery copy: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_0.3.0-paid-beta.10_private_state_20260711`; ACL is limited to the owner, SYSTEM and Administrators. Never publish or commit it.

## Isolated transport canary foundation

- Based on tag `greenvpn-public-candidate-billing-guard-20260711`; production, paid beta, site and downloads were not deployed or changed.
- Current client explicitly advertises only `wireguard_udp`; old clients without the capability field also default to `wireguard_udp` only.
- Backend performs fail-closed protocol negotiation and removes non-negotiated endpoints before selection. An empty negotiation returns `503 no_available_vpn_nodes` instead of silently restoring the builtin endpoint.
- Rollout stages are explicit: `wireguard_udp=public`; existing guarded alternatives are `canary_prepared` or `research`.
- Canary apply/rollback is refused on all known production/control-plane hosts and Friendly Linnet. The only owner-approved exception is the exact NL2 AmneziaWG unit/config/IP tuple; it cannot enable another transport or touch another host.
- AmneziaWG uses a oneshot systemd unit; readiness validates root-only non-symlink config, required AWG2 fields, unique nonzero H1-H4 and a canary peer without printing secrets.
- AmneziaWG 2 canary is active on Netherlands #2 `5.129.216.42` as `awgcanary0` UDP/1443. Existing `wg0` UDP/443 stayed active and its config matches the pre-change snapshot byte-for-byte.
- Hysteria2 `app/v2.9.3` canary is active on the same NL2 as isolated service `greenvpn-hysteria2-canary` UDP/2443. Official Linux binary SHA-256 matches GitHub release digest; trusted ACME TLS, password auth and Salamander are enabled. Windows and Android previews use Hysteria only in MIT SOCKS mode plus HEV `2.14.4` TUN; Hysteria's GPL-linked built-in TUN is explicitly excluded. Windows physical proof passed with protected paths, non-recursive routes, watchdog cleanup and exact restoration. Android physical proof passed on Samsung SM-A226B with NL2 egress, production/both paid-beta APIs and YouTube `200`, bidirectional counters, fail-closed engine-kill cleanup, clean final `down` and plaintext-config removal.
- Real isolated WSL smoke passed handshake, tunnel IP and egress to `1.1.1.1`; rollback, interface/NAT removal, reinstall and post-reinstall smoke also passed. Public catalog still exposes only `wireguard_udp`.
- NL2 pre-change snapshot: `/root/greenvpn-awg2-prechange/20260711T171122Z`; local root-only client checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_awg2_20260711`.
- Detailed live result: `docs/AMNEZIAWG2_NL2_CANARY_2026_07_11_RU.md`.
- Android transport preview is physically proven on Samsung SM-A226B: separate `10.202.0.2`, NL2 egress `5.129.216.42`, YouTube playback, Recents swipe survival, session persistence and accurate selected-server restoration.
- Paid-beta control planes run isolated r19 backend `0.9.113-transport-preview.7`. A capable preview receives five hidden canaries in strict order: AWG2, Hysteria2, VLESS REALITY/XHTTP, Naive HTTPS and dnstt. Legacy/stable clients cannot negotiate them. Production remains `0.9.105`.
- Android five-stage preview artifact: `C:\BlueVPN_Builds\android_transport_preview_20260712_cascade_r19\GreenVPN_Android_five_stage_preview_0.2.45_2026071204.apk`, size `140,139,681`, SHA-256 `984CBEF0EB4C0A88A4D982AC63C1A1DFB3F597CF785F51D639E6DEE05C1FEFD1`.
- Detailed Android result and rollback: `docs/ANDROID_AWG2_PREVIEW_2026_07_11_RU.md`.
- Windows transport preview remains isolated from stable. The protected `%ProgramFiles%` migration removed the unsafe legacy path and broad ProgramData ACLs. AWG2 full-tunnel proof passed after the Windows peer received unique `10.202.0.3/32`; Hysteria2 full-tunnel and watchdog cleanup also passed. Both tests proved NL2 egress, production/paid-beta APIs, YouTube, endpoint route isolation and exact restoration of `device20_full` with egress `5.129.237.163`. Artifact SHA-256 is `2B8A4D0EB2DD78A57CB979012A5881ABB0F2A4D6A18E09D8E858053DF1B9D6A2`; manifest has 32 files and 0 mismatches.
- Detailed Windows preview state and rollback: `docs/WINDOWS_AWG2_PREVIEW_2026_07_12_RU.md`.
- VLESS REALITY/XHTTP is active only as an NL2 TCP/443 canary using Xray-core `v26.7.11`; WireGuard UDP/443, AWG2 and Hysteria2 remain active and unchanged. The bootstrap performs a real data-plane smoke and keeps all identity/key/path material root-only. Windows `transport-preview.2` packages hash-pinned Xray plus HEV, binds Xray to the physical adapter, filters private/multicast and UDP/443 noise, and fail-closes through a dedicated watchdog. Physical proof passed direct ISP REALITY, full TUN NL2 egress, DNS/TCP, four HTTP `200` probes, engine-kill cleanup and exact restoration of `device20_full`/`5.129.237.163`.
- Windows VLESS artifact: `C:\BlueVPN_Builds\windows_transport_preview_20260712_vless\GreenVPN_Windows_Transport_Preview_0.3.0-preview2.zip`, size `41,606,258`, SHA-256 `F6615248AE756477DFAE40153B0D819DFBAC17AC47C734B475D7B7DD2E944BCA`; manifest has 39 files. Full-tunnel report SHA-256: `7B83B1C75EC15B7675688207D06E478B960AE0C0981C995E4763FD05D7B9037A`.
- Detailed VLESS Windows state and rollback: `docs/WINDOWS_VLESS_REALITY_PREVIEW_2026_07_12_RU.md`.
- Android VLESS REALITY/XHTTP preview is physically proven on Samsung SM-A226B. Full TUN reached NL2 egress `5.129.216.42`; production and both paid-beta APIs returned `200`, YouTube returned `204`, one exact Xray child carried bidirectional traffic, watchdog fail-closed cleanup passed, and reconnect returned to `up`. A separate background/Home/YouTube relaunch check kept the tunnel and egress alive. Preview was then shut down and official `bluevpn-phone-3` restored as `VALIDATED` with stable egress `5.129.237.163`.
- Android VLESS artifact: `C:\BlueVPN_Builds\android_transport_preview_20260712_vless\GreenVPN_Android_VLESS_REALITY_Transport_Preview_0.2.45-preview2_debug.apk`, size `147,691,009`, SHA-256 `7C10F16B590A9DC9003E3050E5DD1C09BEB7EC39DD81DBF93EE4B0ED36D46DB4`. Full physical report SHA-256: `C3A9C3B236D4FDF96143D9F707518DB13B06C1917A89E4A106F7FF5AEDB9836D`.
- Detailed Android VLESS state and rollback: `docs/ANDROID_VLESS_REALITY_PREVIEW_2026_07_12_RU.md`.
- Naive HTTPS is active only as an out-of-catalog NL2 server canary on TCP/8443. Caddy `v2.11.4`, forwardproxy exact commit `d62c80d3dd2c`, and NaiveProxy `v150.0.7871.63-1` are pinned; TLS camouflage verifies normally with HTTP `404`, real SOCKS smoke returns NL2 egress `5.129.216.42`, UDP/8443 is absent, and WireGuard/AWG2/Hysteria2/VLESS remain active. Credentials are root-only and never printed. Windows client and TCP/443 SNI sharing are not yet enabled.
- Android Naive HTTPS preview is physically proven on Samsung SM-A226B. HEV mapdns avoids UDP DNS, full TUN reached NL2 egress `5.129.216.42`, production/both paid-beta APIs returned `200`, YouTube returned `204`, watchdog/reconnect and plaintext cleanup passed, and Home/YouTube/relaunch stayed `up`. APK SHA-256: `DB2439502B81A471C4D53E53C36689DD6726D5599207912EBCD8B1BA870A630E`; full report SHA-256: `E2217CE98D011CEBC0729E45B578DACEC88B66D8EA4213613D9E02931BDB5521`. Windows client and TCP/443 SNI sharing are not yet enabled.
- Naive/AnyTLS license decision, readiness and rollback: `docs/NAIVE_HTTPS_NL2_CANARY_2026_07_12_RU.md`.
- Preview-only route selection now applies a bounded in-memory failure cooldown of `1/3/10/30` minutes. Automatic route observations are accepted only for automation-eligible, verified tunnel/proxy data-plane probes; ordinary control-plane health cannot unlock or promote a transport. Stable flags remain off.
- Android Hysteria2 preview artifact: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_awg2_hysteria2_transport_preview5_build2026070515_debug.apk`, size `117,990,976`, SHA-256 `6D84E4F89296DE095133025BE3E4333F232DDC53A022FABD625F5A7E8F98D84E`. Exact official Hysteria hashes, three HEV/bridge ABIs, license assets, zip alignment and signature pass the APK verifier. A separate stable build has the preview flag `false` and contains no Hysteria engine/service/native payload.
- Detailed Android Hysteria2 state and rollback: `docs/ANDROID_HYSTERIA2_PREVIEW_2026_07_12_RU.md`.
- Verification: 28 transport-backend tests, 33 paid-beta backend tests, 11 Flutter tests and 3 native Quick Settings cascade tests pass. The Android package compiles, its dnstt/APK/signature verifier passes, and the physical device contract probe returned `10/10` valid config responses across both control planes. The physical Quick Settings proof selected AWG2 first and Hysteria2 after AWG2 cooldown, with a YouTube probe required before success. `flutter analyze` remains at the pre-existing baseline of 184 lint/info items with no increase; release gate is `0 warnings`, `0 errors`.
- Detailed operator runbook: `docs/TRANSPORT_CANARY_ROLLOUT_2026_07_11_RU.md`.

## Frozen production stable

- Site/API: `https://greenvpn.pro/` and `https://api.greenvpn.pro/`.
- Backend: `0.9.105`.
- Android: `0.2.44`, build `2026070504`, SHA-256 `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Windows SHA-256: `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Timeweb Moscow `72.56.32.197` is primary; RUVDS Moscow `176.113.81.35` is fallback.
- Production artifacts, DB and `0.9.105` stayed unchanged during all beta work.

## Isolated paid beta

- Primary API/site: `https://api.greenvpn.pro/paid-beta-api`, `https://greenvpn.pro/paid-beta/`.
- Fallback API/site: `https://176-113-81-35.sslip.io/paid-beta-api`, `https://176-113-81-35.sslip.io/paid-beta/`.
- Current server release on both nodes: `paid-beta-0.3.0-paid-beta.6-2026071201-r19-preview-probe-contract`.
- Backend: `0.9.113-transport-preview.7`, service `greenvpn-paid-beta.service`, bind `127.0.0.1:8010` only.
- DB: `/opt/bluevpn-paid-beta/data/bluevpn.db`; sync timer every 10 seconds.
- Probe: `greenvpn-paid-beta-service-probe.timer`, every 300 seconds on both nodes.
- Marker/channel/cohort: `green-vpn-paid-beta-v1` / `paid-beta` / `paid_beta_v1`.
- Model: Trial 3 days; 249/649/1099 RUB for 30/90/180 days; no ads/timer; opt-out auto-renew.
- Current state on each node: owner data retained, the earlier 149 RUB payment remains active, the rejected 249 RUB order is canceled, and no empty pending order remains.
- SQLite is suitable for the first 20 only in primary-normal/fallback-only mode. Deletes are not tombstone-replicated, so operational test cleanup must be performed on both nodes with sync paused.

## Paid beta artifacts

- Android: `C:\BlueVPN_Builds\paid_beta_20260711_v17\GreenVPN_Android_0.3.0-paid-beta.6_2026071106.apk`.
- Android package/label: `pro.greenvpn.app.beta` / `Green VPN Beta`.
- Android SHA-256: `5A341F48BA3C902F872D6D5984FC671F215B001654BBE55617886C262232624E`.
- Android signer SHA-256: `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.
- Local Windows side-by-side candidate: `C:\BlueVPN_Builds\paid_beta_20260711_v17\GreenVPN_Beta_Setup_0.3.0-paid-beta.11.exe`.
- Local Windows SHA-256: `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32`; size `12,822,528`; Authenticode `NotSigned`.
- Server-published Windows on both beta nodes: `.11`, SHA-256 `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32`, `required=false`.
- Final bundle: `C:\BlueVPN_Builds\paid_beta_20260711_v17\paid-beta-0.3.0-paid-beta.6-2026071106-r12.tar.gz`.
- Bundle SHA-256: `A38C8C08825042386A17230C584A0FA4C472400367FC78B277E083B947678714`.
- Android `.2/.3/.4` and server revisions before `r5` are forensic/superseded, not approved rollback targets.

## Verified

- 41 backend tests and 6 Flutter tests pass; analyzer returns code 0 with only the pre-existing lint backlog.
- Stateful auth/marker/invite/trial/149/299/bootstrap/config/fallback/cleanup smoke passed.
- Both local/public beta health return `0.9.106-paid-beta.9`; production health returns `0.9.105`.
- Site readiness is 8/8. YooKassa key was reissued, installed in root-only production/beta env on both control-plane nodes and validated with provider HTTP 200.
- Update API returns Android `.5` and Windows `.10`; RUVDS returns its own fallback download URLs. Both downloaded Windows files match the approved SHA-256.
- Real Samsung SM-A226B Android 13: login, invite, VPN, YouTube playback, recents swipe/reopen, disconnect and Timeweb outage fallback passed.
- Stable Android and beta coexist; stable remains `pro.greenvpn.app`, beta is `pro.greenvpn.app.beta`.
- Android custom-app picker lists launchable apps with search. Active add/remove of Chrome rebuilt `tun0`; VPN UID list contained Chrome only while selected. Chrome, MAX and all unselected apps route directly.
- Device was restored after testing: Chrome removed from VPN list, beta VPN off, `stay_on_while_plugged_in=0`.
- Windows `.10` static gate passed: real EXE extraction, 18 payload files, isolated beta identity, 0 stable identifier matches, 0 PowerShell parse errors and 0 Defender detections.
- Windows `.10` was installed side-by-side on the real owner PC. Reboot gate passed with preserved session, successful DPAPI migration, encrypted session at rest, automatic full-tunnel kill switch, beta service/port autostart and Amnezia restoration.
- Windows `.10` physical transition smoke passed: network checker `10/10`, `productionReady=true`, two direct outside-tunnel DNS probes blocked, fresh handshake and traffic, beta APIs `200/200`, YouTube `204`, Green tunnel cleaned and Amnezia restored. Report SHA-256: `F5D4FB2DAC09216FC8116CF4EC2E5B3FD0E633F5F3D96E445FA93C96CD2D08C0`.
- Windows `.10` destructive uninstall/network-recovery and clean reinstall passed. All beta processes/services/adapter/files/autostart were removed, Amnezia and network remained healthy, then the same artifact restored the encrypted session and `/0` managed config. Report SHA-256: uninstall `0CD95C290ABFAE44137A36C90772C1F41C4462BF66D662181DA6A70AAB40BBBB`; reinstall `37D4491569DB669230B8E7DC7C0753A273E3C2FF70C7A5201F063CCE1FB46E07`.
- Beta `r6` deployment passed on Timeweb and RUVDS. Beta/production/sync/probe services are active, both DBs have `quick_check=ok`, temporary staging was removed and rollback backups were created. Deployment report SHA-256: `21B8EB7FE1CE94DB7A1616A1DA02A15958C9E8A1B31CCCD4F5D10A1C42E718BE`.
- The first real 149 RUB checkout attempt exposed two issues before any payment was created: YooKassa credentials were invalid and independent SQLite writers created conflicting empty pending orders. No provider payment ID, payment URL or charge existed.
- Both empty orders and duplicate `order_created` events were removed with sync paused after root-only DB backups; the invite is eligible again and both DBs pass `quick_check=ok`.
- Beta `r7` makes Timeweb the only paid-beta billing writer. RUVDS still serves auth/VPN/config failover but rejects billing mutation before touching SQLite. 29 tests and release gate 0/0 pass. Report SHA-256: `8241308F02FA3CFBDB523C7B7052D89B802CFB3868CFF72D96259D595659CD50`.
- Deployed RUVDS integration probe returned `503 paid_beta_billing_primary_required` with billing/order-event counts unchanged at zero. Report SHA-256: `F5E06CEFD4C3A3B47C09010CC86D59838668D39424CFDE03D03C928553DA3F45`.
- One real 149 RUB payment succeeded and activated `paid_beta_30d` through 2026-08-10. Provider state is `succeeded`, paid and refundable; no actual refund was issued and auto-renew remains disabled.
- YooKassa HTTP notifications are configured for the production webhook endpoint, including payment success/cancel, capture waiting, payment-method activation and refund success.
- Server `r8` fixes mixed SQLite timestamp formats by normalizing them to UTC. Both sync timers run with 0 conflicts/errors; the three critical row hashes are identical on both nodes.
- With Timeweb beta stopped, public RUVDS returned HTTP 200 for subscription and bootstrap, reported the paid plan, allowed VPN connection and required no ad. Timeweb was restored immediately after the test.
- YooKassa rejects `save_payment_method=true` because recurring payments are not enabled for the live shop. Backend `.9` returns a safe actionable error, cancels an empty rejected order, and the client no longer masks it with RUVDS fallback.
- Beta `r12` is active on both control-plane nodes. Both SQLite databases pass `quick_check`, have zero pending orders, and sync timers are active.
- Auto-renew unlink evidence is live at `https://greenvpn.pro/paid-beta/yookassa-review-20260711/`. A YooKassa manager started recurring-payment review on 2026-07-11; expected response is within 1-2 working days, no duplicate ticket should be created.

## Transport preview continuation (2026-07-12)

- Strict preview order is implemented as `AmneziaWG2 -> Hysteria2 -> VLESS REALITY/XHTTP -> Naive HTTPS -> dnstt`, with bounded failure cooldown `1/3/10/30` minutes. Stable flags remain off.
- Both paid-beta control planes expose the same five preview-only rows and issue all five config formats. The Samsung contract probe proved `10/10` responses without exporting credentials or config bodies; latest report SHA-256 is `7540393123545F4CF0F09F567BD7EAF4EB13ADEA3C6031A96B020EE47FA80316`.
- Main UI and Android Quick Settings now use the same dynamic preview catalog and strict cascade. Physical tile proof: AWG2 first, Hysteria2 after AWG2 cooldown, both accepted only after YouTube; report SHA-256 `CBED2FD33B0F20C37FBD67C8BB6546BD2F5B5494953D8878E537C134A1030B8A`. The original tile list was restored and every preview engine ended in `down`.
- Paid-beta probe timers on Timeweb and RUVDS are active; latest oneshot results are `success`, status `0`, observations `posted=true`. Their route signals remain control-plane-only and cannot auto-promote a guarded transport without a trusted egress-verified data-plane probe.
- NL2 services for all five canaries are active. The dnstt direct server data-plane smoke passed with NL2 egress and YouTube, `server_data_plane_ready=true`, stable transports active and no secrets printed. Public DNS delegation for `t.greenvpn.pro` is still absent.
- Android Naive HTTPS preview passed physical watchdog, reconnect, background, relaunch, and YouTube checks; commit `207f11e` is the local checkpoint.
- Windows Naive HTTPS preview is implemented and compiled as `0.3.0-preview3`.
- Its package gate and non-disruptive SOCKS data-plane smoke pass; the latter preserved both route signature and WARP service state.
- Full Windows TUN smoke remains deferred until changing WARP is explicitly allowed.
- The frozen stable/public transport and production catalog remain unchanged.
- Remaining transport gate: add `A tns.greenvpn.pro -> 5.129.216.42` and `NS t.greenvpn.pro -> tns.greenvpn.pro`, wait for propagation, unlock the phone, then run the dnstt physical egress/YouTube/watchdog/reconnect test.

## Owner gate

The remaining launch gate is external:

1. YooKassa enables recurring bank-card payments.
2. Run one real 249 RUB first-payment smoke and verify `payment_method.saved=true`.
3. Disable auto-renew in the app and verify that the saved method link is removed on both control-plane nodes.
4. Only then deploy the public candidate and enable the forced update.

The old first-20 runbook is historical and is not the current launch path.

## Separate production decisions

- Delete unreachable KZ test VPS `8360589` at 611 RUB/month only after owner approval.
- Clean about 12 GB of old London recovery artifacts only after owner approval.
- Retire legacy NL1 nginx/certbot and disable/fix unused NL2 dnsmasq only after owner approval.

Full operational evidence: `docs/PAID_BETA_OPS_AUDIT_2026_07_10_RU.md`.
