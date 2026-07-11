# Green VPN Release State

Last compacted: 2026-07-11.

## Stable Public Contour

- Status: active production stable, frozen during paid beta work.
- Site/API: `https://greenvpn.pro`, `https://api.greenvpn.pro`.
- Backend: `0.9.105`.
- Android: `0.2.44`, build `2026070504`, SHA `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Windows SHA: `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Timeweb Moscow primary and RUVDS Moscow fallback remain active. Production artifacts/DB were not changed by beta deployment.

## Isolated Paid Beta

- Paths: `/paid-beta`, `/paid-beta-api`; keep isolated and do not promote to production before the remaining owner gates.
- Android/backend: `0.3.0-paid-beta.5` / `0.9.106-paid-beta.4`.
- Server-published Windows beta: `0.3.0-paid-beta.10`, SHA `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170` (`NotSigned`, `required=false`).
- Local side-by-side Windows candidate is the same deployed `.10` artifact; install, reboot, VPN/DNS transition, uninstall/network recovery and clean reinstall all passed.
- Current release on both nodes: `paid-beta-0.3.0-paid-beta.5-2026071005-r6`.
- Android package: `pro.greenvpn.app.beta`, side-by-side with stable.
- Policy: Trial 3 days, 149 RUB first invited period, then 299 RUB manually, 2 devices, no ads/timer/auto-renew.
- Marker + channel + personal invite + cohort enforcement active.
- DB sync every 10 seconds; service probes every 300 seconds.
- Current DB state on both nodes: owner data only, 1 user/subscription, 2 tokens/devices, 0 billing orders and no smoke rows.

## Verified

- Physical Android VPN/failover/YouTube/recents/disconnect/custom-app split tunneling: passed.
- Stateful auth/invite/quote/bootstrap/config/fallback cleanup: passed.
- 28 backend tests and release gate: passed.
- Site readiness: 8/8. Payment configuration ready; real payment not yet run.
- Primary update API serves primary download URLs; fallback API serves fallback URLs with matching hashes.
- Windows `.10` static isolation/payload/parser/Defender gates passed.
- Windows `.10` real install, reboot, session/DPAPI migration, kill-switch, DNS-leak, handshake, API/YouTube, cleanup, competing-VPN restoration, destructive uninstall/network recovery and clean reinstall gates passed.
- Timeweb/RUVDS beta deployment `r6` passed; both update APIs and downloads expose `.10` with the approved SHA while production remains `0.9.105`.

## Owner Gate

1. One real 149 RUB payment with activation/refund/cancel verification.
2. Owner/legal acceptance of terms and privacy.

Only then create the first 20 invite package.

## Known Risks

- Windows `.10` is side-by-side isolated and physically verified, but remains unsigned. It is published only in the isolated beta contour and must not replace the production Windows build before the remaining owner gates.
- Two SQLite nodes are not globally transactional and deletes have no replicated tombstones. Keep first20 primary-normal/fallback-only.
- KZ VPS deletion and London/NL legacy cleanup require separate owner approval.

## Operational Rule

Preserve snapshots before cleanup. Never expose secrets in chat, docs, repository or checkpoint manifests.
