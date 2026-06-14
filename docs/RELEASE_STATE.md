# Green VPN Release State

Last compacted: 2026-06-12.

## Stable Public Contour

Status: frozen.

- Public site: `https://greenvpn.pro`.
- Public API: `https://api.greenvpn.pro`.
- Stable Android is the no-ads/trial-only line. Last recorded version: `0.2.23-trial-only-android-vpn-takeover`.
- Stable Windows is the no-ads/trial-only line. Last recorded version: `0.2.22-trial-only-manual-server-switch`.
- Do not replace stable public APK/EXE or update stable manifests until the owner explicitly asks for it.

## Preview/Test Contour

- Preview/test is where rewarded ads, adgate, new server experiments, and risky client fixes should happen.
- Preview artifacts may be rebuilt and uploaded only to preview/test links.
- Stable and preview must stay visibly separated.

## Public Download Checks

Safe read-only check for update manifests and public download aliases:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
```

This verifies that Android manifests/download aliases return APK files, Windows manifests/download aliases return EXE files, and the legacy Windows update endpoint does not send an EXE to Android clients.

## Backend And Catalog

Verified 2026-06-12:

- `/healthz` version: `0.9.102`.
- Public client catalog exposes two Netherlands WireGuard UDP endpoints:
  - `intelligent_smew`, `nl1.vpn.greenvpn.pro:443`, health score around `95`;
  - `tw-7879598-nl1`, `nl2.vpn.greenvpn.pro:443`, health score around `100`.
- Public catalog default: `intelligent_smew`.
- Client-side YouTube quality gate is disabled. Server-side adaptive routing remains enabled.

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
