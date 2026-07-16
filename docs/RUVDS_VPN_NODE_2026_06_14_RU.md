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

- Существующий VPS восстановлен провайдером 2026-07-16 без переустановки ОС,
  пересоздания диска или смены IP.
- Managed catalog entry создана, восстановлена и проверена.
- `status=healthy`.
- `clientConfigProfile=remote_ssh_wg0`.
- `clientConfigReady=true`.
- `isActive=true`.
- `isPublic=true`.
- Production и paid-beta каталоги обоих российских control-plane публикуют
  узел как одну логическую локацию `Англия` без провайдера, номера узла и
  протокола в пользовательском интерфейсе.

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
- Публичные production и paid-beta каталоги содержат
  `ruvds-2584554-ld8`, а Android группирует его по стране `GB`.
- Изолированный data-plane smoke с Timeweb и RUVDS Moscow: handshake, RX/TX,
  London egress, production API, Google и YouTube по `3/3`; cleanup полный.
- Physical Android 9 production/test: `Англия` видна одной строкой, tunnel
  `CONNECTED+VALIDATED`; production YouTube проигран до конца; foreground VPN
  пережил удаление activity stack и восстановил состояние после relaunch.
- `greenvpn-london-app-subnet-restore.service` восстановлен и активен.
- `greenvpn-vpn-capacity-report.timer` снова enabled/active, ручной apply
  завершился `Result=success`.

## Важно

- WireGuard private key не выводился и не записывался в repo.
- Admin/API tokens не выводились и не записывались в repo.
- SSH private keys не выводились и не записывались в repo.
- Rollback runtime:
  `/root/greenvpn-london-recovery-backups/20260716T100956Z`.
- Перед публикацией созданы отдельные root-only online-backup production и
  paid-beta SQLite на обоих control-plane; точные пути записаны в
  `CURRENT_HANDOFF.md`.
- При деградации сначала выполнить штатный `unpublish`, затем разбирать узел по
  сохранённому backup; APK для server-side скрытия/возврата не обновляется.
