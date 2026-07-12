# Green VPN Naive HTTPS NL2 Canary

Дата: 2026-07-12.

## Решение

Последняя HTTPS-подобная линия строится на NaiveProxy, а не на reference AnyTLS:

- NaiveProxy использует Chromium network stack, HTTP/2 CONNECT, padding и стандартный TLS fingerprint; клиент имеет лицензию BSD-3-Clause.
- Caddy имеет лицензию Apache-2.0; закреплённый `klzgrad/forwardproxy` также Apache-2.0.
- Reference `anytls-go` на момент аудита не содержит явного LICENSE и сам называет example client/server неполным reference implementation.
- Готовый AnyTLS через sing-box возможен, но sing-box распространяется под GPL-3.0-or-later. Он остаётся исследовательским вариантом, а не зависимостью коммерческого Green VPN клиента.

Первичные источники:

- `https://github.com/klzgrad/naiveproxy`
- `https://github.com/caddyserver/caddy`
- `https://github.com/klzgrad/forwardproxy/tree/d62c80d3dd2c706b6b87579844d2397bddd18317`
- `https://github.com/anytls/anytls-go`
- `https://github.com/SagerNet/sing-box`

## Изоляция

- Host: NL2 `5.129.216.42`.
- Domain: `nl2.vpn.greenvpn.pro`, trusted Let's Encrypt full chain.
- Service: `greenvpn-naive-https-canary.service`.
- Listener: только TCP/8443. UDP/8443 отсутствует.
- TCP/443 VLESS REALITY, UDP/443 WireGuard, UDP/1443 AWG2 и UDP/2443 Hysteria2 не менялись.
- Canary не добавлен в production или paid-beta catalog и не выдаётся ни одному клиенту.
- Незнакомый HTTPS-запрос получает обычный HTTP `404` с успешной TLS verification, а не признак proxy endpoint.

## Закреплённые компоненты

- Go `1.26.5`, archive SHA-256 `5C2C3B16CAEFA1D968A94C1DACA04A7CA301A496D9B086E17AD77BB81393F053`.
- Caddy `v2.11.4`.
- xcaddy `v0.4.5`.
- forwardproxy exact commit `d62c80d3dd2c706b6b87579844d2397bddd18317`.
- NaiveProxy `v150.0.7871.63-1`.
- Naive Linux archive SHA-256 `0C4F506CE66A7881892FD6932B542C53FC06AC2351987756096C61E753C687BF`.
- Built Caddy SHA-256 `FE70C730D8BED0A9570CE9ADF62B94958E676E196B40EA7108C5E93EC7003498`.
- Installed Naive binary SHA-256 `BAEA1E9B9F8DD879A6374110BD7BDCA80C2ECBDCA8DEBC4F84F784A8739EAEA7`.
- Windows archive SHA-256 `D09E35F9FDE6206A775A1B930D7D8252053BEE1408EE1C910B5681346C68D1A1`.
- Android arm64 plugin APK SHA-256 `733FBBBEBB383A91F42036992C21CFD19B99E089AC3D15D7C077DF79FC471A89`.

## Защита

- Учётные данные создаются отдельно, хранятся root/group-only и никогда не печатаются readiness/bootstrap.
- Client profile root-owned mode `0600`; Caddy config mode `0640` доступен только dedicated user `greenvpn-naive`.
- Caddy работает не от root с systemd hardening, отдельным state directory, отключённым admin endpoint и без HTTP/3.
- Сертификат копируется из существующего ACME fullchain в отдельный canary material directory; права Hysteria не ослабляются.
- Bootstrap разрешён только при exact public IP и двойном NL2 approval argument.

## Проверка

`scripts/server/check_naive_https_canary_readiness.sh` подтвердил:

- service active и TCP/8443 listener;
- отсутствие UDP/8443;
- Caddy/forwardproxy/Naive build metadata;
- корректные owner/mode и отсутствие symlink config;
- внешний TLS status `404`, verify result `0`;
- реальный SOCKS data-plane egress `5.129.216.42`;
- активность WireGuard, AWG2, Hysteria2 и VLESS.

## Rollback

Dry-run:

```bash
/tmp/remove_naive_https_canary.sh
```

Apply допускается только на точном NL2:

```bash
/tmp/remove_naive_https_canary.sh \
  --expected-public-ip 5.129.216.42 \
  --approved-existing-host 5.129.216.42 \
  --apply
```

Rollback сохраняет root-only backup, удаляет только service/config/client profile/install root Naive и проверяет активность четырёх прежних транспортов.

## Осталось до клиентского rollout

- Собрать отдельные Windows и Android preview engines поверх существующего HEV bridge.
- Провести physical full-tunnel, watchdog, background и restore проверки.
- Для реальной последней линии перевести Naive с 8443 на общий TCP/443 через проверенный SNI router; VLESS нельзя переносить до отдельного rollback/proof.
- Только после этого добавлять `naive_https` capability и endpoint в изолированный control plane.
