# Green VPN Development Protocol

Последнее обновление: 2026-04-30

Этот документ жестко привязывает разработку Green VPN к мастер-плану.

Для экономии контекста новый Codex, другой аккаунт или будущая сессия сначала читает только:

- `C:\Users\gekto\projects\bluevpn\docs\CODEX_CONTEXT_COMPACT_RU.md`

Большие документы читать только точечно, если компактного файла недостаточно:

- `C:\Users\gekto\projects\bluevpn\docs\CURRENT_HANDOFF.md`
- `C:\Users\gekto\projects\bluevpn\docs\RELEASE_STATE.md`
- `C:\Users\gekto\projects\bluevpn\docs\GREENVPN_MASTER_PLAN.md`
- `C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`

## Правило Экономии Контекста

Нельзя начинать каждую сессию с чтения всего старого чата и всех больших docs.

Порядок:

1. Прочитать `CODEX_CONTEXT_COMPACT_RU.md`.
2. Выполнить `git status --short`.
3. Открыть только файлы, нужные для текущей задачи.
4. Если нужна история релиза, искать точные строки в `RELEASE_STATE.md`, а не читать файл целиком.
5. Если нужна дорожная карта, читать конкретный раздел `GREENVPN_MASTER_PLAN.md`, а не весь файл.
6. После стабильного этапа обновить компактный файл одной короткой записью.
7. Старые скриншоты и длинные сообщения пользователя считать историческим шумом, пока пользователь прямо не укажет на конкретный новый скриншот.

## Главный принцип

Мы двигаемся только от одного стабильного шага к следующему стабильному шагу.

Нельзя одновременно ломиться в service, tray, auth, updater, payments и monitoring. Каждый крупный блок делается как отдельный этап:

1. Взять следующий пункт из мастер-плана.
2. Сохранить текущую стабильную версию как rollback anchor.
3. Сделать минимальный технический срез следующего пункта.
4. Проверить сборку, release gate и пользовательский сценарий.
5. Если стабильно, обновить docs и новый rollback anchor.
6. Только после этого переходить к следующему пункту.

## Текущий стабильный якорь

Если что-то ломается, сначала возвращаться сюда:

