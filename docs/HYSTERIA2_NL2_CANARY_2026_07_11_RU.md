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

## Paid-beta control-plane contract

- Timeweb Moscow `72.56.32.197` and RUVDS Moscow `176.113.81.35` run the same immutable release `paid-beta-0.3.0-paid-beta.6-2026071106-r16-hysteria-contract`.
- Backend version on both paid-beta nodes: `0.9.110-transport-preview.4`; production remained `0.9.105`.
- The Hysteria2 base client profile is installed as root:root `0600`; its SHA-256 is `6115ef37a73c43233e4ff90481e0fd46a8748c75a502839f94aeaecc38912cbe` on NL2 and both control planes.
- Legacy catalog returns `hysteria2_count=0`. Preview catalog returns exactly one Hysteria2 endpoint only when the client advertises `hysteria2` capability.
- Preview auto-selection remains `current_wg0|wireguard_udp`; Hysteria2 therefore cannot replace the stable route merely because it is present.
- Both SQLite databases pass `quick_check=ok`; their canonical seven-row catalog SHA-256 is `2c9fb6e8e5245ee994cfd8585b81b1d766899e536a0b7b5a8ba64cf1904584d6`.
- Public primary and fallback paid-beta health endpoints return the same backend version. Production health and public stable artifacts were not changed.
- Transaction backups: Timeweb `/root/greenvpn-hysteria2-contract-prechange/20260711T200156Z-timeweb`; RUVDS `/root/greenvpn-hysteria2-contract-prechange/20260711T200236Z-ruvds`.

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
