# Green VPN Release State

Updated: 2026-07-16.

## Stable Public

| Component | Version/state |
| --- | --- |
| Main site | `https://greenvpn.pro/`, healthy |
| Primary API | `https://api.greenvpn.pro/`, backend `0.9.119-public.1` |
| Fallback API | RUVDS Moscow, backend `0.9.119-public.1` |
| Android | `0.3.3+2026071608`, package `pro.greenvpn.app`, mandatory |
| Android SHA-256 | `EEC96C8E29DED9151E5A8E8679A41D946BAC76FB41483A5A6DB8609F6C6141B0` |
| Windows SHA-256 | `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15` |
| Ads/session timer | disabled |

Android 0.3.3 is published on Timeweb and RUVDS Moscow. Both stable manifests
have `required=true` and `fileReady=true`; the previous APK is retained in the
root-only deployment backups listed under Rollback.

## Paid Public Candidate

| Component | Version/state |
| --- | --- |
| Primary/fallback backend | `0.9.119-public.1` |
| Android | `0.3.3+2026071608`, package `pro.greenvpn.app.beta`, mandatory |
| Android SHA-256 | `77A81ED9C3A5195E4E2F73C036725E3C501BC6C28C671CC355265CCC1F4985F2` |
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
| Source base | `11b5f54`, Android native-runtime and fallback-config fix |
| Android production | `0.3.3+2026071608`, package `pro.greenvpn.app`, release signed |
| Android production SHA-256 | `EEC96C8E29DED9151E5A8E8679A41D946BAC76FB41483A5A6DB8609F6C6141B0` |
| Android test | `0.3.3+2026071608`, package `pro.greenvpn.app.beta`, release signed |
| Android test SHA-256 | `77A81ED9C3A5195E4E2F73C036725E3C501BC6C28C671CC355265CCC1F4985F2` |
| Windows ZIP | `0.3.0+1603`, four protected fallback engines plus stable tunnel, unsigned |
| Windows ZIP SHA-256 | `04D2AB4AD84F9B63641590BDFEE2600C702E79DEC29224B1B4E84A9B17F1FF37` |
| YooKassa | real 249 RUB payment, saved-method verification and unlink smoke complete |
| London | existing VPS `2584554` restored in place; production and paid-beta catalogs publish one logical `Англия` location |

Production and test APKs are published on both Russian control planes. The
customer-facing stable and paid-beta update manifests force 0.3.3 and all four
public APK aliases are ready.

## Verified

- Both RU control planes run backend `0.9.119-public.1` and pass health,
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
- The final Android picker was physically rechecked on Samsung Android 9 in
  production and test: `Авто`, `Нидерланды` and `Англия` are the only logical
  rows and every row displays numeric latency. Two physical Netherlands nodes
  remain grouped behind one customer location.
- The restored London VPS passed isolated WireGuard data-plane smoke from both
  Russian control planes: handshake, positive RX/TX, matching London egress and
  3/3 production API, Google and YouTube checks. Temporary peers, namespaces,
  firewall rules, forwarding changes and key files were all removed.
- Production Android connected to `Англия`, exposed a `CONNECTED` and
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

## Remaining Launch Gates

1. The Windows installer requires Authenticode signing before mandatory rollout.

Android and the server-side location pool are published. No confirmed Android,
London or Russian control-plane defect remains.

## Rollback

- Android 0.3.3 deployment backups:
  - Timeweb: `/root/greenvpn-apk-release-backups/20260716T184718Z-timeweb-0.3.3-2026071608`;
  - RUVDS Moscow: `/root/greenvpn-apk-release-backups/20260716T184757Z-ruvds-0.3.3-2026071608`.
  They retain the previous APK aliases and environment files with root-only
  permissions.
- Backend 0.9.119 production backups:
  - Timeweb: `/root/greenvpn-public-product-backups/20260716T175852Z-timeweb-0.9.119-public.1`;
  - RUVDS Moscow: `/root/greenvpn-public-product-backups/20260716T175914Z-ruvds-0.9.119-public.1`.
- Backend 0.9.119 paid-candidate backups:
  - Timeweb: `/root/greenvpn-paid-beta-backend-backups/20260716T175858Z-paid-beta-backend-fallback-peer-20260716-r23`;
  - RUVDS Moscow: `/root/greenvpn-paid-beta-backend-backups/20260716T175919Z-paid-beta-backend-fallback-peer-20260716-r23`.
- London preserved-state recovery backup:
  `/root/greenvpn-london-recovery-backups/20260716T100956Z`.
- Production catalog DB backups before London publication:
  - Timeweb: `/root/greenvpn-london-catalog-backups/20260716T103621Z-timeweb`;
  - RUVDS Moscow: `/root/greenvpn-london-catalog-backups/20260716T103621Z-ruvds-moscow`.
- Paid-beta catalog DB backups before London publication:
  - Timeweb: `/root/greenvpn-london-catalog-backups/20260716T104858Z-timeweb-paid-beta`;
  - RUVDS Moscow: `/root/greenvpn-london-catalog-backups/20260716T104858Z-ruvds-moscow-paid-beta`.
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
