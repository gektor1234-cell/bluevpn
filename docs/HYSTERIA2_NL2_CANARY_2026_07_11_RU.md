# Green VPN Hysteria2 NL2 canary

Дата: 2026-07-11.

## Изоляция

- Host: Netherlands #2 `5.129.216.42` / `nl2.vpn.greenvpn.pro`.
- Stable `wg0` остаётся active на UDP/443.
- AWG2 canary остаётся active на UDP/1443.
- Hysteria2: service `greenvpn-hysteria2-canary.service`, UDP/2443.
- Server config: `/etc/greenvpn-transport/hysteria2-canary.yaml`, root:root `0600`.
- Client smoke config: `/etc/greenvpn-transport/hysteria2-canary.client.yaml`, root:root `0600`.
- Runtime: `/opt/greenvpn-canary/hysteria2`, отдельно от production.
- Public catalog, control-plane env, базы, nginx, сайт и downloads не изменялись.

## Закреплённый runtime

- Upstream: `apernet/hysteria`.
- Release: `app/v2.9.3`, commit `2d973f9513ef661d1922d6d14acb37945caef47d`.
- License: MIT.
- Linux amd64 SHA-256: `66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1`.
- Windows amd64 SHA-256: `bcd3865b09be2e5cc18d117dcf3ad687d1e6e27b0b050376b9cf4ea251b64d6f`.
- Оба SHA совпадают с digest официальных GitHub release assets.

## Защита транспорта

- TLS-сертификат для `nl2.vpn.greenvpn.pro` получен через ACME Let’s Encrypt; `insecure` не используется.
- Клиент подключается к IP и проверяет SNI `nl2.vpn.greenvpn.pro`, что также подходит Android FD-control без отдельного DNS-запроса Hysteria.
- Включены отдельные password auth и Salamander obfuscation secrets; значения не попадают в Git, docs или логи проверки.
- Server работает с BBR standard и игнорирует заявленную клиентом полосу.
- Masquerade отвечает нейтральной HTML-страницей внутри Hysteria transport.

## Доказательства

- Guard negative test: попытки apply/rollback для неразрешённого `shadowsocks` на NL2 завершились с exit `1`, unit не появился.
- Readiness: `ok=true`, `serviceActive=true`, `listenReady=true`, blockers/warnings пусты.
- `wg0=active`, `greenvpn-amneziawg-canary=active`, `greenvpn-hysteria2-canary=active`.
- Неизменные hashes после Hysteria rollout:
  - `/etc/wireguard/wg0.conf`: `74724832a1cf0e6f1b1368da631c1a498a240aeb379b5e25e481151524a71cab`;
  - `/etc/greenvpn-transport/awgcanary0.conf`: `3d774dc564238a1a0c2bcb70aa1c66442b62eb93632152dce989c836eb9d7e8e`.
- Windows official Hysteria client SOCKS smoke:
  - listener `127.0.0.1:1980` поднялся;
  - egress IP `5.129.216.42`;
  - `https://api.greenvpn.pro/healthz` вернул `ok=true`;
  - `https://www.youtube.com/` вернул HTTP `200`;
  - после smoke процесс и listener остановлены.
- Paid-beta catalog содержит три WireGuard server и `hysteria2_count=0`.

## Rollback

Dry-run:

```bash
/root/greenvpn-hysteria2-staging-20260711/remove_transport_canary_service.sh \
  --protocol hysteria2 \
  --service-name greenvpn-hysteria2-canary \
  --expected-public-ip 5.129.216.42 \
  --approved-existing-host 5.129.216.42
```

Apply добавляет только `--apply`. Rollback удаляет unit, но сохраняет config, credentials и binary для диагностики. Public catalog и другие VPN service не затрагиваются.

## Следующий gate

Серверная стадия `canary` доказана. До `preview` остаются: Windows full-TUN engine, Android `VpnService` + FD-control + tun2socks engine, fail-closed capability contract в обоих российских control-plane и физические тесты без вложенного VPN.
