# Green VPN Current Handoff

Last updated: 2026-06-14.

## Hard Rules

- Start every serious project pass with `git status --short`.
- Do not print or commit secrets, SMTP/SMS/YooKassa tokens, API keys, SSH private keys, or WireGuard private keys.
- Do not use `git reset --hard`, `git checkout --`, or destructive cleanup without explicit owner approval.
- Visible brand is Green VPN. Internal BlueVPN names may stay for now.
- Do not touch FriendlyLynet / Friendly Linnet.
- Main public contour `https://greenvpn.pro` is frozen. Do not upload stable APK/EXE, do not change stable manifests, and do not alter the main public site unless the owner explicitly unfreezes it.
- Work on the closed/test/preview contour only.

## Current Stable State

- Main public site: frozen and currently used by real users.
- Main Android stable: no-ads/trial-only line, last recorded as `0.2.23-trial-only-android-vpn-takeover`.
- Main Windows stable: no-ads/trial-only line, last recorded as `0.2.22-trial-only-manual-server-switch`.
- Test/preview contour is the place for rewarded ads, experiments, and risky fixes.

## Live Backend Snapshot

Checked 2026-06-14:

- `https://api.greenvpn.pro/healthz` returns backend version `0.9.102`.
- Public server catalog returns Netherlands nodes only:
  - `intelligent_smew` / Netherlands #1 / `nl1.vpn.greenvpn.pro:443`;
  - `tw-7879598-nl1` / Netherlands #2 / `nl2.vpn.greenvpn.pro:443`.
- Client-side YouTube route-quality gate is disabled in the live catalog. Server-side adaptive routing remains enabled.
- Older Frankfurt/Germany notes are historical only.
- Public update/download check is green:
  - Android stable and preview return `.apk`;
  - Windows stable and preview return `.exe`;
  - legacy Android compatibility path does not return Windows installer.

## Infrastructure

- Timeweb Frankfurt/Germany server `8147243` and floating IP `72.56.31.142` were retired/deleted.
- FriendlyLynet / Friendly Linnet is personal infrastructure and must not be modified.
- Timeweb API works and currently sees 5 servers. Timeweb production balance is about `1671.5 RUB`; do not spend it on a new NL node without explicit production-balance-risk acceptance.
- RUVDS API works and currently sees one server, `ruvds-2584554-ld8`, which is preview-only and passes remote provisioning, peer, and client-config smoke checks.
- RUVDS Zurich rollout wrapper exists and is dry-run safe by default, but paid create is blocked until the API-visible balance is at least `933 RUB`. Current configured RUVDS API credential still sees `267 RUB`.
- Serverspace API works but is not in the active plan right now because funding is not ready.
- New test VPN nodes must be created outside the main public pool first and promoted only to preview/test after smoke checks.

## Repo Cleanup Status

- Large generated/cache folders were archived to `D:\GreenVPN_Cleanup_Archive\20260612_144838`.
- Full old historical handoff docs were archived to `D:\GreenVPN_Cleanup_Archive\20260612_144838\docs_full_history_before_compaction`.
- Old root one-shot patch scripts were removed from the repo working tree.
- Remaining dirty source changes are real project work and should be reviewed/committed by topic, not blindly deleted.

## Practical Next Steps

1. Keep stable public site untouched.
2. Continue testing/fixing only on the preview contour.
3. For RUVDS scaling, first make sure `D:\GreenVPN_Secrets\provider_api.local.ps1` contains an API v2 token from the funded RUVDS account. Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_ruvds_access_candidates.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

4. Preferred RUVDS continuation command, safe dry-run by default:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1
```

5. When RUVDS is ready, create and provision the Zurich preview node with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1 -CreateWhenReady -ConfirmPaidCreate
```

6. If RUVDS API creates the VPS but does not return public IPv4, take the IP from the panel once and continue:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview
```

7. Before any release publish, verify Android/Windows artifacts, backend catalog, and stable/preview target separation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1
```
