# Green VPN Development Protocol

Updated: 2026-06-12.

## Startup

1. Run `git status --short`.
2. Read `docs/NEW_CHAT_HANDOFF_2026_05_15/START_THIS_IN_NEW_CHAT_RU.md`.
3. Read `docs/CURRENT_HANDOFF.md`.
4. Open only files needed for the current task.

## Safety

- Do not expose or commit secrets, tokens, SMTP/SMS/YooKassa credentials, SSH private keys, or WireGuard private keys.
- Do not use `git reset --hard`, `git checkout --`, or broad destructive cleanup without explicit owner approval.
- Preserve questionable cleanup candidates to `D:\GreenVPN_Cleanup_Archive` before removing them from the repo.
- Do not touch FriendlyLynet / Friendly Linnet.

## Release Discipline

- Main public site `https://greenvpn.pro` is frozen.
- Stable Android/Windows downloads are used by real users and must not be replaced unless explicitly requested.
- Risky work, rewarded ads, new VPN nodes, and experiments belong on the preview/test contour first.

## Current Routing Principle

- Public catalog should only expose working Netherlands nodes unless the owner explicitly promotes a new node.
- Retired Timeweb Frankfurt/Germany infrastructure must not be restored to public routing.

## Repo Hygiene

- Keep generated files, build outputs, old handoff packs, and one-shot patch scripts out of the working tree.
- Keep concise current docs in repo; move long historical context to the D: archive.
- Commit future changes by topic: backend, Android, Windows, docs, deployment scripts.
