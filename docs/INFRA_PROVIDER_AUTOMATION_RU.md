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

Check current preview VPN nodes without printing admin token or private keys:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1
```

This command SSHes to the origin, reads `/opt/bluevpn/backend/data/admin_token.txt` only on that host, runs protected admin checks, and prints only a safe status summary.

Check public update manifests and download aliases without changing stable or preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
```

This catches Android/Windows artifact mixups: Android must receive `.apk`, Windows must receive `.exe`, including the legacy `/api/v1/updates/windows` compatibility path.

Check end-to-end scaling readiness in one safe command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_scaling_readiness.ps1
```

Check all configured RUVDS API candidates without printing token values:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_ruvds_access_candidates.ps1
```

RUVDS inventory and rollout scripts can use `GREENVPN_RUVDS_API_KEY`, `GREENVPN_RUVDS_API_KEY_2`, any `GREENVPN_RUVDS_API_KEY_*`, and semicolon/comma-separated `GREENVPN_RUVDS_API_KEYS`. The checks read the local secrets file and standard environment scopes (`Process`, `User`, `Machine`). The selected credential is reported only by source variable names, never by token value. When multiple working RUVDS credentials are present, inventory prefers the candidate with the highest visible balance.

Owner-facing click/action packet:

```text
docs\OWNER_INFRA_NEXT_CLICKS_RU.md
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

Protected emergency NL rollout wrapper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1
```

Paid create requires all three explicit switches:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -AcceptProductionBalanceRisk
```

The `-AcceptProductionBalanceRisk` switch is intentional: this Timeweb account also hosts production Green VPN infrastructure. The wrapper must not spend this balance by accident.

KZ latest full smoke, 2026-06-14: still unreliable. Non-mutating catalog/provisioning checks may pass, but full smoke can fail with remote SSH/WireGuard reachability false. Keep `tw-kz1-test-01` in maintenance and out of preview/stable until it passes repeated full smoke checks.

Timeweb balance visible through API on 2026-06-14: about `1671.5 RUB`.

Known Timeweb quotes:

- NL preset `3344`, location `nl-1`: about `1600 RUB/month`; technically enough balance, but do not auto-create because it would consume almost all current Timeweb production balance.
- KZ preset `2937`, location `kz-1`: about `611 RUB/month`; do not create more KZ before current KZ reliability is understood.

### RUVDS

API works, but the API-visible balance is currently `267 RUB`. The owner reported topping up RUVDS, but that top-up is not visible to the currently configured API credentials yet. Current local secret inventory contains only one RUVDS API token, and that token resolves to the `267 RUB` account. Until the same funded browser account and API token show at least `933 RUB`, paid create commands must stay blocked.

Current server:

- Provider server id: `2584554`.
- Backend server id: `ruvds-2584554-ld8`.
- Location: London / LD8.
- Endpoint: `88.218.250.86:443`.
- Status: hidden from stable, visible only in preview.

Latest protected smoke check, 2026-06-14:

- `remote-provisioning-check`: ok, SSH reachable, WireGuard ready.
- `remote-peer-smoke`: ok, temporary peer created and removed.
- `client-config-smoke`: ok, temporary client config shape valid and smoke peer removed.
- Public catalog split: stable does not contain `ruvds-2584554-ld8`; preview contains it.

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

Preferred end-to-end Zurich rollout wrapper, dry-run by default:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1
```

Expected current result until the correct RUVDS account/token is visible to API:

- `currentBalanceRub=267`
- `quotedCostRub=933`
- `readyToCreate=false`

If the browser panel shows a higher balance, create or copy the RUVDS API v2 token from that same funded account and place it in `D:\GreenVPN_Secrets\provider_api.local.ps1` as `GREENVPN_RUVDS_API_KEY`, any `GREENVPN_RUVDS_API_KEY_*`, or inside `GREENVPN_RUVDS_API_KEYS`. Do not paste it into chat and do not commit it to the repository. Then rerun `check_ruvds_access_candidates.ps1` and the safe gate above.

After the API-visible balance is enough, create the paid Zurich test VPS with the explicit double-confirm command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1 -CreateWhenReady -ConfirmPaidCreate
```

This command still refuses to create anything if the API-visible balance is lower than the quoted cost.

Important RUVDS limitation: current RUVDS API v2 responses for existing servers may return `network_v4=null`. If live-create does not expose the public IPv4, take the IP once from the panel and continue the automated bootstrap chain from that point.

Resume the rollout when the public IPv4 is known:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 `
  -NodeIPv4 <public-ip-from-provider-panel> `
  -ApplyBootstrap `
  -ConfirmRemoteProvision `
  -AddToPreview
```

Post-create remote node bootstrap, dry-run first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\prepare_remote_wireguard_node.ps1 `
  -ServerId ruvds-zurich-test-01 `
  -NodeIPv4 <public-ip-from-provider-panel> `
  -Title "Green VPN RUVDS Zurich Test 01" `
  -Country CH `
  -City Zurich `
  -Provider ruvds
```

Apply the bootstrap, register the node as hidden, and keep it out of preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\prepare_remote_wireguard_node.ps1 `
  -ServerId ruvds-zurich-test-01 `
  -NodeIPv4 <public-ip-from-provider-panel> `
  -Title "Green VPN RUVDS Zurich Test 01" `
  -Country CH `
  -City Zurich `
  -Provider ruvds `
  -Apply `
  -ConfirmRemoteProvision
```

Apply the bootstrap and add the node to preview only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\prepare_remote_wireguard_node.ps1 `
  -ServerId ruvds-zurich-test-01 `
  -NodeIPv4 <public-ip-from-provider-panel> `
  -Title "Green VPN RUVDS Zurich Test 01" `
  -Country CH `
  -City Zurich `
  -Provider ruvds `
  -Apply `
  -ConfirmRemoteProvision `
  -AddToPreview
```

This wrapper creates only origin-side SSH/env material, bootstraps WireGuard on the node, upserts the backend catalog entry as `remote_ssh_wg0`, runs admin smoke checks, and verifies that stable catalog does not contain the new node.

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

Latest preview-node smoke command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1
```

Latest result, 2026-06-14:

- `tw-7879598-nl1`: checks ok; active/public; stable and preview.
- `ruvds-2584554-ld8`: checks ok; hidden from stable; preview only.
- `tw-kz1-test-01`: not part of preview/stable; keep hidden/maintenance because full smoke is unreliable.

## Standard rollout for a new node

1. Quote price with `new_test_vps_plan.ps1 -QuotePrice`.
2. Confirm provider API-visible balance is enough.
3. Create paid VPS with `new_test_vps_plan.ps1 -Apply`.
4. Run `scripts\infra\prepare_remote_wireguard_node.ps1` in dry-run mode with the new public IP.
5. Run the same wrapper with `-Apply -ConfirmRemoteProvision`.
6. Register/update backend managed catalog entry as hidden.
7. Run admin checks:
   - `remote-provisioning-check`
   - `remote-peer-smoke`
   - `client-config-smoke`
8. Add the node only to `GREENVPN_PREVIEW_SERVER_IDS` with `-AddToPreview`.
9. Restart backend.
10. Verify:
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

Use the exact owner-facing sequence in:

```text
docs\OWNER_INFRA_NEXT_CLICKS_RU.md
```
