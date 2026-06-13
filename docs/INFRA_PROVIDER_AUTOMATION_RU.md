# Green VPN: provider API automation

Цель: сделать так, чтобы новые VPN-узлы можно было поднимать через API провайдеров, но не рисковать основным сайтом и текущими пользователями.

## Текущая граница безопасности

- Основной сайт и основной public catalog не трогаем без отдельного решения владельца.
- Новые серверы сначала создаются как test/preview.
- В backend новый узел сначала регистрируется только как скрытый draft: `isPublic=false`, `isActive=false`, `status=draft`.
- В public catalog узел попадает только после bootstrap WireGuard, remote provisioning check, smoke test и ручного решения.
- FriendlyLynet не трогаем.
- API-ключи, SMTP/SMS/YooKassa secrets, SSH private keys и WireGuard private keys не пишем в repo.

## Где хранить ключи

Основной локальный файл для секретов рядом с проектом:

```powershell
C:\Users\gekto\projects\bluevpn\secrets\provider_api.local.ps1
```

Он игнорируется git через `secrets/`, поэтому не попадает в репозиторий.

Внешняя папка-источник/backup:

```powershell
D:\GreenVPN_Secrets
```

Импорт существующих `*_access.txt` из внешней папки в проектный локальный файл:

```powershell
.\scripts\infra\import_existing_secrets.ps1 -Force
```

Шаблон без реальных значений лежит тут:

```powershell
scripts\infra\provider_secrets.example.ps1
```

В реальном локальном файле должны быть только присваивания env vars:

```powershell
$env:GREENVPN_SERVERSPACE_API_KEY = "..."
$env:GREENVPN_TIMEWEB_TOKEN = "..."
$env:GREENVPN_RUVDS_API_KEY = "..."
$env:BLUEVPN_ADMIN_TOKEN = "..."
```

`GREENVPN_RUVDS_API_KEY` — это RUVDS API v2 bearer token из `https://ruvds.com/my/settings/api`.
Логин/пароль RUVDS для старого `/api/logon/` flow больше не нужен для текущей автоматизации.

HOSTKEY сейчас не входит в рабочий пул. Если позже появится нормальный API-ключ, его можно добавить отдельно как `$env:GREENVPN_HOSTKEY_API_KEY`, но текущая автоматизация не должна блокироваться об него.

Файл `*.local.ps1` игнорируется git.

## Проверка API-доступов

```powershell
.\scripts\infra\test_provider_api.ps1 -Provider all
```

С инвентаризацией без вывода секретов:

```powershell
.\scripts\infra\test_provider_api.ps1 -Provider all -IncludeInventory
```

Что сейчас делает скрипт:

- Timeweb: проверяет список серверов через `GET https://api.timeweb.cloud/api/v1/servers`.
- RUVDS: проверяет `GET https://api.ruvds.com/v2/balance`, `/v2/servers`, `/v2/datacenters`, `/v2/os`, `/v2/tariffs`.
- Serverspace: проверяет проект через `GET https://api.serverspace.io/api/v1/project`.
- HOSTKEY: не входит в `-Provider all`; доступен только ручной проверкой `-Provider hostkey`, пока считается запасным вариантом без live-вызовов.

## Dry-run плана VPS

Serverspace, без покупки:

```powershell
.\scripts\infra\new_test_vps_plan.ps1 `
  -Provider serverspace `
  -Name greenvpn-test-am2-01 `
  -LocationId am2 `
  -ImageId Debian-12-X64 `
  -Cpu 1 `
  -RamMb 1024 `
  -DiskGb 25 `
  -BandwidthMbps 50
```

Реальное создание в Serverspace:

```powershell
.\scripts\infra\new_test_vps_plan.ps1 `
  -Provider serverspace `
  -Name greenvpn-test-am2-01 `
  -LocationId am2 `
  -ImageId Debian-12-X64 `
  -Cpu 1 `
  -RamMb 1024 `
  -DiskGb 25 `
  -BandwidthMbps 50 `
  -Apply
```

`-Apply` тратит деньги у провайдера. Без `-Apply` денег не тратит.

RUVDS London, только расчет цены без создания сервера:

```powershell
.\scripts\infra\new_test_vps_plan.ps1 `
  -Provider ruvds `
  -Name greenvpn-ruvds-ld8-test-01 `
  -LocationId 3 `
  -ImageId 52 `
  -Cpu 1 `
  -RamMb 1024 `
  -DiskGb 20 `
  -PaymentPeriod 2 `
  -RuvdsTariffId 41 `
  -RuvdsDriveTariffId 9 `
  -QuotePrice
```

Текущий безопасный RUVDS baseline:

- `LocationId 3` — LD8 London.
- `LocationId 2` — ZUR1 Zurich как fallback.
- `ImageId 52` — Debian 12.
- `RuvdsTariffId 41` — PremiumEurope.
- `RuvdsDriveTariffId 9` — европейский drive tariff из каталога RUVDS.
- `PaymentPeriod 2` — 1 месяц.
- SSH public key `greenvpn-codex-local` должен быть в RUVDS. Он нужен, чтобы VPS создавался сразу доступным по SSH без вывода стартового пароля в чат.

Реальное создание RUVDS VPS:

```powershell
.\scripts\infra\new_test_vps_plan.ps1 `
  -Provider ruvds `
  -Name greenvpn-ruvds-ld8-test-01 `
  -LocationId 3 `
  -ImageId 52 `
  -Cpu 1 `
  -RamMb 1024 `
  -DiskGb 20 `
  -PaymentPeriod 2 `
  -RuvdsTariffId 41 `
  -RuvdsDriveTariffId 9 `
  -Apply
```

`-Apply` создает платный сервер. Созданный узел остается вне основного сайта до ручного bootstrap/smoke/promote.

## Bootstrap свежего VPN-узла

На новом VPS:

```bash
bash /root/bootstrap_wireguard_node.sh --apply
```

Скрипт:

- ставит WireGuard;
- включает forwarding;
- создает `/etc/wireguard/wg0.conf`;
- запускает `wg-quick@wg0`;
- печатает только public key и безопасные факты.

Private key остается только на сервере.

## Подключение к backend

После создания VPS и bootstrap:

1. Завести backend-only файл на origin:

```bash
/etc/bluevpn/vpn_nodes/<serverId>.env
```

2. Указать там host, SSH key path, public host/port, WG public key и interface.
3. Запустить `remote-provisioning-check`.
4. Запустить `remote-peer-smoke`.
5. Запустить `client-config-smoke`.
6. Только после этого решать, добавлять ли узел в preview или public pool.

## Источники API

- Serverspace Public API: `https://serverspace.io/support/help/automation/`
- Timeweb Cloud API: `https://timeweb.cloud/api-docs`
- RUVDS API v2: `https://ruvds.com/api-docs/`
- HOSTKEY Invapi/API docs: `https://hostkey.com/documentation/apidocs/`
