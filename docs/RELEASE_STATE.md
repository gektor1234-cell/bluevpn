# Green VPN Release State

Updated: 2026-07-16.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.118-public.1` |
| Fallback API | RUVDS Moscow, backend `0.9.118-public.1` |
| Android | `0.3.2+2026071607`, package `pro.greenvpn.app`, mandatory |
| Android SHA-256 | `6C881410C2B8001BD3BCDA954526B86F8BE77400EE452B11D38A77362E9E936A` |
| Windows SHA-256 | `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15` |
| Ads/session timer | disabled |

Android 0.3.2 is published on Timeweb and RUVDS Moscow. Both stable manifests
have `required=true` and `fileReady=true`; the previous APK is retained in the
root-only deployment backups listed under Rollback.

## Paid Public Candidate

| Component | Version/state |
| --- | --- |
| Primary/fallback backend | `0.9.118-public.1` |
| Android | `0.3.2+2026071607`, package `pro.greenvpn.app.beta`, mandatory |
| Android SHA-256 | `7313A781EC7B1CF834E0C5150FDF055FE5E7DE4B97891ACE419F5056109A0042` |
| Windows | `0.3.0-paid-beta.11`, unsigned |
| Windows SHA-256 | `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32` |
| Plans | trial 3 days; 249/649/1099 RUB for 30/90/180 days |
| Auto-renew | recurring card binding approved; real save-method and unlink smoke passed on both control planes |
| Billing writer | Timeweb only |
| DB replication | active-active state merge with tombstones |

The candidate is isolated at `/paid-beta` and `/paid-beta-api`. It is not a
closed-first-20 product anymore, but those paths remain the safe staging contour
until public promotion.

## Published Android Product Release

| Component | Version/state |
| --- | --- |
| Customer location model | one row per country; `Авто / Нидерланды / Англия`; physical routes hidden |
| Latency model | every picker row, including `Авто`, shows `N мс`; missing measurement becomes `0 мс` |
| Source base | `7b5d192`, release changes recorded in the current branch |
| Android production | `0.3.2+2026071607`, package `pro.greenvpn.app`, release signed |
| Android production SHA-256 | `6C881410C2B8001BD3BCDA954526B86F8BE77400EE452B11D38A77362E9E936A` |
| Android test | `0.3.2+2026071607`, package `pro.greenvpn.app.beta`, release signed |
| Android test SHA-256 | `7313A781EC7B1CF834E0C5150FDF055FE5E7DE4B97891ACE419F5056109A0042` |
| Windows ZIP | `0.3.0+1603`, four protected fallback engines plus stable tunnel, unsigned |
| Windows ZIP SHA-256 | `04D2AB4AD84F9B63641590BDFEE2600C702E79DEC29224B1B4E84A9B17F1FF37` |
| YooKassa | real 249 RUB payment, saved-method verification and unlink smoke complete |
| London | renewal paid; provider restore is pending after an overdue `initializing` state; England stays absent until smoke tests pass |

Production and test APKs are published on both Russian control planes. The
customer-facing stable and paid-beta update manifests force 0.3.2 and all four
public APK aliases are ready.

## Verified

- Both RU control planes run backend `0.9.118-public.1` and pass health,
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
- Public-product auto-renew UI has passing Flutter tests. Physical Android 9
  QA confirms one Settings entry, a dedicated card/auto-renew page, no cancel
  action in Tariff, and no layout overlap.
- The final Android picker was physically rechecked on Samsung Android 9:
  `Авто` and `Нидерланды` were the only rows, both displayed live numeric
  latency, selecting a location persisted it, and the phone was restored to
  `Авто` with no active VPN agent.
- Stable catalog exposes only stable transports. Five anti-blocking previews are
  hidden and isolated to NL2.
- Production and test 0.3.2 were installed side-by-side on Samsung Android 9.
  Both completed a real VPN connect with an Android `CONNECTED` and `VALIDATED`
  network, loaded YouTube, stayed connected after their task was swiped from
  recent apps, restored the live state when reopened, and disconnected cleanly.
- Release optimization keeps the reflected optional tunnel API intact, while
  `wireguard_udp` is always routed through the standard backend and
  `amneziawg` alone uses the optional backend.

## Remaining Launch Gates

1. The Windows installer requires Authenticode signing before mandatory rollout.
2. RUVDS must restore the already-paid London VPS; it then needs preserved-state
   recovery, data-plane validation and publication as the single `Англия` row.

Android is published. No confirmed Android or RU control-plane defect remains;
the outstanding gates are Windows signing and the provider-side London restore.

## Rollback

- Android 0.3.2 deployment backups:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260716T084402Z-timeweb-0.3.2-2026071607`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260716T084727Z-ruvds-0.3.2-2026071607`.
- Each directory contains the previous production/test APK aliases, previous
  environment files and APK checksums with root-only permissions.
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
