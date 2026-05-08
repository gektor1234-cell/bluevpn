# Секреты и приватные данные

## Нельзя писать в чат/docs/repo

- `YOOKASSA_SECRET_KEY`
- SMTP app password
- SMS.ru `api_id`
- Telegram bot token
- admin token
- SSH/root password
- WireGuard private key
- full private WireGuard config
- database passwords
- production env file contents

## Можно писать

- имена env-переменных;
- public URLs;
- non-secret `shopId`, если владелец сам согласен;
- masked values;
- placeholder вроде `<YOOKASSA_SECRET_KEY>`.

## Куда вводить секреты

Только через:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\configure_backend_env_wsl.ps1
```

Скрипт пишет на сервер:

`/etc/bluevpn/backend.env`

Не выводить содержимое этого файла.

## Если пользователь вставил секрет в чат

Не повторять его в ответе.

Сказать коротко:

- что секрет увиден;
- что его нельзя сохранять в docs/repo;
- что лучше позже перевыпустить/rotate, если сервис позволяет;
- продолжить настройку через safe script.

## Support reports

Support reports должны быть безопасными:

- без private keys;
- без tokens/passwords;
- без full configs;
- только masked identifiers и диагностические признаки.
