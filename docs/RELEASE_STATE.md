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
- Android/backend: `0.3.0-paid-beta.6` / `0.9.106-paid-beta.9`.
- Server-published Windows beta: `0.3.0-paid-beta.11`, SHA `ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32` (`NotSigned`, `required=false`).
- Local side-by-side Windows candidate is the same deployed `.10` artifact; install, reboot, VPN/DNS transition, uninstall/network recovery and clean reinstall all passed.
- Current release on both nodes: `paid-beta-0.3.0-paid-beta.6-2026071106-r12`.
- Android package: `pro.greenvpn.app.beta`, side-by-side with stable.
- Policy: Trial 3 days; 249/649/1099 RUB for 30/90/180 days; no ads/timer; opt-out auto-renew.
- Marker + channel + personal invite + cohort enforcement active.
- DB sync every 10 seconds; service probes every 300 seconds.
- Current DB state on both nodes: earlier owner payment/subscription retained, rejected 249 RUB order canceled, no pending billing orders, `quick_check=ok`.

## Verified

- Physical Android VPN/failover/YouTube/recents/disconnect/custom-app split tunneling: passed.
- Stateful auth/invite/quote/bootstrap/config/fallback cleanup: passed.
- 31 backend/DB-sync/first20 tests and release gate 0/0: passed.
- Site readiness: 8/8. YooKassa key was reissued, installed into root-only production/beta env on both control-plane nodes and validated with provider HTTP 200.
- Primary update API serves primary download URLs; fallback API serves fallback URLs with matching hashes.
- Windows `.10` static isolation/payload/parser/Defender gates passed.
- Windows `.10` real install, reboot, session/DPAPI migration, kill-switch, DNS-leak, handshake, API/YouTube, cleanup, competing-VPN restoration, destructive uninstall/network recovery and clean reinstall gates passed.
- Timeweb/RUVDS beta deployment `r6` passed; both update APIs and downloads expose `.10` with the approved SHA while production remains `0.9.105`.
- Billing guard `r7` passed 29 tests and release gate 0/0. Timeweb is the only paid-beta billing writer; RUVDS rejects billing mutation before DB writes. Empty checkout artifacts from the failed credential test were backed up and removed from both DBs.
- One real 149 RUB YooKassa payment succeeded and activated `paid_beta_30d` through 2026-08-10. Provider reports the payment as paid and refundable; auto-renew remains disabled.
- YooKassa cabinet webhook points to the production HTTPS endpoint and includes payment success/cancel, capture waiting, payment-method activation and refund success events.
- DB sync `r8` normalizes naive and timezone-aware timestamps to UTC. Both sync timers complete with 0 conflicts/errors, and RUVDS served active subscription/bootstrap with Timeweb beta stopped.
- Billing guard `r12` passed 41 backend and 6 Flutter tests. It sanitizes the YooKassa recurring-payment rejection, cancels the local empty order and prevents billing API failover from hiding the primary error.
- Both public beta health endpoints expose backend `.9`; both beta download manifests expose Android `.6` and Windows `.11` with matching hashes.
- YooKassa recurring payments remain externally disabled. Evidence was sent from `https://greenvpn.pro/paid-beta/yookassa-review-20260711/` and is waiting for a manager.

## Owner Gate

1. YooKassa enables recurring bank-card payments.
2. Real 249 RUB smoke confirms `payment_method.saved=true`.
3. App-side cancellation clears the saved payment method on both nodes.
4. Only then publish the stable candidate and forced update.

## Known Risks

- Windows `.10` is side-by-side isolated and physically verified, but remains unsigned. It is published only in the isolated beta contour and must not replace the production Windows build before the remaining owner gates.
- Two SQLite nodes are not globally transactional and deletes have no replicated tombstones. Keep first20 primary-normal/fallback-only.
- KZ VPS deletion and London/NL legacy cleanup require separate owner approval.

## Operational Rule

Preserve snapshots before cleanup. Never expose secrets in chat, docs, repository or checkpoint manifests.
