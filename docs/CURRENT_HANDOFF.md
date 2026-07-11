# Green VPN Current Handoff

Last updated: 2026-07-11.

## Hard rules

- Start with `git status --short`, then read this file and `PAID_BETA_EXECUTION_PLAN_2026_07_10_RU.md`.
- Never print or commit API keys, passwords, provider/payment credentials, private keys, admin tokens, OTP values or full invite codes.
- Do not touch Friendly Linnet `5.129.237.163`.
- Production stable, the main site and public downloads remain frozen until explicit owner approval.
- Paid beta work goes only to `/paid-beta` and `/paid-beta-api`.
- Ads, forced disconnect timer and auto-renew stay disabled in paid beta.
- Do not create or send the first 20 invite codes before the owner gate.

## Repository and checkpoints

- Root: `C:\Users\gekto\projects\bluevpn`.
- Branch: `green-vpn-paid-beta-20260710`.
- Stable tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Stable local checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\pre_paid_beta_20260710_103722`.
- Stable server snapshots: `/root/greenvpn-pre-paid-beta-20260710T103821`.
- Previous beta tag/checkpoint: `greenvpn-paid-beta-technical-ready-20260710` and `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_technical_ready_20260710T110614Z`.
- Final owner-gate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_owner_gate_ready_20260710`, `/root/greenvpn-paid-beta-owner-gate-ready-20260710`, `greenvpn-paid-beta-owner-gate-ready-20260710`.
- Windows candidate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_candidate_ready_20260710`, `greenvpn-paid-beta-windows-candidate-ready-20260710`.
- Windows owner-gate checkpoint/tag: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_owner_gate_passed_20260711`, `greenvpn-paid-beta-windows-owner-gate-passed-20260711`.
- Private Windows session/config recovery copy: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_windows_0.3.0-paid-beta.10_private_state_20260711`; ACL is limited to the owner, SYSTEM and Administrators. Never publish or commit it.

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
- Current server release on both nodes: `paid-beta-0.3.0-paid-beta.5-2026071005-r6`.
- Backend: `0.9.106-paid-beta.4`, service `greenvpn-paid-beta.service`, bind `127.0.0.1:8010` only.
- DB: `/opt/bluevpn-paid-beta/data/bluevpn.db`; sync timer every 10 seconds.
- Probe: `greenvpn-paid-beta-service-probe.timer`, every 300 seconds on both nodes.
- Marker/channel/cohort: `green-vpn-paid-beta-v1` / `paid-beta` / `paid_beta_v1`.
- Model: Trial 3 days, invited first period 149 RUB, then 299 RUB/30 days manually, 2 devices, no ads/timer/auto-renew.
- Current clean state on each node: owner data only, 1 user/subscription, 2 tokens/devices, 0 billing orders and 0 smoke users.
- SQLite is suitable for the first 20 only in primary-normal/fallback-only mode. Deletes are not tombstone-replicated, so operational test cleanup must be performed on both nodes with sync paused.

## Paid beta artifacts

- Android: `C:\BlueVPN_Builds\paid_beta_20260710_v5\GreenVPN_Android_0.3.0-paid-beta.5_2026071005.apk`.
- Android package/label: `pro.greenvpn.app.beta` / `Green VPN Beta`.
- Android SHA-256: `90E42FB6CE5A06247E620E5DC3302B7C7C86A0F9A8FEBDC523876A622B9C6580`.
- Android signer SHA-256: `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.
- Local Windows side-by-side candidate: `C:\BlueVPN_Builds\paid_beta_20260711_v13\GreenVPN_Beta_Setup_0.3.0-paid-beta.10.exe`.
- Local Windows SHA-256: `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170`; size `12,822,016`; Authenticode `NotSigned`.
- Server-published Windows on both beta nodes: `.10`, SHA-256 `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170`, `required=false`.
- Final bundle: `C:\BlueVPN_Builds\paid_beta_20260711_v14\paid-beta-0.3.0-paid-beta.5-2026071005-r6.tar.gz`.
- Bundle SHA-256: `DA6F1D07AA1DFB6330A08E116F0F0EC0AB223430D7D210359B2ED8520C3139AA`.
- Android `.2/.3/.4` and server revisions before `r5` are forensic/superseded, not approved rollback targets.

## Verified

- 28 backend/DB-sync/first20 tests pass; release gate: 0 warnings, 0 errors.
- Stateful auth/marker/invite/trial/149/299/bootstrap/config/fallback/cleanup smoke passed.
- Both local/public beta health return `0.9.106-paid-beta.4`; production health returns `0.9.105`.
- Site readiness is 8/8 on both nodes; payment config is ready; real payment smoke is intentionally incomplete.
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

## Owner gate

Do not create/send the first 20 codes yet. Remaining owner actions:

1. Make one real 149 RUB YooKassa payment and verify activation polling plus refund/cancel handling.
2. Accept or legally review beta terms/privacy.

After both, follow `docs/PAID_BETA_FIRST20_RUNBOOK_2026_07_10_RU.md`.

## Separate production decisions

- Delete unreachable KZ test VPS `8360589` at 611 RUB/month only after owner approval.
- Clean about 12 GB of old London recovery artifacts only after owner approval.
- Retire legacy NL1 nginx/certbot and disable/fix unused NL2 dnsmasq only after owner approval.

Full operational evidence: `docs/PAID_BETA_OPS_AUDIT_2026_07_10_RU.md`.
