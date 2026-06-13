# RUVDS VPN Node 2026-06-14

## Что сделано

- Создан RUVDS VPS для тестового VPN-узла Green VPN.
- Provider server id: `2584554`.
- Backend/catalog serverId: `ruvds-2584554-ld8`.
- Локация: London, United Kingdom.
- IPv4: `88.218.250.86`.
- ОС: Debian GNU/Linux 12 bookworm.
- WireGuard поднят на `wg0`.
- VPN endpoint: `88.218.250.86:443/udp`.
- VPN subnet: `10.10.0.0/24`.
- IPv4 forwarding включён.
- `wg-quick@wg0` включён и активен.
- На origin `37.220.85.211` создан server-only env:
  `/etc/bluevpn/vpn_nodes/ruvds-2584554-ld8.env`.
- На origin создан отдельный root-only SSH-ключ для управления этой нодой:
  `/etc/bluevpn/vpn_nodes/ruvds-2584554-ld8_ed25519`.
- Публичная часть origin-key добавлена в `authorized_keys` на RUVDS-ноде.
- Установлен capacity reporter:
  `greenvpn-vpn-capacity-report.timer`.
- Reporter отправляет capacity и peer counters для `ruvds-2584554-ld8`.

## Текущее безопасное состояние

- Managed catalog entry создана и проверена.
- `status=healthy`.
- `clientConfigProfile=remote_ssh_wg0`.
- `clientConfigReady=true`.
- `isActive=false`.
- `isPublic=false`.
- Узел не попадает в публичный клиентский catalog.
- Основной сайт и публичная выдача не менялись.

## Проверки

- SSH с локальной машины на `88.218.250.86` работает.
- SSH с origin на `88.218.250.86` через origin-only key работает.
- `wg-quick@wg0` на RUVDS активен.
- WireGuard слушает UDP `443`.
- Peer count после smoke: `0`.
- Protected admin `remote-provisioning-check`: `ok=true`.
- Protected admin `remote-peer-smoke`: временный peer добавлен, найден и удалён.
- Protected admin `client-config-smoke`: форма клиентского конфига собрана, временный peer удалён.
- External service probe видит `ruvds-2584554-ld8` как `healthy`.
- Publication gate dry-run: `canPublish=true`.
- Публичный `/api/v1/catalog/servers` не содержит `ruvds-2584554-ld8`.

## Важно

- WireGuard private key не выводился и не записывался в repo.
- Admin/API tokens не выводились и не записывались в repo.
- SSH private keys не выводились и не записывались в repo.
- Публикацию узла клиентам делать только отдельным явным решением владельца.
- До публикации можно использовать ноду как hidden canary/test endpoint через admin smoke.

