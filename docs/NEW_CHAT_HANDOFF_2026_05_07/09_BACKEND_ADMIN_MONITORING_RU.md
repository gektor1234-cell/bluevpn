# Backend, admin monitoring и health scoring

## Backend source

`C:\Users\gekto\projects\bluevpn\backend_live\app\main.py`

Последняя подтвержденная live версия: `0.9.67`.

## Monitoring/admin features

Уже реализованы:

- server catalog;
- current endpoint health scoring;
- server-health observations;
- external monitoring probe groundwork;
- incidents;
- alert readiness;
- launch readiness aggregator;
- API/VPN endpoint split readiness;
- public site readiness;
- payment smoke readiness;
- payment-smoke-gated renewals/expiry readiness;
- user auth flow readiness;
- launch closure plan;
- owner launch packet;
- server-enforced owner-action note secret guard;
- API/VPN split-plan preflight metadata and command;
- new VPS onboarding plan;
- safe VPS draft workflow;
- promo readiness.

## Важные admin endpoints

- `GET /api/v1/admin/server-catalog`
- `GET /api/v1/admin/server-health`
- `POST /api/v1/admin/server-health/probe-current`
- `GET /api/v1/admin/monitoring/readiness`
- `GET /api/v1/admin/monitoring/probes`
- `GET /api/v1/admin/network/readiness`
- `GET /api/v1/admin/network/split-plan` includes mutation-free `check_api_vpn_split_preflight.ps1` metadata
- `GET /api/v1/admin/site/readiness`
- `GET /api/v1/admin/billing/payment-smoke/readiness`
- `GET /api/v1/admin/auth/user-flow/readiness`
- `GET /api/v1/admin/launch/readiness`
- `GET /api/v1/admin/launch/closure-plan`
- `GET /api/v1/admin/launch/owner-packet`
- `POST /api/v1/admin/external-actions/{action_code}` rejects secret-looking owner notes before DB/audit writes
- `GET /api/v1/admin/billing/promos/readiness`
- `POST /api/v1/admin/billing/promos/draft-start-campaign`

## Health scoring rules

Health scoring должен быть внутренним и безопасным:

- проверяет `wg0`;
- проверяет признаки конфига;
- проверяет peer/handshake;
- проверяет UDP endpoint;
- считает score `0-100`;
- не пишет private keys;
- не пишет full configs;
- не раскрывает admin token.

## Readiness checker

Основной файл:

`C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1`

Команда:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json
```

Ожидаемый red до production:

- API/VPN endpoint split.

Это не backend outage. Это инфраструктурный блокер разделения IP.
