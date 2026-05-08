# Server catalog, новые VPS и API/VPN split

## Текущий сервер

- Backend/VPN server: `37.220.85.211`
- Current VPN endpoint internal id: `intelligent_smew`
- Current tunnel/config internal name: `BlueVPNDev1`

## Public catalog

Пользовательский endpoint:

`GET /api/v1/catalog/servers`

Публичный клиентский catalog должен оставаться безопасным. Managed/draft endpoints не должны становиться видимыми пользователям автоматически.

## New VPS onboarding

Для будущих серверов уже подготовлен safe draft workflow.

Имена:

- `nl1.vpn.greenvpn.pro`
- `de1.vpn.greenvpn.pro`
- `kz1.vpn.greenvpn.pro`

Safe defaults для нового VPS:

- `status=draft`
- `isPublic=false`
- `isActive=false`
- `clientConfigProfile=none`
- `healthScore=0`

Admin endpoint:

`POST /api/v1/admin/server-catalog/draft-from-plan`

## API/VPN endpoint split

Текущий red blocker:

`api.greenvpn.pro` и VPN endpoint оба указывают на `37.220.85.211`.

Симптом: при включенном full-tunnel VPN браузер может не открывать `https://api.greenvpn.pro`, а без VPN сайт открывается.

Решение перед public release:

- API/site на отдельный IP или reverse proxy;
- VPN endpoint на отдельный host, например `nl1.vpn.greenvpn.pro -> 37.220.85.211`;
- обновить DNS и backend/server catalog;
- проверить, что сайт открывается при включенном Green VPN.

Admin plan endpoint:

`GET /api/v1/admin/network/split-plan`

Сейчас endpoint уже отдаёт mutation-free preflight command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_api_vpn_split_preflight.ps1 -ApiBase https://api.greenvpn.pro -VpnEndpointHost nl1.vpn.greenvpn.pro -ExpectedVpnIp 37.220.85.211 -ExpectedApiIp <new-api-site-ip> -Json
```

Скрипт secret-free и не меняет DNS/server/backend. Он только проверяет HTTPS URL, DNS, expected IP, пересечение API/VPN IP и `/healthz`.
