# Green VPN Release State

Last compacted: 2026-07-05.

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

- Preview/test is still where rewarded ads, adgate, new server experiments, and risky client fixes should happen before the next owner-approved stable promotion.
- Preview artifacts may be rebuilt and uploaded only to preview/test links.
- Stable and preview must stay visibly separated.

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
- YooKassa webhook should still be verified on the next real payment before scaling paid sales.
- RuStore/Yandex Ads moderation and monetization status still depends on external review.
- Repository still has real uncommitted source changes. They need topic-by-topic review/commits, not a blind reset.

## Operational Rule

When uncertain, preserve data to `D:\GreenVPN_Cleanup_Archive` first, then clean the working tree. Never expose secrets in chat or repo.
