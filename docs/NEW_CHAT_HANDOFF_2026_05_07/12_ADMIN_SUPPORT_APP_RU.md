# Admin/support app

## Где лежит

`C:\Users\gekto\projects\bluevpn\admin_support_app`

Основные файлы:

- `C:\Users\gekto\projects\bluevpn\admin_support_app\index.html`
- `C:\Users\gekto\projects\bluevpn\admin_support_app\app.js`
- `C:\Users\gekto\projects\bluevpn\admin_support_app\styles.css`

## Назначение

Это отдельное внутреннее приложение для владельца/админа/поддержки.

Не возвращать его в обычный пользовательский Green VPN client.

## Уже есть

- staff login/session flow;
- RBAC roles;
- 2FA;
- user search/detail;
- devices;
- billing/orders;
- support reports/comments;
- audit;
- feature flags;
- runbooks;
- support actions;
- monitoring/readiness;
- server catalog;
- incident/admin alerts;
- launch readiness;
- promo readiness and safe START20 draft;
- structured API error formatting without `[object Object]`;
- client-side owner note precheck before backend submit;
- owner launch packet card in production readiness.

## Ссылки

Public site:

`https://api.greenvpn.pro/`

Admin/support app локально:

`C:\Users\gekto\projects\bluevpn\admin_support_app\index.html`

Если нужен local server, можно поднять статический сервер в этой папке, но не хранить admin token в файлах.

## Свежий polish

- Backend live остаётся `0.9.63`; этот polish меняет только separate `admin_support_app`.
- `apiGet`/`apiPost` форматируют object/array `detail` безопаснее: validation errors показываются как понятный текст, sensitive fallback fields редактируются.
- Owner-action note textarea проверяется до `POST /api/v1/admin/external-actions/{action_code}`. Очевидные private keys, bearer/admin tokens, password/secret/provider env assignments блокируются локально; server-side guard всё равно остаётся главным.
- После backend `0.9.64` раздел `Готовность` также показывает `GET /api/v1/admin/launch/owner-packet`: owner commands, pending owner inputs and after-apply checks without secret values.
- После backend `0.9.65` карточки renewals/expiry показывают, что safe-enable signals требуют clean payment smoke.
- После backend `0.9.66` owner packet commands включают `payment_launch_safety`.
- После backend `0.9.67` owner packet commands включают `monitoring_probe_plan`.

## Проверки

Node в этой desktop-сессии может быть заблокирован Windows permissions. Использовать QuickJS syntax check:

```powershell
cd C:\Users\gekto\projects\bluevpn
python -c "from pathlib import Path; import quickjs, json; code=Path('admin_support_app/app.js').read_text(encoding='utf-8'); quickjs.Context().eval('new Function(' + json.dumps(code) + ')'); print('admin_support_app/app.js syntax OK via quickjs')"
```
