# Green VPN: следующие действия владельца по инфраструктуре

Цель: расширять серверный пул через API-провайдеров, не трогая основной стабильный сайт и текущих пользователей.

Секреты, API keys, SMTP/SMS/YooKassa secrets, SSH private keys и WireGuard private keys сюда не писать.

## Текущее состояние

- Основной сайт и stable catalog не трогаем.
- Preview/test можно менять и использовать для новых серверов.
- Timeweb API работает.
- RUVDS API работает, но текущий API-доступ видит баланс `267 RUB`, поэтому платное создание Zurich пока заблокировано.
- Serverspace API работает, но баланс `0.50 EUR`, серверов нет.
- Friendly Linnet не трогать.
- Preview smoke зелёный для:
  - `tw-7879598-nl1`;
  - `ruvds-2584554-ld8`.
- KZ `tw-kz1-test-01` держать в maintenance: полный smoke нестабилен.

## Быстрая картина

Запускать из проекта:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

Ожидаемые признаки готовности к новому RUVDS Zurich:

```text
providers.ruvds.accessCandidates.readyCandidateFound = true
createOptions.ruvdsZurich.readyToCreate = true
```

Сейчас это ещё не готово, потому что API видит только `267 RUB`.

Отдельная безопасная проверка всех RUVDS API-кандидатов:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_ruvds_access_candidates.ps1
```

Проверка публичных update/download ссылок:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
```

Она проверяет, что Android получает APK, Windows получает EXE, а legacy update endpoint не отдаёт телефону Windows installer.

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

6. Замени значение основного ключа или добавь второй ключ:

```powershell
$env:GREENVPN_RUVDS_API_KEY = "PASTE_RUVDS_API_V2_TOKEN_HERE"
$env:GREENVPN_RUVDS_API_KEY_2 = "PASTE_SECOND_RUVDS_API_V2_TOKEN_HERE"
```

7. Сохрани файл.
8. После этого я проверяю:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_ruvds_access_candidates.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

Если RUVDS готов, сухая проверка Zurich rollout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1
```

Платное создание:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview
```

Дальше автоматика:

1. получает IP нового VPS;
2. запускает `prepare_remote_wireguard_node.ps1`;
3. ставит WireGuard;
4. добавляет узел hidden;
5. гоняет smoke;
6. добавляет только в preview;
7. проверяет stable/preview split.

Если RUVDS API создаст VPS, но не вернёт публичный IPv4, владелец один раз копирует IP из панели, а я продолжаю так:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview
```

## Timeweb

Прямая ссылка:

[Timeweb Cloud servers](https://timeweb.cloud/my/servers)

API сейчас видит баланс примерно `1671 RUB`.

Timeweb NL preset `3344` стоит примерно `1600 RUB/month`. Технически его можно создать, но это съест почти весь текущий Timeweb balance, где держатся production-сервера. Поэтому:

- новый Timeweb NL не создаём без отдельного решения;
- новые KZ не создаём, пока текущий KZ smoke нестабилен;
- текущие рабочие NL-сервера оставляем.

Безопасная сухая проверка emergency Timeweb NL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1
```

Платное создание только при явном принятии риска списания почти всего Timeweb production-баланса:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -AcceptProductionBalanceRisk
```

Дальше автоматика держит новый узел скрытым, ставит WireGuard, гоняет smoke и добавляет только в preview. Stable не трогается.

## Serverspace

Прямая ссылка:

[Serverspace panel](https://my.serverspace.io/)

Сейчас:

- API работает;
- баланс `0.50 EUR`;
- серверов нет.

Пока не используем. Если RUVDS не получится, можно пополнить Serverspace и использовать его как альтернативного провайдера.

## Что не делать

- Не трогать основной stable сайт.
- Не добавлять новые ноды сразу в stable.
- Не возвращать старый Timeweb Frankfurt.
- Не включать KZ в preview/stable до повторяемого полного smoke.
- Не удалять и не останавливать Friendly Linnet.
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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1
```
