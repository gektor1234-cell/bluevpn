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

Текущее состояние: `wireguard_udp=public`; `amneziawg=canary`; `hysteria2=canary`; `wireguard_tcp`, `openvpn_tcp`, `shadowsocks`, `trojan_tls`, `vless_reality=canary_prepared`; `masque_udp=research`.

## Защищённые серверы

Canary-скрипты запрещают apply на действующих control-plane/VPN узлах и на Friendly Linnet. После прямого решения владельца для `5.129.216.42` разрешены только два точных сочетания: AWG2 с service `greenvpn-amneziawg-canary` и config `/etc/greenvpn-transport/awgcanary0.conf`; Hysteria2 с service `greenvpn-hysteria2-canary` и config `/etc/greenvpn-transport/hysteria2-canary.yaml`. Оба требуют `--approved-existing-host 5.129.216.42`; исключения нельзя использовать для другого протокола, unit, config или IP.

Свободного безопасного VPS на момент первоначальной фиксации не было. Владелец явно выбрал Netherlands #2 для параллельного canary. Основной `wg0` UDP/443 сохранён; AWG2 использует отдельные interface `awgcanary0`, UDP/1443, subnet и ключи. Результат зафиксирован в `docs/AMNEZIAWG2_NL2_CANARY_2026_07_11_RU.md`.

Hysteria2 использует на том же NL2 отдельные service `greenvpn-hysteria2-canary`, UDP/2443, TLS/ACME material, auth и Salamander secret. Он не публикуется в catalog до готовности клиентских engine. Результат зафиксирован в `docs/HYSTERIA2_NL2_CANARY_2026_07_11_RU.md`.

Отдельные Windows и Android preview-engine теперь физически проверены. Это не
меняет rollout stage `canary` и не публикует Hysteria2 stable-клиентам:
endpoint получает только клиент, явно объявивший capability `hysteria2` в
изолированном preview-канале. Android-доказательства и rollback находятся в
`docs/ANDROID_HYSTERIA2_PREVIEW_2026_07_12_RU.md`.

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
