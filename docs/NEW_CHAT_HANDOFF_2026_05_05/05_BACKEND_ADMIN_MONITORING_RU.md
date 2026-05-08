# Backend, admin API, server catalog и monitoring

## Текущая цель

Завершить текущий этап плана: внутренний мониторинг endpoint и оценка здоровья серверов для админки.

Пользовательский VPN-клиент и installer не трогаем, если изменения относятся только к backend/admin support app.

Публичный клиентский catalog остаётся безопасным и не начинает выдавать managed endpoints пользователям автоматически.

## Backend version

Целевая версия:

`0.9.11`

Файл:

`C:\Users\gekto\projects\bluevpn\backend_live\app\main.py`

Переменная:

`APP_VERSION = "0.9.11"`

Server:

`37.220.85.211`

API:

`https://api.greenvpn.pro`

## Public catalog

Правильный публичный URL:

`GET /api/v1/catalog/servers`

Не использовать старый/ошибочный путь:

`/api/v1/server-catalog`

Публичный catalog должен быть безопасным:

- не публикует приватные ключи;
- не публикует internal managed endpoints автоматически;
- не выдаёт то, что не предназначено для пользователей;
- может отдавать builtin/safe catalog.

## Admin health flow

Нужные endpoints:

- `GET /api/v1/admin/server-catalog`
- `GET /api/v1/admin/server-health`
- `POST /api/v1/admin/server-health/probe-current`

Admin token:

- вводится вручную;
- не хранится в repo;
- не выводится в чат;
- не логируется.

## Health scoring

Health scoring должен быть внутренним:

- проверяет `wg0`;
- проверяет config presence;
- проверяет peer/handshake;
- проверяет UDP endpoint;
- проверяет latency/packet loss там, где это безопасно;
- сохраняет score `0-100`;
- сохраняет только безопасные технические признаки;
- не пишет ключи, токены, приватные конфиги;
- не выводит WireGuard private keys.

Безопасные признаки:

- `endpoint_id`;
- `status`;
- `score`;
- `latency_ms`;
- `packet_loss`;
- `last_handshake_age_sec`;
- `has_recent_handshake`;
- `rx_bytes`;
- `tx_bytes`;
- `wg_interface_present`;
- `config_present`;
- `udp_endpoint_reachable`;
- `observed_at`;
- короткие reason codes.

Небезопасные данные:

- private key;
- preshared key;
- full raw config;
- admin token;
- SSH password;
- payment secrets;
- SMTP password;
- SMS token.

## Русские формулировки в админке

Использовать:

- `Наблюдения здоровья`
- `Оценка здоровья`
- `Проверить текущий endpoint`
- `Задержка`
- `потери`
- `статус`
- `score`
- `Последняя проверка`
- `Причины`
- `Рекомендация`

Не использовать англо-русскую кашу в пользовательских названиях, кроме технических компактных полей вроде `score`.

## Monitoring probes

Первый слой:

- backend-local probe;
- проверка текущего `wg0`;
- проверка API/catalog;
- запись результата в backend/admin;
- отображение в admin_support_app.

Следующий слой:

- отдельный маленький monitoring VPS;
- `scripts\monitoring\service_probe.py`;
- `scripts\monitoring\install_probe_systemd.sh`;
- проверка доступности YouTube/Discord/Telegram через controlled agent;
- отправка безопасных observations на backend.

## Что не делать сейчас

- Не переключать обычных пользователей на managed catalog автоматически.
- Не строить full multi-country resilience до покупки новых серверов.
- Не тащить admin health UI в пользовательский Green VPN.
- Не добавлять новые пользовательские вкладки без явной необходимости.

## Проверки

Локально:

```powershell
cd C:\Users\gekto\projects\bluevpn
python -m py_compile backend_live\app\main.py
```

Admin app syntax check:

```powershell
cd C:\Users\gekto\projects\bluevpn
@'
import json, pathlib, quickjs
code = pathlib.Path('admin_support_app/app.js').read_text(encoding='utf-8')
ctx = quickjs.Context()
ctx.eval('new Function(' + json.dumps(code) + ')')
print('quickjs app.js syntax ok')
'@ | python -
```

Server:

```powershell
wsl.exe curl -fsS http://37.220.85.211:8000/healthz
wsl.exe curl -fsS http://37.220.85.211:8000/api/v1/catalog/servers
```

Admin endpoints проверять с token, но token не печатать.
