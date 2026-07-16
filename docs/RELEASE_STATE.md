# Green VPN Release State

Updated: 2026-07-16.

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
| Primary/fallback backend | `0.9.117-public-client.1` |
| Server release | `paid-beta-backend-public-client-20260716-r23` |
| Android | `0.3.0-paid-beta.6`, package `pro.greenvpn.app.beta` |
| Windows | `0.3.0-paid-beta.11`, unsigned |
| Windows SHA-256 | `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32` |
| Plans | trial 3 days; 249/649/1099 RUB for 30/90/180 days |
| Auto-renew | recurring card binding approved; real save-method and unlink smoke passed on both control planes |
| Billing writer | Timeweb only |
| DB replication | active-active state merge with tombstones |

The candidate is isolated at `/paid-beta` and `/paid-beta-api`. It is not a
closed-first-20 product anymore, but those paths remain the safe staging contour
until public promotion.

## Final Product Candidate, Local Only

| Component | Version/state |
| --- | --- |
| Customer location model | one row per country; `Авто / Нидерланды / Англия`; physical routes hidden |
| Latency model | every picker row, including `Авто`, shows `N мс`; missing measurement becomes `0 мс` |
| Source checkpoint | `ceec7aa`, clean reproducible build |
| Android | `0.3.0+2026071603`, package `pro.greenvpn.app.finalcandidate`, debug signed |
| Android SHA-256 | `BA6BD7CD79A211853FCC0377E904174BF81FD8ECBB9472785FA8DB5F8FDE22D7` |
| Windows ZIP | `0.3.0+1603`, four protected fallback engines plus stable tunnel, unsigned |
| Windows ZIP SHA-256 | `04D2AB4AD84F9B63641590BDFEE2600C702E79DEC29224B1B4E84A9B17F1FF37` |
| YooKassa | real 249 RUB payment, saved-method verification and unlink smoke complete |
| London | renewal paid; provider restore is pending after an overdue `initializing` state; England stays absent until smoke tests pass |

This checkpoint is a verified release candidate, not a published production
release. The public site and forced-update manifests still point to the older
stable artifacts.

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
- Public-product auto-renew UI has 29 passing Flutter tests. Physical Android 9
  QA confirms one Settings entry, a dedicated card/auto-renew page, no cancel
  action in Tariff, and no layout overlap.
- The final Android picker was physically rechecked on Samsung Android 9:
  `Авто` and `Нидерланды` were the only rows, both displayed live numeric
  latency, selecting a location persisted it, and the phone was restored to
  `Авто` with no active VPN agent.
- Stable catalog exposes only stable transports. Five anti-blocking previews are
  hidden and isolated to NL2.

## Not Yet Launchable

1. The Windows installer requires Authenticode signing before mandatory rollout.
2. RUVDS must unlock the already-paid London VPS; it then needs preserved-state
   recovery, data-plane validation and publication as the single `Англия` row.

No confirmed code or RU control-plane defect currently blocks those owner and
provider gates.

## Rollback

- Current final-candidate source commit:
  `ceec7aad27ab0399d3ec93f096bbae83c5187ee6`.
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
