# Green VPN Release State

Last compacted: 2026-07-10.

## Stable Public Contour

Status: active production rollout approved by owner on 2026-07-05.

- Public site: `https://greenvpn.pro`.
- Public API: `https://api.greenvpn.pro`.
- Stable Android: `0.2.44`, build `2026070504`, mandatory update enabled.
- Stable Windows: `0.2.39-windows-clean-server-ui`, mandatory update enabled.
- Public Android alias: `https://greenvpn.pro/downloads/GreenVPN_Android.apk`.
- Public Windows alias: `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`.
- RUVDS Moscow mirrors both active public aliases for fallback downloads.
- Owner explicitly approved replacing stable public APK/EXE and enabling the update popup on 2026-07-05.

## Preview/Test Contour

- The active test contour is the isolated paid beta under `/paid-beta` and `/paid-beta-api`.
- App/backend: `0.3.0-paid-beta.2` / `0.9.106-paid-beta.2`.
- Primary/fallback beta APIs run separately on `:8010`; beta DB sync runs every 10 seconds.
- Paid beta uses marker + channel + personal invite + cohort enforcement.
- Policy: 3-day Trial, 149 RUB first invited period, then 299 RUB manually, 2 devices, no ads/forced timer/auto-renew.
- Beta probe timers run on both Russian control-plane nodes and keep primary/fallback/API/VPN endpoint observations separate from production telemetry.
- Do not publish or promote this contour until the owner gate in `docs/PAID_BETA_FIRST20_RUNBOOK_2026_07_10_RU.md` is complete.

## Public Download Checks

Safe read-only check for update manifests and public download aliases:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
```

This verifies that Android manifests/download aliases return APK files, Windows manifests/download aliases return EXE files, and the legacy Windows update endpoint does not send an EXE to Android clients.

## Backend And Catalog

Verified 2026-07-05:

- `/healthz` version: `0.9.105`.
- Public client catalog exposes `current_wg0`, `ruvds-2584554-ld8`, and `tw-7879598-nl1`.
- Public catalog and update manifests are served by Timeweb Moscow primary and RUVDS Moscow fallback.
- Timeweb/RUVDS Moscow DB state sync runs every 30 seconds for critical auth/session/device/ad-grant state.
- Rewarded ads and the ad-session disconnect timer are disabled server-side.

## Retired Infrastructure

- Timeweb Frankfurt/Germany `8147243` / `tw-8147243-de1` / `72.56.31.142` is retired and deleted.
- Do not restore it into public catalog.
- Old Frankfurt documentation is historical and superseded by `docs/OPERATIONS_MAIN_FREEZE_AND_TEST_CONTOUR_RU.md`.

## Known Product Risks

- Windows installer and EXE are not code-signed. This remains the main SmartScreen/Defender/trust risk.
- A real 149 RUB YooKassa beta payment, activation polling and refund/cancel path still need owner verification.
- RuStore/Yandex Ads moderation and monetization status still depends on external review.
- Two SQLite control-plane nodes are not globally transactional; keep primary-normal/fallback-only for the first 20.
- KZ test VPS is unreachable and costs 611 RUB/month; London needs approved recovery-artifact cleanup.

## Operational Rule

When uncertain, preserve data to `D:\GreenVPN_Cleanup_Archive` first, then clean the working tree. Never expose secrets in chat or repo.