- Installer: `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Почему эта версия важна:

- Установщик работает.
- Видимый бренд Green VPN.
- UI не просит UAC на каждый запуск.
- Привилегированные VPN-действия работают через native `GreenVPNService`.
- SYSTEM scheduled tasks остаются как fallback.
- Tray/background работает: закрытие окна прячет приложение в трей, tray menu может открыть/connect/disconnect/exit.
- Autostart работает через `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\GreenVPN` и запускает только UI/tray в `--background`, без auto-connect.
- Auth cleanup работает: свежий login/register открывает главный экран, базовые auth/network ошибки не показывают пользователю raw exception.
- Dev/admin UI cleanup работает: обычный пользователь не видит `Backend Admin` и debug/dev login.
- Support report работает как пользовательский экран `Поддержка`, без сырой диагностики.
- Simple updater работает как Settings -> `Обновления` + backend update manifest.
- Simple server catalog, basic monitoring status, and internal-only YouTube/Discord/Telegram availability checks are in place.
- Payments-hardening is in place: user-facing monitoring/order-history clutter is removed, and YooKassa order/payment validation protects tariff activation.
- Production-payments readiness is in place: backend reports payment production readiness and verifies YooKassa payment state authoritatively when credentials are configured.
- Payment confirmation flow is in place: browser return page exists and the client auto-checks pending payment orders.
- Backend config fetch не блокируется `subscription_inactive` для MVP Trial.
- Green VPN не пытается включаться поверх активной Amnezia/WireGuard/WARP.
- Есть безопасное удаление только Green VPN-артефактов.

## Обязательный порядок ближайших этапов

Текущий стабильный шаг: payment confirmation flow build.

Текущий кандидат: email confirmation foundation.

Следующие этапы идут строго в этом порядке, если пользователь явно не меняет приоритет:

1. Production payments: домен, HTTPS, YooKassa production keys, real webhook URL, payment confirmation flow.
2. Email confirmation.
3. SMS/phone auth.
4. Social login.
5. Отдельное admin/support приложение.
6. Первый resilience layer: несколько серверов, health-check, fallback catalog.
7. Protocol fallback: WireGuard alternate ports, потом OpenVPN TCP 443.
8. Advanced fallback/anti-blocking transports.
9. Free mode с рекламой.
10. Code signing и public build.

## Definition Of Done Для Каждого Этапа

Этап считается стабильным только если выполнено все:

- Рабочий rollback anchor создан до рискованных изменений.
- `flutter build windows --release -t .\lib\main.dart` проходит.
- `bluevpn_release_gate.ps1 -StrictPaymentGate` проходит.
- Если собирался установщик, release gate проходит и по payload zip.
- Старый установленный тестовый Green VPN удален перед выдачей нового установщика.
- Новый установщик имеет кликабельный путь и SHA256.
- `docs\RELEASE_STATE.md` обновлен.
- `docs\CURRENT_HANDOFF.md` обновлен.
- Пользовательский сценарий проверен или честно отмечено, что не проверен.

## External Action Rule

Если для следующего шага нужно действие пользователя вне кода, не останавливать разработку. Нужно:

- продолжать делать весь кодовый слой, заглушки, readiness-checks и безопасные fallbacks;
- отдельно в ответе выделять блок `Что нужно от тебя`;
- писать конкретную инструкцию: что купить, где нажать, какие значения нужны, куда их потом добавить;
- никогда не просить и не сохранять в репозиторий реальные пароли, токены, SMTP passwords, YooKassa secret keys, SSH secrets или WireGuard private keys.

Внешние действия, которые могут понадобиться: домен, DNS, HTTPS, YooKassa keys/webhook, SMTP/mail provider, SMS provider, code-signing certificate, VPS/server purchases, admin domain, monitoring/alerting accounts.

## Правила Безопасности

- Не делать `git reset --hard`, `git checkout --`, destructive cleanup без прямого разрешения пользователя.
- Не трогать Friendly/personal server.
- Не удалять WireGuard, Amnezia, WARP и другие VPN клиента пользователя.
- Удалять можно только Green VPN-артефакты:
  - `greenvpn.exe` / `bluevpn.exe`
  - `GreenVPNConnect`, `GreenVPNDisconnect`, `GreenVPNGuard`
  - `WireGuardTunnel$BlueVPNDev1`
  - `C:\ProgramData\BlueVPN`
  - `%LOCALAPPDATA%\Programs\Green VPN`
  - Green VPN shortcuts/startup entries
- Не переименовывать внутренние имена без отдельной миграции:
  - `BlueVPNDev1`
  - `WireGuardTunnel$BlueVPNDev1`
  - `C:\ProgramData\BlueVPN`
- Не писать в repo пароли, SSH secrets, admin tokens, YooKassa keys, WireGuard private keys.

## Test Installer Rule

Перед каждым новым тестовым установщиком:

1. Остановить Green VPN.
2. Удалить Green VPN scheduled tasks.
3. Удалить только `WireGuardTunnel$BlueVPNDev1`.
4. Удалить Green VPN install dir, shortcuts, startup entries.
5. Удалить `C:\ProgramData\BlueVPN`, если не нужно сохранить логи.
6. Проверить, что Amnezia/WARP/WireGuard не затронуты.
7. Только потом собирать/выдавать новый `GreenVPN_Setup.exe`.

Если папка установки не удаляется, проверить старые `wsl.exe/wslhost.exe` backend-relay процессы через Sysinternals Handle. Не стрелять вслепую по чужим VPN-процессам.

## Rollback Rule

После каждого стабильного этапа создать отдельную rollback-папку:

`C:\BlueVPN_Builds\ROLLBACK_YYYYMMDD_HHMM_<short_reason>`

В нее положить:

- `GreenVPN_Setup_ROLLBACK.exe`
- payload zip, если есть
- SHA256 в `RELEASE_STATE.md`
- краткое описание, почему эта версия стабильна

## Работа С Мастер-Планом

`GREENVPN_MASTER_PLAN.md` является продуктовой дорожной картой.

`DEVELOPMENT_PROTOCOL.md` является правилами движения по ней.

Если пользователь говорит "идем дальше по плану", брать следующий не завершенный пункт из обязательного порядка ближайших этапов. Если текущий пункт нестабилен, сначала стабилизировать его, а не перескакивать дальше.
