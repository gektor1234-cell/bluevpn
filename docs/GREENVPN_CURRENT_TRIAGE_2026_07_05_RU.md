# Green VPN: current triage 2026-07-05

Дата: 2026-07-05.

Цель: зафиксировать текущие симптомы, вероятные причины и порядок исправления.

## Текущие симптомы

### Android login

- Email code отправляется долго.
- После ввода кода долго висит стадия подготовки устройства/VPN.
- Иногда `POST /auth/email/code/start` возвращает 503: не удалось отправить email-код.
- Иногда bootstrap на fallback API `https://88-218-250-86.sslip.io` дает timeout/connection abort.

### Android VPN

- Netherlands auto/full-tunnel периодически работает.
- London manual WireGuard работает.
- London через наше Android-приложение может подключаться формально, но не давать трафик.
- Были случаи: Android status bar показывает VPN key, а приложение считает, что активен другой VPN.
- Social-only уже несколько раз ломался из-за изменений в VPN status/per-app logic.

### Windows

- Windows должен соответствовать общей актуальной логике, но без Android-only функций.
- При проблемах Timeweb login не должен полностью падать, если fallback API жив.
- Сессия после обновления не должна слетать.

### Backend/fallback

- Если Timeweb/primary API падает, клиент должен иметь возможность:
  - залогиниться;
  - получить catalog;
  - получить config;
  - подключиться к независимому node, например RUVDS London.
- Сейчас fallback может отвечать `/healthz`, но падать на bootstrap/config. Это не считается рабочим fallback.

## Главная техническая гипотеза

Проблема не одна. Есть минимум три отдельных слоя:

1. Auth email code медленный, потому что backend синхронно ждет SMTP.
2. Fallback API недостаточно проверяется: health alive не гарантирует bootstrap/config alive.
3. London Android app path отличается от manual WireGuard path: проверять generated config, AllowedIPs, DNS, per-app mode, native handoff.

## Порядок исправления

### Блок 1. Быстрый auth

Цель: кнопка `Получить код` не должна зависать на SMTP.

Проверить:

- `backend_live/app/main.py`: `send_smtp_email`;
- `POST /api/v1/auth/email/code/start`;
- текущий SMTP timeout;
- есть ли queue/background send.

Исправление:

- сократить SMTP timeout;
- при возможности отправлять email код в background queue;
- клиенту возвращать быстрый понятный статус;
- если SMTP реально не отправил письмо, логировать это в backend/support, а не держать пользователя минуту.

### Блок 2. Настоящий API failover

Цель: fallback считается живым только если проходят реальные client endpoints.

Проверить primary и fallback:

- `/healthz`;
- `/api/v1/catalog/servers`;
- `/api/v1/client/bootstrap`;
- `/api/v1/client/config`;
- auth start/verify.

Исправление:

- client API selector должен считать API пригодным только после проверки рабочих endpoint classes;
- админка/monitoring должны явно показывать `primary auth`, `primary bootstrap`, `fallback auth`, `fallback bootstrap`.

### Блок 3. London Android traffic

Цель: если manual WireGuard London работает, приложение должно генерировать эквивалентный рабочий config.

Проверить:

- server public key источники;
- endpoint/port;
- AllowedIPs;
- DNS;
- MTU;
- per-app mode disabled/enabled branch;
- Android native config handoff;
- нет ли старого stale peer/config для device.

Особая заметка: `docs/WIREGUARD_MANUAL_CONFIG_NOTES_RU.md` говорит, что для London раньше была проблема stale server public key. Это первое место для сравнения manual config vs app config.

### Блок 4. VPN ownership/status

Цель: приложение не должно путать свой активный VPN с чужим VPN.

Проверить:

- Android marker сохранения собственного туннеля;
- статус после сворачивания;
- статус после закрытия recent apps;
- сценарий, когда пользователь включает другой VPN.

Правильное поведение:

- если активен чужой VPN, показывать `Другой VPN активен`;
- при нажатии `Переключить на Green VPN` запускать Android VpnService prepare/connect и перехватывать системный VPN;
- если активен наш VPN, UI должен показывать `Включено`, даже после возврата в приложение.

### Блок 5. Update hygiene

Цель: обновления не должны ломать сессию и не должны плодить мусор.

Проверить:

- Android APK download path;
- удаление временного APK после install intent;
- update manifest platform split;
- force-update modal поверх экранов;
- session store persistence across app update.

## Что не делать сейчас

- Не возвращать client-side YouTube gate как блокирующую проверку подключения.
- Не публиковать новые stable APK/EXE без отдельной команды.
- Не добавлять KZ/London в stable без smoke.
- Не лечить London Android вслепую сменой сервера, если manual WireGuard на этом сервере работает.
- Не трогать FriendlyLynet.

## Безопасные проверки

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider all -IncludeInventory
```

Эти проверки не должны печатать секреты.
