# Timeweb KZ1 test node — 2026-06-14

## Что сделано

- Создан Timeweb VPS `greenvpn-tw-kz1-test-01`.
- Timeweb server id: `8360589`.
- Backend serverId: `tw-kz1-test-01`.
- Локация: Kazakhstan / Almaty, Timeweb `kz-1`.
- IPv4: `94.198.221.206`.
- ОС: Debian 12.
- WireGuard поднят на `wg0`.
- VPN endpoint: `94.198.221.206:443/udp`.
- Origin-only SSH key создан на origin в `/etc/bluevpn/vpn_nodes/tw-kz1-test-01_ed25519`.
- Backend server-only env создан на origin в `/etc/bluevpn/vpn_nodes/tw-kz1-test-01.env`.
- Capacity reporter установлен на KZ-ноде и использует admin token только из root-only файла на сервере.

## Текущее безопасное состояние

- Managed catalog entry создана.
- `clientConfigProfile=remote_ssh_wg0`.
- `clientConfigReady=true`.
- `status=maintenance`.
- `isActive=false`.
- `isPublic=false`.
- Нода не добавлена в `GREENVPN_PREVIEW_SERVER_IDS`.
- Основной сайт, stable APK/EXE и публичный каталог не менялись.

## Проверки

- `remote-provisioning-check`: ok, origin видит удалённый `wg0`, публичный ключ совпадает с env.
- `remote-peer-smoke`: ok, временный peer добавляется и удаляется, но только после нескольких попыток.
- `client-config-smoke`: нестабильно падает на remote apply из-за SSH banner timeout.
- SSH до `94.198.221.206:22` периодически открывает TCP, но не отдаёт SSH banner.

## Решение по публикации

Ноду нельзя включать даже в preview, пока SSH до KZ нестабилен. Backend выдаёт конфиги для `remote_ssh_wg0` через SSH-команды на удалённый WireGuard-узел. При banner timeout пользователь получит зависание или ошибку получения конфига.

KZ-нода оставлена скрытой как maintenance/test asset. Для рабочей fallback-ноды лучше использовать другого провайдера или другую локацию, где origin-to-node SSH стабилен.

## Секреты

- WireGuard private key не выводился и не записывался в repo.
- Admin token не выводился и не записывался в repo.
- SSH private key не выводился и не записывался в repo.
- Provider API token не выводился и не записывался в repo.
