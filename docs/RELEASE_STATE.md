# Green VPN Release State

Updated: 2026-07-13.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.105` |
| Fallback API | RUVDS Moscow, backend `0.9.105` |
| Android | `0.2.44+2026070504` |
| Android SHA-256 | `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F` |
| Windows SHA-256 | `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15` |
| Ads/session timer | disabled |

Stable remains the rollback baseline until the candidate launch gates pass.

## Paid Public Candidate

| Component | Version/state |
| --- | --- |
| Primary/fallback backend | `0.9.116-active-active.3` |
| Server release | `paid-beta-backend-active-active-20260713-r22` |
| Android | `0.3.0-paid-beta.6`, package `pro.greenvpn.app.beta` |
| Windows | `0.3.0-paid-beta.11`, unsigned |
| Windows SHA-256 | `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32` |
| Plans | trial 3 days; 249/649/1099 RUB for 30/90/180 days |
| Auto-renew | implemented opt-out; provider approval pending |
| Billing writer | Timeweb only |
| DB replication | active-active state merge with tombstones |

The candidate is isolated at `/paid-beta` and `/paid-beta-api`. It is not a
closed-first-20 product anymore, but those paths remain the safe staging contour
until public promotion.

## Verified

- Both RU control planes run the identical r22 backend bundle and pass health,
  schema and SQLite quick-check.
- Production and candidate sync timers are active. Latest explicit production
  cycles on both nodes: zero inserts/updates, zero conflicts/errors.
- Public site, legal pages, downloads, manifests and all three API surfaces pass
  the independent 31-target probe.
- Login/bootstrap/config failover, session persistence, Android background and
  custom per-app routing were physically proven.
- Windows side-by-side install, reboot persistence, VPN/DNS transition,
  competing-VPN restoration, uninstall recovery and clean reinstall were proven.
- Android/Flutter/backend/native tests, analyzer, dependency audit, release gate
  and full Git-history secret scan are green.
- Stable catalog exposes only stable transports. Five anti-blocking previews are
  hidden and isolated to NL2.

## Not Yet Launchable

1. YooKassa recurring bank-card access is still under external review.
2. A real 249 RUB save-method and unlink smoke must pass after approval.
3. The Windows installer requires Authenticode signing before mandatory rollout.

No code or server defect currently blocks those three external gates.

## Rollback

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
