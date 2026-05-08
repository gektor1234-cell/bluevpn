# Green VPN: быстрый демо-набор

Дата: 2026-05-08

Это не финальный публичный релиз, а быстрый комплект "показать, что уже работает".

## Что открыть

1. Установщик Windows:

   `01_INSTALLER\GreenVPN_Setup_DEMO.exe`

2. Локальный сайт:

   `http://127.0.0.1:8088`

3. Локальная админка:

   `http://127.0.0.1:8090`

4. API health:

   `https://api.greenvpn.pro/healthz`

## Что говорить при показе

- Это Windows MVP Green VPN.
- Установщик уже собран и брендирован.
- Клиент умеет auth, тарифы, оплату, VPN connect/disconnect, tray/background/autostart, Social Only.
- Backend живой: `0.9.69`.
- ЮKassa production подключена, минимальный live-платеж прошел.
- API и VPN endpoint разведены по разным IP:
  - API: `api.greenvpn.pro -> 72.56.32.197`;
  - VPN endpoint: `nl1.vpn.greenvpn.pro -> 37.220.85.211`.
- Админка отдельная от пользовательского клиента: users, orders, support, readiness, monitoring, incidents, feature flags, releases, runbooks.

## Честные недочеты

- `greenvpn.pro` сейчас еще парковочная страница REG.RU, поэтому для показа используется локальный демо-сайт.
- `www.greenvpn.pro` сейчас не готов по TLS.
- Финальный installer/update artifact еще не выпускался после backend `0.9.69`.
- External monitoring probe и Telegram admin alerts еще нужно подключить.
- Code signing еще нет.

## Важное правило

Не показывать и не писать в чат/repo реальные admin token, YooKassa secret key, SMTP/SMS/Telegram secrets, SSH пароли и WireGuard private keys.
