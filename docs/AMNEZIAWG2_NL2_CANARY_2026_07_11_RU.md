# AmneziaWG 2 canary на Netherlands #2

Дата: 2026-07-11.

## Результат

- Host: Netherlands #2 `5.129.216.42` / `nl2.vpn.greenvpn.pro`.
- Стадия: `canary`; пользователям и stable-клиенту не выдаётся.
- Основной VPN: `wg-quick@wg0`, UDP/443, остался active.
- Canary: `greenvpn-amneziawg-canary.service`, interface `awgcanary0`, UDP/1443.
- Canary subnet: `10.202.0.0/24`; отдельные серверный и клиентский ключи.
- Config: `/etc/greenvpn-transport/awgcanary0.conf`, owner `root`, mode `0600`.
- Toolchain: `/opt/greenvpn-canary/amneziawg2/bin`.
- Public catalog после установки: `current_wg0`, `ruvds-2584554-ld8`, `tw-7879598-nl1`; у всех protocol `wireguard_udp`, default `current_wg0`.

## Закреплённые исходники

- Go `go1.26.5`, archive SHA-256 `5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`.
- `amnezia-vpn/amneziawg-go` commit `c1e9bb3758e71bb1adc402598465565bfc9663fd`.
- `amneziawg-tools` tag `v1.0.20260618-2`.
- Tools archive SHA-256 `9f645117ba1aa536c8358e2c682a54cc3949e65b9efb86d8495d4343dcee99f9`.
- Серверный build manifest: `/etc/greenvpn-transport/awgcanary0.build-manifest`, mode `0600`.

## Backup и секреты

- Pre-change snapshot: `/root/greenvpn-awg2-prechange/20260711T171122Z`.
- Snapshot содержит root-only копию `wg0.conf`, iptables, listeners, systemd и контрольные суммы.
- Локальный client checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_awg2_20260711`.
- Локальные private key/config ACL: только владелец, SYSTEM и Administrators.
- Первый некорректно собранный тестовый client key был немедленно ротирован; сервер принимает только новый public key.
- Private keys, server config и значения H/S в документацию и git не записывались.

## Пройденные проверки

1. До изменения NL1, London и NL2 были healthy; default оставался NL1.
2. `wg0.conf` после установки совпал со snapshot через `cmp`.
3. Readiness: `ok=true`, service active, UDP/1443 listener ready, blockers/warnings пусты.
4. Из WSL создан временный AWG2 userspace client без изменения маршрутов Windows.
5. Fresh handshake прошёл.
6. Ping `10.202.0.1` через tunnel прошёл.
7. Egress через canary до `1.1.1.1` прошёл.
8. Временный WSL interface удалён cleanup-обработчиком.
9. Rollback удалил unit, `awgcanary0`, listener и canary NAT; `wg0` остался active.
10. Повторная установка и post-reinstall handshake/egress прошли.
11. Production `/healthz` вернул `ok=true`.
12. Единственный failed unit NL2 - старый `dnsmasq.service`; новый canary failed units не создал.

## Rollback

```bash
/root/greenvpn-awg2-stage/remove_transport_canary_service.sh \
  --protocol amneziawg \
  --service-name greenvpn-amneziawg-canary \
  --expected-public-ip 5.129.216.42 \
  --approved-existing-host 5.129.216.42 \
  --apply
```

Rollback сохраняет root-only config, ключи и binaries для диагностики, но снимает interface, listener и правила canary NAT.

## Ограничение

Green VPN stable пока не содержит AmneziaWG client engine и продолжает объявлять только `wireguard_udp`. Следующий этап должен выполняться исключительно в отдельной preview-сборке приложения. Публиковать AWG endpoint в stable catalog до physical Android/Windows preview smoke запрещено.
