# Green VPN: Start Here In New Chat

Updated: 2026-06-12.

## First Command

Run:

```powershell
git status --short
```

## Non-Negotiable Rules

- Do not print or commit secrets, tokens, SMTP/SMS/YooKassa credentials, SSH private keys, or WireGuard private keys.
- Do not use `git reset --hard`, `git checkout --`, or destructive cleanup unless the owner explicitly asks for it.
- Visible brand: Green VPN.
- Internal BlueVPN names may remain for now.
- Do not touch FriendlyLynet / Friendly Linnet.
- Main public site `https://greenvpn.pro` is frozen because real users use it. Do not change stable public APK/EXE, stable manifests, or main site content without explicit owner approval.
- Work on the test/preview contour unless explicitly told otherwise.

## Current Known State

- Backend `https://api.greenvpn.pro/healthz` was checked on 2026-06-12 and returned version `0.9.102`.
- Public catalog should expose only working Netherlands nodes:
  - `intelligent_smew` / `nl1.vpn.greenvpn.pro:443`;
  - `tw-7879598-nl1` / `nl2.vpn.greenvpn.pro:443`.
- Timeweb Frankfurt/Germany `8147243` / `72.56.31.142` is retired/deleted and must not be restored to public routing.
- Client-side YouTube quality gate was removed/disabled after it broke Android connection flow. Do not reintroduce it casually.

## Important Docs

- Current compact handoff: `docs/CURRENT_HANDOFF.md`.
- Current release state: `docs/RELEASE_STATE.md`.
- Main/test contour operating rule: `docs/OPERATIONS_MAIN_FREEZE_AND_TEST_CONTOUR_RU.md`.
- VPS provider shortlist: `docs/VPS_PROVIDER_OPTIONS_WITH_API_RU.md`.

## Current Work Direction

1. Keep the stable public product working and untouched.
2. Continue risky work only on preview/test.
3. Clean and organize the repo without reverting real source work.
4. For a new VPN location, provision a private/test node first, then smoke-test from real Android before any public catalog promotion.
