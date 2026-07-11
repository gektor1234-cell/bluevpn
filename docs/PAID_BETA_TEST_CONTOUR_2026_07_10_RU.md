# Green VPN: изолированный тестовый paid beta-контур

Дата: 2026-07-10. Статус: технически готов к действиям владельца, но не к публичному запуску.

## Размещение

| Роль | Узел | Beta API | Beta site |
| --- | --- | --- | --- |
| Primary | Timeweb Moscow `72.56.32.197` | `https://api.greenvpn.pro/paid-beta-api` | `https://greenvpn.pro/paid-beta/` |
| Fallback | RUVDS Moscow `176.113.81.35` | `https://176-113-81-35.sslip.io/paid-beta-api` | `https://176-113-81-35.sslip.io/paid-beta/` |

На каждом control-plane:

- `greenvpn-paid-beta.service`, bind только `127.0.0.1:8010`;
- current: `/opt/bluevpn-paid-beta/current`;
- DB: `/opt/bluevpn-paid-beta/data/bluevpn.db`;
- root-only env: `/etc/bluevpn/paid-beta.env`;
- site: `/var/www/paid-beta`;
- sync: `greenvpn-paid-beta-db-sync.timer`, 10 секунд;
- probe: `greenvpn-paid-beta-service-probe.timer`, 300 секунд.

Production использует отдельные service/DB/site/download paths и backend `0.9.105` на `127.0.0.1:8000`.

## Текущий release

- Android: `0.3.0-paid-beta.5`, build `2026071005`, package `pro.greenvpn.app.beta`.
- Windows на серверах и локально: `0.3.0-paid-beta.10`, side-by-side beta, `NotSigned`, `required=false`.
- Backend: `0.9.106-paid-beta.5`.
- Release directory на обоих узлах: `paid-beta-0.3.0-paid-beta.5-2026071005-r8`.
- Bundle SHA-256: `89423157BF094435C660692491C2885D2EC1EAF245F0F20ED2773A6E18B9F6FC`.
- Android SHA-256: `90E42FB6CE5A06247E620E5DC3302B7C7C86A0F9A8FEBDC523876A622B9C6580`.
- Windows `.10` SHA-256: `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170` (`NotSigned`).
- Client IP pool: `10.10.0.180-10.10.0.229`.

Update API на Timeweb выдаёт primary download URLs; RUVDS выдаёт собственные fallback URLs. Оба возвращают Android `.5`/Windows `.10`, правильные SHA и `required=false`.

Windows `.10` прошёл real install/reboot/session/DPAPI/VPN/DNS/uninstall/network-recovery/reinstall на ПК владельца и опубликован только в изолированном beta-контуре.

## Проверки

- 31 backend/DB-sync/first20 tests: OK.
- Flutter test: OK; analyze без новых fatal issues.
- Android release build/signature/package/label: OK.
- Release gate: 0 warnings, 0 errors.
- Local/public beta health: `0.9.106-paid-beta.5`; production health: `0.9.105`.
- DB `quick_check=ok` на обоих узлах.
- Stateful HTTP smoke: marker denial, primary/fallback login, invite, Trial, 149/299, 2 devices, no ads/timer, bootstrap/config/fallback: OK.
- Smoke peer удалён; после синхронизации на обоих узлах 0 smoke users/devices/invites.
- Site readiness 8/8; YooKassa key перевыпущен и проверен на обоих узлах. Реальный платёж 149 RUB, активация, межсерверная синхронизация и RUVDS fallback subscription/bootstrap: OK.
- Оба service probe завершились `Result=success`, timers active.
- Реальный Timeweb beta outage переключил Android-клиент на RUVDS без потери сессии.
- Реальный Samsung SM-A226B: YouTube playback через VPN, recents swipe/reopen, корректный disconnect: OK.
- Custom app picker: поиск Chrome, сохранение, active reconfigure и UID allowlist: OK. После удаления Chrome его UID исчез из VPN network capabilities, `tun0` остался поднят.
- Stable Android `0.2.44` и beta `.5` установлены рядом; stable не заменён.

## Backups и rollback

- Stable snapshots: `/root/greenvpn-pre-paid-beta-20260710T103821`.
- Previous technical-ready snapshots: `/root/greenvpn-paid-beta-technical-ready-20260710T110614Z`.
- Final deploy backups:
  - Timeweb: `/root/greenvpn-paid-beta-backups/20260710T125718Z-timeweb-paid-beta-0.3.0-paid-beta.5-2026071005-r5`;
  - RUVDS: `/root/greenvpn-paid-beta-backups/20260710T125730Z-ruvds-paid-beta-0.3.0-paid-beta.5-2026071005-r5`.
- Final owner-gate snapshots: `/root/greenvpn-paid-beta-owner-gate-ready-20260710`.
- Local checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\paid_beta_owner_gate_ready_20260710`.
- Git tag: `greenvpn-paid-beta-owner-gate-ready-20260710`.

Разрешённый beta rollback: повторно развернуть проверенный `r5` либо остановить только beta service/sync/probe. Production service/DB/downloads не трогать. Android `.2/.3/.4` и server revisions до `r5` оставлены только для forensic comparison.

## Ограничения

- SQLite sync не даёт глобальную транзакционную блокировку и не реплицирует delete tombstones. Для первых 20: primary-normal/fallback-only; массовый запуск требует write authority или общей transactional DB.
- Windows installer не подписан, но полный физический installation/reboot/VPN/DNS/uninstall/network-recovery/reinstall gate пройден.
- Реальный платёж 149 RUB, activation/refund/cancel не проверен.
- Terms/privacy не подтверждены владельцем/юристом.
- `noindex` не является контролем доступа; доступ защищают marker, invite и cohort.
