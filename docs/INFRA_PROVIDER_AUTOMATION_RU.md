# Green VPN: automation for VPN node providers

Цель: поднимать новые VPN-узлы через API провайдеров, не трогая основной сайт и текущих пользователей. Все новые узлы сначала идут только в `test/preview`.

## Safety boundary

- Основной сайт, stable APK/EXE и public catalog не менять без отдельного решения.
- Новые узлы регистрировать сначала как скрытые draft/test nodes: `isPublic=false`, `isActive=false`, `status=draft`.
- В preview catalog узел попадает только после WireGuard bootstrap, backend env, smoke checks и отдельного включения preview allowlist.
- `Friendly Linnet` не трогать.
- API keys, SMTP/SMS/YooKassa secrets, SSH private keys и WireGuard private keys не писать в repo.

## Secrets

Источник истины для локальных секретов:

```powershell
D:\GreenVPN_Secrets\provider_api.local.ps1
```

Repo хранит только пример:

```powershell
scripts\infra\provider_secrets.example.ps1
```

Импорт существующих access-файлов во внешний secrets-файл:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\import_existing_secrets.ps1 -Force
```

Проверка, что секреты загружаются, без вывода значений:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider all
```

## Current API status, 2026-06-14

### Timeweb

API работает. Видит 4 сервера:

- `Friendly Linnet` — личный/no-touch.
- `Intelligent Smew` — origin/VPN/backend.
- `Friendly Cetus` — site/proxy/monitoring.
- `GreenVPN NL1 VPN 20260511` — NL VPN node.

Live-create в `new_test_vps_plan.ps1` пока намеренно отключён, потому что для безопасной покупки надо зафиксировать точные Timeweb configuration IDs. Читать inventory можно.

### RUVDS

API v2 работает.

- Баланс на момент проверки: `267 RUB`.
- Текущий сервер: `2584554`, backend serverId `ruvds-2584554-ld8`.
- Доступные целевые локации из текущего API-инвентаря:
  - `3` — LD8 London.
  - `2` — ZUR1 Zurich.
- Debian 12 image: `52`.
- SSH key `greenvpn-codex-local` есть в аккаунте.

Dry-run Zurich node:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\new_test_vps_plan.ps1 `
  -Provider ruvds `
  -Name greenvpn-ruvds-zurich-test-01 `
  -LocationId 2 `
  -ImageId 52 `
  -Cpu 1 `
  -RamMb 1024 `
  -DiskGb 20 `
  -PaymentPeriod 2 `
  -RuvdsTariffId 41 `
  -RuvdsDriveTariffId 9 `
  -ServerId ruvds-zurich-test-01 `
  -Title "Green VPN RUVDS Zurich Test 01" `
  -Country Switzerland `
  -City Zurich `
  -QuotePrice
```

Текущая цена dry-run: `933 RUB`; минимум докинуть при балансе `267 RUB`: `666 RUB`. Практичный запас: пополнить RUVDS минимум на `1500 RUB`.

Ограничение: RUVDS API v2 в текущем ответе `/v2/servers/{id}` не отдаёт публичный IPv4 в server object (`network_v4=null` у существующей ноды). Если после live-create API тоже не отдаст IP, нужен либо старый/другой RUVDS endpoint для IP, либо разово взять IP из панели. Остальная цепочка после IP автоматизируема.

### Serverspace

API работает.

- Проект активен.
- Серверов сейчас `0`.
- Баланс на момент проверки: `0.50 EUR`.

Создание через API технически доступно в `new_test_vps_plan.ps1`, но перед live-create нужен баланс. Этот провайдер держим как альтернативу, если RUVDS окажется неудобен из-за IP в API.

### HOSTKEY

Не входит в рабочий пул. API key пока не подтверждён, live calls отключены.

## Provider check commands

All providers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider all -IncludeInventory
```

RUVDS only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider ruvds -IncludeInventory
```

Serverspace only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider serverspace -IncludeInventory
```

## Standard node rollout

1. Quote price with `new_test_vps_plan.ps1 -QuotePrice`.
2. Top up provider balance if needed.
3. Create paid VPS with `new_test_vps_plan.ps1 -Apply`.
4. Wait for VPS to become reachable by SSH.
5. Run WireGuard bootstrap on the VPS with `scripts/server/bootstrap_wireguard_node.sh --apply`.
6. Create origin-only env file:

```bash
/etc/bluevpn/vpn_nodes/<serverId>.env
```

7. Register/update backend draft entry.
8. Run admin checks:
   - `remote-provisioning-check`
   - `remote-peer-smoke`
   - `client-config-smoke`
9. Add the node only to `GREENVPN_PREVIEW_SERVER_IDS`.
10. Restart backend and verify:
   - stable catalog does not contain the new node;
   - preview catalog contains the new node;
   - Android preview can connect.

## Owner actions needed next

1. Пополнить RUVDS минимум на `1500 RUB`, если хотим создать Zurich fallback.
2. Пополнить Serverspace, если хотим проверить альтернативного провайдера.
3. Не менять основной сайт и stable-релизы, пока preview не подтверждён реальным Android smoke.

## API links

- RUVDS API: https://ruvds.com/api-docs/
- RUVDS API settings: https://ruvds.com/my/settings/api
- Serverspace API: https://serverspace.io/support/help/automation/
- Serverspace panel: https://my.serverspace.io/
- Timeweb API: https://timeweb.cloud/api-docs

## Update 2026-06-14: Timeweb KZ test

- `new_test_vps_plan.ps1` now supports Timeweb live-create after pinned IDs are passed explicitly.
- Created hidden Timeweb KZ test VPS `tw-kz1-test-01`, Timeweb id `8360589`, IPv4 `94.198.221.206`.
- WireGuard bootstrap and origin-only `remote_ssh_wg0` env are done.
- Backend entry is hidden: `status=maintenance`, `isActive=false`, `isPublic=false`.
- Do not add this node to `GREENVPN_PREVIEW_SERVER_IDS` yet: origin-to-node SSH is unstable and sometimes fails at SSH banner exchange.
- Detailed note: `docs/TIMEWEB_KZ1_TEST_NODE_2026_06_14_RU.md`.
