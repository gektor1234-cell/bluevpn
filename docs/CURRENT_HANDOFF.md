# Green VPN Current Handoff

Last compacted: 2026-06-12.

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

Checked 2026-06-12:

- `https://api.greenvpn.pro/healthz` returns backend version `0.9.102`.
- Public server catalog returns Netherlands nodes only:
  - `intelligent_smew` / Netherlands #1 / `nl1.vpn.greenvpn.pro:443`;
  - `tw-7879598-nl1` / Netherlands #2 / `nl2.vpn.greenvpn.pro:443`.
- Client-side YouTube route-quality gate is disabled in the live catalog. Server-side adaptive routing remains enabled.
- Older Frankfurt/Germany notes are historical only.

## Infrastructure

- Timeweb Frankfurt/Germany server `8147243` and floating IP `72.56.31.142` were retired/deleted.
- FriendlyLynet / Friendly Linnet is personal infrastructure and must not be modified.
- Next test VPN node should be created outside the main public pool first. Preferred provider research is in `docs/VPS_PROVIDER_OPTIONS_WITH_API_RU.md`.

## Repo Cleanup Status

- Large generated/cache folders were archived to `D:\GreenVPN_Cleanup_Archive\20260612_144838`.
- Full old historical handoff docs were archived to `D:\GreenVPN_Cleanup_Archive\20260612_144838\docs_full_history_before_compaction`.
- Old root one-shot patch scripts were removed from the repo working tree.
- Remaining dirty source changes are real project work and should be reviewed/committed by topic, not blindly deleted.

## Practical Next Steps

1. Keep stable public site untouched.
2. Continue testing/fixing only on the preview contour.
3. Pick a new test VPS provider, preferably RUVDS first or HOSTKEY second.
4. Before any release publish, verify Android/Windows artifacts, backend catalog, and stable/preview target separation.
