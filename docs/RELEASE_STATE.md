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

- Paths: `/paid-beta`, `/paid-beta-api`; do not publish before owner gate.
- Android/backend: `0.3.0-paid-beta.5` / `0.9.106-paid-beta.4`.
- Server-published Windows beta: `0.3.0-paid-beta.2` (`NotSigned`).
- Local side-by-side Windows candidate: `0.3.0-paid-beta.10`, SHA `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170` (`NotSigned`); installed and runtime-tested locally, not deployed.
- Current release on both nodes: `paid-beta-0.3.0-paid-beta.5-2026071005-r5`.
- Android package: `pro.greenvpn.app.beta`, side-by-side with stable.
- Policy: Trial 3 days, 149 RUB first invited period, then 299 RUB manually, 2 devices, no ads/timer/auto-renew.
- Marker + channel + personal invite + cohort enforcement active.
- DB sync every 10 seconds; service probes every 300 seconds.
- Current DB state on both nodes: owner data only, no smoke rows.

## Verified

- Physical Android VPN/failover/YouTube/recents/disconnect/custom-app split tunneling: passed.
- Stateful auth/invite/quote/bootstrap/config/fallback cleanup: passed.
- 28 backend tests and release gate: passed.
- Site readiness: 8/8. Payment configuration ready; real payment not yet run.
- Primary update API serves primary download URLs; fallback API serves fallback URLs with matching hashes.
- Windows `.10` static isolation/payload/parser/Defender gates passed.
- Windows `.10` real install, reboot, session/DPAPI migration, kill-switch, DNS-leak, handshake, API/YouTube, cleanup and competing-VPN restoration gates passed. Uninstall/reinstall recovery is pending owner confirmation.

## Owner Gate

1. Windows `.10` uninstall/network-recovery and immediate reinstall smoke. All earlier Windows gates passed.
2. One real 149 RUB payment with activation/refund/cancel verification.
3. Owner/legal acceptance of terms and privacy.

Only then create the first 20 invite package.

## Known Risks

- Windows `.10` is side-by-side isolated and physically verified, but remains unsigned. It must not replace the public Windows build before the owner gate.
- Two SQLite nodes are not globally transactional and deletes have no replicated tombstones. Keep first20 primary-normal/fallback-only.
- KZ VPS deletion and London/NL legacy cleanup require separate owner approval.

## Operational Rule

Preserve snapshots before cleanup. Never expose secrets in chat, docs, repository or checkpoint manifests.
