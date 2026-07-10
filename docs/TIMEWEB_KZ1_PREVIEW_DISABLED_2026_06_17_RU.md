# Timeweb KZ1 preview disabled - 2026-06-17

## Summary

KZ test node `tw-kz1-test-01` was removed from the Android/preview server pool.

Reason: full route-smoke from origin to the KZ node is not stable. The node sometimes passes backend provisioning checks, but direct SSH from origin to the node can fail with `Connection timed out during banner exchange`. This makes client config issuance unreliable and matches real-device reports with endless config loading or VPN connected without working YouTube.

## Current state

- Backend serverId: `tw-kz1-test-01`.
- Public host: `94.198.221.206`.
- Catalog status: `maintenance`.
- `isActive=false`.
- `isPublic=false`.
- Stable catalog: does not contain KZ.
- Preview catalog: does not contain KZ.

Current stable catalog:

- `intelligent_smew`
- `tw-7879598-nl1`

Current preview catalog:

- `intelligent_smew`
- `tw-7879598-nl1`
- `ruvds-2584554-ld8`

## Verification

KZ maintenance check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1 -ServerId tw-kz1-test-01 -SkipPeerSmoke -SkipClientConfigSmoke -HttpTimeoutSec 30
```

Expected important fields:

- `catalog.status = maintenance`
- `publicCatalog.inStable = false`
- `publicCatalog.inPreview = false`

Preview working node check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\infra\check_preview_vpn_nodes.ps1' -ServerId @('tw-7879598-nl1','ruvds-2584554-ld8') -HttpTimeoutSec 60"
```

Expected: both nodes pass `remote-provisioning-check`, `remote-peer-smoke`, and `client-config-smoke`.

## Reactivation rule

Do not add KZ back to preview or stable until repeated full route-smoke checks pass:

1. origin can repeatedly SSH to the node without banner timeout;
2. temporary WireGuard peer can pass traffic through the node;
3. Google and YouTube checks pass through the tunnel;
4. a real Android preview device confirms YouTube works after manual KZ selection.

Main/stable release remains untouched.
