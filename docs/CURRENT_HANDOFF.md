# Green VPN Current Handoff

Last updated: 2026-07-10.

## Hard rules

- Start with `git status --short` and read this file plus `PAID_BETA_EXECUTION_PLAN_2026_07_10_RU.md`.
- Never print or commit API keys, passwords, provider tokens, payment credentials, private keys, admin tokens or full invite codes.
- Do not touch Friendly Linnet `5.129.237.163`.
- Production stable, main site and public downloads stay frozen until explicit owner approval.
- Paid beta work goes only to the isolated `/paid-beta` and `/paid-beta-api` contour.
- Do not enable ads, forced disconnect timer or auto-renew in paid beta.
- Do not publish beta links/codes to a cold audience before the owner gate.

## Repository

- Root: `C:\Users\gekto\projects\bluevpn`.
- Branch: `green-vpn-paid-beta-20260710`.
- Stable tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Stable checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\pre_paid_beta_20260710_103722`.
- Server stable snapshots: `/root/greenvpn-pre-paid-beta-20260710T103821`.
- Current paid beta plan: `docs/PAID_BETA_EXECUTION_PLAN_2026_07_10_RU.md`.

## Frozen production stable

- Site: `https://greenvpn.pro/`.
- API: `https://api.greenvpn.pro/`, backend `0.9.105`.
- Android SHA-256: `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Windows SHA-256: `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Production runs on Timeweb Moscow `72.56.32.197` with RUVDS Moscow `176.113.81.35` fallback and 30-second critical-state sync.
- Stable files/hashes remained unchanged throughout paid beta deployment and ops work.

## Isolated paid beta

- Primary API/site:
  - `https://api.greenvpn.pro/paid-beta-api`;
  - `https://greenvpn.pro/paid-beta/`.
- Fallback API/site:
  - `https://176-113-81-35.sslip.io/paid-beta-api`;
  - `https://176-113-81-35.sslip.io/paid-beta/`.
- Backend: `0.9.106-paid-beta.2`, service `greenvpn-paid-beta.service`, bind only `127.0.0.1:8010`.
- DB: `/opt/bluevpn-paid-beta/data/bluevpn.db`; beta sync every 10 seconds.
- Probe: `greenvpn-paid-beta-service-probe.timer` on both control-plane nodes, every 300 seconds.
- Marker/channel: `green-vpn-paid-beta-v1` / `paid-beta`.
- Model: 3-day Trial, first period 149 RUB by personal invite, then 299 RUB/30 days manually, 2 devices, no ads, no auto-renew.
- SQLite caveat: primary-normal/fallback-only for writes; no mass launch before transactional storage/write authority decision.

## Paid beta artifacts

- Android: `C:\BlueVPN_Builds\paid_beta_20260710_v2\GreenVPN_Android_0.3.0-paid-beta.2_2026071002.apk`.
- Android SHA-256: `29252A8AE44BA4487363E669A0ED31DDAC159289A49254EBBED34F123D20AB50`.
- Windows: `C:\BlueVPN_Builds\paid_beta_20260710_v2\GreenVPN_Setup_0.3.0-paid-beta.2.exe`.
- Windows SHA-256: `41F96CB95118507AACA861721F83B2972CF419E2F10BA2FCF38CB73800988332`.
- Windows Authenticode: `NotSigned`.
- Approved bundle: `C:\BlueVPN_Builds\paid_beta_20260710_v2\paid-beta-0.3.0-paid-beta.2-2026071002-r2.tar.gz`.
- Bundle SHA-256: `440671161C710AD6BA7A47D4A5DC77CB96D3451F9FF26E3C233EF58853295B17`.
- r1 is forensic only and must not be used as rollback because of the fixed managed-peer cleanup bug.

## Verified

- 26 backend/DB-sync/package tests pass.
- Release gate passes with 0 warnings and 0 errors.
- Stateful auth/invite/trial/quote/bootstrap/config/fallback/cleanup smoke passed.
- Timeweb beta outage selected RUVDS beta fallback while production stayed healthy.
- All beta downloads were fetched through both HTTPS routes and matched expected SHA.
- Both beta probes see all three public VPN endpoints as healthy; both beta API health targets are green.
- Beta staging and temporary seed copies were removed; live beta env contains one assignment per key.

## Owner gate: next action

Do not create/send the 20 invite codes yet. The owner must:

1. Install and smoke Android beta on a real phone.
2. Install and smoke Windows beta on a real PC, including reboot/uninstall/network recovery.
3. Make one real 149 RUB YooKassa payment and verify activation, polling and refund/cancel handling.
4. Accept or legally review beta terms/privacy.

Then run `scripts/ops/create_paid_beta_first20_package.py` following `docs/PAID_BETA_FIRST20_RUNBOOK_2026_07_10_RU.md`.

## Separate production decisions

- Delete unreachable hidden KZ test VPS `8360589` at 611 RUB/month: recommended, owner approval required.
- Clean old London recovery artifacts occupying about 12 GB: recommended, owner approval required.
- Retire legacy NL1 nginx/certbot and disable/fix unused NL2 dnsmasq: owner approval required.
- Review support report for user `34`; eight older reports are likely resolved historical tests but were not auto-closed.

Full evidence: `docs/PAID_BETA_OPS_AUDIT_2026_07_10_RU.md`.
