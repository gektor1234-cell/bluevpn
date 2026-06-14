# Green VPN: что нажимать владельцу по инфраструктуре

Цель: довести серверный пул до нормального масштабирования, не трогая основной стабильный сайт и не ломая текущих пользователей.

Секреты, API keys, SMTP/SMS/YooKassa secrets, SSH private keys и WireGuard private keys сюда не писать.

## Текущее состояние

- Основной сайт и stable catalog не трогаем.
- Preview/test можно менять.
- Timeweb API работает.
- RUVDS API работает, но видит баланс `267 RUB`, а не пополнение на `1200 RUB`.
- Serverspace API работает, но баланс `0.50 EUR`, серверов нет.
- Friendly Linnet не трогать.
- Preview smoke сейчас зелёный для:
  - `tw-7879598-nl1`;
  - `ruvds-2584554-ld8`.
- KZ `tw-kz1-test-01` держать в maintenance: полный smoke нестабилен.

## Одна команда для текущей картины

Запускать из проекта:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

Смысл результата:

- `providers.timeweb.status=ok` - Timeweb API жив.
- `providers.ruvds.status=ok` - RUVDS API жив.
- `createOptions.ruvdsZurich.readyToCreate=true` - можно создавать RUVDS Zurich.
- `previewSmoke.ok=true` - текущие preview-ноды проходят smoke.

## RUVDS: что сделать владельцу

Прямая ссылка:

[RUVDS API settings](https://ruvds.com/my/settings/api)

Действия:

1. Открой RUVDS под аккаунтом, где виден баланс около `1200 RUB` или больше.
2. Открой `Настройки` -> `Информация API` / `API V2`.
3. Создай новый API v2 token или скопируй существующий из этого же аккаунта.
4. Не отправляй token в чат.
5. Открой локальный файл:

```text
D:\GreenVPN_Secrets\provider_api.local.ps1
```

6. Замени только значение:

```powershell
$env:GREENVPN_RUVDS_API_KEY = "PASTE_RUVDS_API_V2_TOKEN_HERE"
```

7. Сохрани файл.
8. Я проверяю:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

Ожидаемый признак готовности:

```text
createOptions.ruvdsZurich.readyToCreate = true
```

Сухая проверка полного Zurich rollout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1
```

После этого я сам запускаю единый безопасный wrapper для платного создания:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -CreatePaidServer -ConfirmPaidCreate
```

Дальше я сам:

1. беру IP нового VPS;
2. запускаю `prepare_remote_wireguard_node.ps1`;
3. ставлю WireGuard;
4. добавляю узел hidden;
5. гоняю smoke;
6. добавляю только в preview;
7. проверяю stable/preview split.

Если RUVDS API создаст VPS, но не вернёт публичный IPv4, владелец один раз копирует IP из панели, а я продолжаю так:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview
```

## Timeweb: что уже можно, но пока не делаем

Прямая ссылка:

[Timeweb Cloud servers](https://timeweb.cloud/my/servers)

API сейчас видит баланс примерно `1682 RUB`.

Timeweb NL preset `3344` стоит примерно `1600 RUB/month`. Технически его можно создать, но это съест почти весь текущий Timeweb balance, где держатся production-сервера. Поэтому:

- не создаём новый Timeweb NL без отдельного решения;
- не создаём новые KZ, потому что текущий KZ smoke нестабилен;
- текущие рабочие NL-сервера оставляем.

Если понадобится emergency Timeweb NL, сначала владелец должен явно подтвердить, что можно потратить почти весь текущий Timeweb balance.

## Serverspace

Прямая ссылка:

[Serverspace panel](https://my.serverspace.io/)

Сейчас:

- API работает;
- баланс `0.50 EUR`;
- серверов нет.

Пока не используем. Если RUVDS не получится, пополнить Serverspace и дальше использовать его как альтернативный provider.

## Что не делать

- Не трогать основной stable сайт.
- Не добавлять новые ноды сразу в stable.
- Не возвращать старый Timeweb Frankfurt.
- Не включать KZ в preview/stable до повторяемого полного smoke.
- Не удалять/останавливать Friendly Linnet.
- Не писать секреты в repo, docs или чат.

## Быстрые проверки для меня

Provider inventory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider all -IncludeInventory
```

Preview VPN smoke:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1
```

RUVDS paid-create gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\ruvds_zurich_gate.ps1
```
