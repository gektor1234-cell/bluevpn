# Green VPN: безопасный rollout транспортов

Дата: 2026-07-11.

## Неприкосновенный основной контур

- Исходная точка: tag `greenvpn-public-candidate-billing-guard-20260711`.
- Рабочая ветка эксперимента: `green-vpn-transport-canary-20260711`.
- Stable-клиент поддерживает и объявляет только `wireguard_udp`.
- Клиент без поля `supportedProtocols` считается старым и получает только `wireguard_udp`.
- Backend пересекает объявленные клиентом возможности с `SERVER_CLIENT_READY_PROTOCOLS`.
- Неподдерживаемый протокол удаляется из каталога повторно перед выбором endpoint.
- Новый транспорт не заменяет `wg0`, не меняет сайт, авторизацию, оплату, DB или stable downloads.

## Стадии

| Стадия | Смысл | Может попасть клиенту |
|---|---|---|
| `research` | Изучение движка и лицензии | Нет |
| `canary_prepared` | Есть dry-run installer/readiness/rollback | Нет |
| `canary` | Демон работает на отдельном тестовом VPS | Нет |
| `preview` | Есть отдельный клиентский engine и физический smoke | Только явно совместимому preview-клиенту |
| `public` | Пройдены server, client, route-health и rollback gates | Да |

Текущее состояние: `wireguard_udp=public`; `wireguard_tcp`, `amneziawg`, `openvpn_tcp`, `shadowsocks`, `hysteria2`, `trojan_tls`, `vless_reality=canary_prepared`; `masque_udp=research`.

## Защищённые серверы

Canary-скрипты безусловно запрещают apply на действующих control-plane/VPN узлах и на Friendly Linnet. Старый параметр `--allow-current-vpn-host` оставлен только для совместимости dry-run и не обходит защиту apply.

Свободного безопасного VPS на момент фиксации нет. KZ test `94.198.221.206` недоступен по SSH; существующие зарубежные узлы обслуживают рабочий VPN. Поэтому live-развёртывание нового транспорта не выполнялось.

## Первый кандидат: AmneziaWG 2

1. Выделить отдельный test-only VPS, не входящий в stable/preview каталог.
2. Установить закреплённые версии официальных `amneziawg` и `amneziawg-tools`; записать версии и SHA-256.
3. Создать отдельный интерфейс и root-only config без переиспользования ключей `wg0`.
4. Config должен содержать `S1-S4`, уникальные ненулевые `H1-H4`, серверный `PrivateKey`, `ListenPort` и отдельного canary peer.
5. Выполнить dry-run generic installer, затем readiness checker.
6. Apply требует точный `--expected-public-ip`; для AWG systemd использует `Type=oneshot` и `RemainAfterExit=yes`.
7. Проверить handshake, DNS, YouTube/Telegram, sleep/reopen и отсутствие изменений public catalog.
8. Откатить отдельным rollback-скриптом; config/keys оставить root-only для диагностики.

```bash
sudo scripts/server/install_transport_canary_service.sh \
  --protocol amneziawg \
  --binary /usr/bin/awg-quick \
  --config-file /etc/greenvpn-transport/awg-canary0.conf \
  --expected-public-ip TEST_VPS_IP

sudo scripts/server/check_transport_canary_readiness.sh \
  --protocol amneziawg \
  --binary /usr/bin/awg-quick \
  --config-file /etc/greenvpn-transport/awg-canary0.conf \
  --listen-port CANARY_PORT --json
```

`--apply` добавляется только после зелёного dry-run на отдельном VPS.

## Последовательность после AWG2

1. AmneziaWG 2: быстрый маскированный UDP.
2. Hysteria2: QUIC fallback.
3. VLESS + REALITY + XHTTP на TCP/443: fallback при блокировке UDP.
4. NaiveProxy/AnyTLS: HTTPS-подобный резерв после отдельного лицензионного и engine-аудита.
5. OpenVPN TCP/443: совместимость.
6. MASQUE и Tor transports: исследовательский контур.
7. DNS/ICMP-туннели: только аварийная лаборатория, не продуктовый auto-selection.

## Обязательные public-gates

- Клиентский engine присутствует в отдельной preview-сборке и объявляет протокол.
- Сервер работает минимум 72 часа без рестарт-цикла и утечек ресурсов.
- Внешний probe подтверждает endpoint и маршруты к обязательным сервисам.
- Физический Android и Windows smoke пройдены.
- Старый stable-клиент не видит endpoint даже при ошибочной пометке записи public.
- Rollback проверен до публикации.
- Лицензия движка допускает коммерческое распространение выбранным способом.
