# Текущее состояние проекта Green VPN

## Репозиторий

Рабочая папка:

`C:\Users\gekto\projects\bluevpn`

Это исторически `bluevpn`, но видимый бренд продукта теперь `Green VPN`.

Внутренние имена пока оставлены старые, чтобы не сломать WireGuard, ProgramData и существующий flow:

- `BlueVPNDev1`
- `WireGuardTunnel$BlueVPNDev1`
- `C:\ProgramData\BlueVPN`

## Общая архитектура

Проект состоит из нескольких слоёв:

- Flutter Windows client в `lib\`.
- Native Windows runner/service code в `windows\`.
- Windows installer scripts в `scripts\windows\`.
- Backend MVP в `backend_live\app\main.py`.
- Admin/support app в `admin_support_app\`.
- Monitoring/probe scripts в `scripts\monitoring\`.
- Release/handoff docs в `docs\`.

## Текущий backend

Целевая версия backend на текущем этапе:

`0.9.11`

Рабочий сервер:

`37.220.85.211`

Production API:

`https://api.greenvpn.pro`

Локальный backend при разработке может использовать:

`http://127.0.0.1:8000`

Ключевые backend-направления:

- auth/session/device flow;
- client config выдача;
- tariffs/orders/payments groundwork;
- phone/SMS/email groundwork;
- update manifest groundwork;
- support reports groundwork;
- admin API;
- server catalog;
- health scoring;
- monitoring/probe ingestion.

## Пользовательский клиент

Что уже должно работать:

- запуск Green VPN;
- вход/регистрация в базовом виде;
- VPN connect/disconnect;
- Social Only;
- service/tray/autostart;
- тарифная вкладка;
- отсутствие Backend Admin в обычном пользовательском UI;
- обычный пользователь не должен видеть внутренние dev/admin инструменты;
- support/report UI должен двигаться к варианту `Отправить отчет`, а не `Скопировать отчет`.

Что нельзя ломать:

- WireGuard config/key/tunnel;
- `ProgramData` config/state;
- existing session/device flow;
- working Social Only;
- installer path;
- стабильный rollback.

## Windows service / UAC

Правильная цель:

- установщик один раз просит админ-права;
- ставит системный компонент;
- UI запускается без постоянного UAC;
- privileged VPN-действия делает service/helper;
- не появляются лишние PowerShell-окна;
- приложение не конфликтует с Amnezia/WARP/WireGuard других приложений;
- наш VPN не должен ломать чужие VPN и должен корректно распознавать competing VPN.

Важно: не убивать процессы Amnezia, WARP, WireGuardManager и чужие туннели без прямого разрешения.

## Admin/support app

Папка:

`C:\Users\gekto\projects\bluevpn\admin_support_app`

Локальный запуск/просмотр обычно:

`http://127.0.0.1:8090/`

или файл:

`C:\Users\gekto\projects\bluevpn\admin_support_app\index.html`

Назначение:

- отдельная внутренняя админка;
- не внутри пользовательского VPN;
- аналитика, пользователи, платежи, входы, audit, support reports, monitoring, server catalog, health scoring, readiness;
- роли и доступы позже.

Admin token нельзя писать в репозиторий и нельзя выводить в чат.

## Domain/email state

Домен куплен:

`greenvpn.pro`

DNS уже содержит важные записи:

- `A @ -> 95.163.244.138`
- `A www -> 95.163.244.138`
- `A api -> 37.220.85.211`
- MX для Яндекс 360;
- SPF TXT;
- DKIM TXT;
- Yandex verification TXT.

Yandex 360 / корпоративная почта в процессе подключения. Это внешний сервис, требующий действий владельца, но backend/app должны быть подготовлены так, чтобы после выдачи SMTP/почтовых данных всё быстро включалось без переписывания архитектуры.

## Текущий ближайший слой

Фокус ближайшего этапа:

- стабилизировать server-side health scoring;
- довести admin server catalog/health flow;
- не публиковать managed catalog клиентам автоматически;
- подготовить monitoring/probe groundwork;
- держать всё безопасным: без ключей, токенов и приватных конфигов.

## Ориентировочный прогресс

Это не строгая метрика, а рабочий ориентир:

- Общий мастер-план: примерно `39%`.
- Windows MVP: примерно `85%`.
- Monitoring/resilience слой: примерно `52%`.

После каждого стабильного шага новый чат должен обновлять проценты в handoff, но без фантазий: только если реально закрыт понятный блок.
