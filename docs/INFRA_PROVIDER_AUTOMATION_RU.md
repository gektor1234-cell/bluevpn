# Green VPN: provider automation runbook

Goal: create and validate new VPN exit nodes through provider APIs without touching the public stable product. Every new node starts in the test/preview contour.

## Safety boundary

- Do not change the main public site, stable APK/EXE, stable update manifests, or stable public catalog without an explicit owner decision.
- Register new nodes first as hidden test nodes: `isPublic=false`, `isActive=false`, or hidden by preview allowlist only.
- A node may enter preview only after WireGuard bootstrap, origin-only env, admin smoke checks, and explicit preview allowlist.
- `Friendly Linnet` is personal/no-touch.
- Do not commit or print provider API keys, SMTP/SMS/YooKassa secrets, SSH private keys, or WireGuard private keys.

## Secret files

Primary local secret store:

```powershell
D:\GreenVPN_Secrets\provider_api.local.ps1
```

Project-local fallback secret store:

```powershell
secrets\provider_api.local.ps1
```

Committed template only:

```powershell
scripts\infra\provider_secrets.example.ps1
```

Provider scripts load `D:\GreenVPN_Secrets\provider_api.local.ps1` first, then `secrets\provider_api.local.ps1`. The real secret files must stay uncommitted.

Check all provider APIs without printing secret values:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\test_provider_api.ps1 -Provider all -IncludeInventory
```

## Current API status, 2026-06-14

### Timeweb

API works. Current inventory has 5 servers:

- `Friendly Linnet`, IP `5.129.237.163` - personal/no-touch.
- `Intelligent Smew`, IP `37.220.85.211` - origin/backend/current node.
- `Friendly Cetus`, IP `72.56.32.197` - site/proxy/monitoring.
- `GreenVPN NL1 VPN 20260511`, IP `5.129.216.42` - working NL VPN node.
- `greenvpn-tw-kz1-test-01`, IP `94.198.221.206` - hidden KZ test node, not in preview/stable.

Timeweb live-create support exists in `scripts\infra\new_test_vps_plan.ps1` when pinned Timeweb IDs are passed. Existing working NL nodes stay unchanged.

### RUVDS

API works, but the API-visible balance is currently `267 RUB`. The owner reported topping up RUVDS, but that top-up is not visible to the currently configured API credentials yet.

Current server:

- Provider server id: `2584554`.
- Backend server id: `ruvds-2584554-ld8`.
- Location: London / LD8.
- Endpoint: `88.218.250.86:443`.
- Status: hidden from stable, visible only in preview.

Available target locations from current API inventory:

- `3` - LD8 London.
- `2` - ZUR1 Zurich.

Known image/tariff values:

- Debian 12 image: `52`.
- Europe VPS tariff: `41`.
- Drive tariff: `9`.
- SSH key exists in provider account: `greenvpn-codex-local`.

Zurich dry-run quote:

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

Last dry-run price: `933 RUB`. With API-visible balance `267 RUB`, live-create is intentionally blocked until the API-visible balance is enough.

Preferred safe gate for Zurich:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\ruvds_zurich_gate.ps1
```

Expected current result until the correct RUVDS account/token is visible to API:

- `currentBalanceRub=267`
- `quotedCostRub=933`
- `readyToCreate=false`

After the API-visible balance is enough, create the paid Zurich test VPS with the explicit double-confirm command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\ruvds_zurich_gate.ps1 -ApplyWhenReady -ConfirmPaidCreate
```

This command still refuses to create anything if the API-visible balance is lower than the quoted cost.

Important RUVDS limitation: current RUVDS API v2 responses for existing servers may return `network_v4=null`. If live-create does not expose the public IPv4, take the IP once from the panel and continue the automated bootstrap chain from that point.

### Serverspace

API works. Current balance is `0.50 EUR`, server count is `0`. Keep it as a prepared alternative; do not create servers until funded.

### HOSTKEY

Not in the working automation pool. API access was not confirmed.

## Current stable/preview split

Stable catalog currently exposes only:

- `intelligent_smew`
- `tw-7879598-nl1`

Preview catalog currently exposes:

- `intelligent_smew`
- `tw-7879598-nl1`
- `ruvds-2584554-ld8`

Do not add KZ or new nodes to stable. Add new nodes to preview first and test on Android/Windows before any stable decision.

## Standard rollout for a new node

1. Quote price with `new_test_vps_plan.ps1 -QuotePrice`.
2. Confirm provider API-visible balance is enough.
3. Create paid VPS with `new_test_vps_plan.ps1 -Apply`.
4. Wait for SSH.
5. Bootstrap WireGuard on the VPS with the server bootstrap script.
6. Create origin-only env file under `/etc/bluevpn/vpn_nodes/<serverId>.env`.
7. Register/update backend managed catalog entry as hidden.
8. Run admin checks:
   - `remote-provisioning-check`
   - `remote-peer-smoke`
   - `client-config-smoke`
9. Add the node only to `GREENVPN_PREVIEW_SERVER_IDS`.
10. Restart backend.
11. Verify:
   - stable catalog does not contain the new node;
   - preview catalog contains the new node;
   - Android preview can connect;
   - Windows preview can obtain config and connect, if applicable.

## Useful commands

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

Catalog check:

```powershell
$stable = Invoke-RestMethod -Uri 'https://api.greenvpn.pro/api/v1/catalog/servers?channel=stable&appVersion=0.2.26'
$preview = Invoke-RestMethod -Uri 'https://api.greenvpn.pro/api/v1/catalog/servers?channel=preview&appVersion=0.2.26-adgate-preview'
$stable.catalog.servers | Select-Object id,title
$preview.catalog.servers | Select-Object id,title
```

## Links

- RUVDS API docs: https://ruvds.com/api-docs/
- RUVDS API settings: https://ruvds.com/my/settings/api
- Serverspace panel: https://my.serverspace.io/
- Serverspace API docs: https://serverspace.io/support/help/automation/
- Timeweb API docs: https://timeweb.cloud/api-docs

## Next owner action

Open RUVDS and check whether the account shown in the browser is the same account as the configured API token. The configured API currently sees only `267 RUB`; server creation can continue once this API-visible balance is at least `933 RUB` for Zurich.
