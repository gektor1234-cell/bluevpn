# Timeweb KZ1 preview status — 2026-06-17

## Узел

- Provider: Timeweb Cloud.
- Timeweb server id: `8360589`.
- Backend serverId: `tw-kz1-test-01`.
- Name: `greenvpn-tw-kz1-test-01`.
- Location: Kazakhstan / Almaty, Timeweb `kz-1`.
- IPv4: `94.198.221.206`.
- VPN endpoint: `94.198.221.206:443/udp`.
- Current Timeweb preset: `2937`, cheapest available KZ preset found by API at this pass.
- Preset resources: 2 CPU, 2 GB RAM, 40 GB disk, 100 Mbps.
- Quoted monthly price from Timeweb API: `611 RUB`.

## Что исправлено

- KZ не проходил стабильный backend smoke из-за нестабильного SSH banner на публичном `22/tcp`.
- На KZ SSH закрыт от внешнего мира и разрешён только с origin `37.220.85.211`.
- На KZ добавлен отдельный backend SSH port `22222/tcp`, также только для origin.
- На origin env узла переключён на `GREENVPN_NODE_PORT=22222`.
- В backend `remote_ssh_wg0` добавлены SSH retries и SSH multiplexing (`ControlMaster`/`ControlPersist`), чтобы один временный banner timeout не ломал выдачу client config.

## Текущее состояние

- Managed catalog entry: `status=healthy`.
- `clientConfigProfile=remote_ssh_wg0`.
- `clientConfigReady=true`.
- `isActive=false`.
- `isPublic=false`.
- Узел добавлен только в `GREENVPN_PREVIEW_SERVER_IDS`.
- Stable/public catalog не изменён.

## Проверка

После исправления `scripts/infra/check_preview_vpn_nodes.ps1 -ServerId tw-kz1-test-01` прошёл:

- `remoteProvisioning.ok=true`.
- `remotePeerSmoke.ok=true`.
- `clientConfigSmoke.ok=true`.
- `publicCatalog.inPreview=true`.
- `publicCatalog.inStable=false`.

## Важно

Пока это preview/test узел. Не переводить в stable/public без отдельного решения и повторной проверки реального подключения с телефона.
