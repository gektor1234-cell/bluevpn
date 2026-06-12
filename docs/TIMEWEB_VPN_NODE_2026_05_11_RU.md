# Timeweb VPN Node 2026-05-11

## Что сделано

- Создан новый Timeweb Cloud VPS для будущего отдельного VPN-узла.
- Название в Timeweb: `GreenVPN NL1 VPN 20260511`.
- Timeweb server id: `7879598`.
- Регион: `nl-1` / `ams-1`.
- Конфигурация: `Cloud NL-40`, 2 CPU, 2 GB RAM, 40 GB NVMe, 1 Gbit/s.
- IPv4: `5.129.216.42`.
- IPv6: `2a03:6f02::a1ca`.
- Ожидаемая постоянная стоимость: `4030 RUB/month` за сервер + `180 RUB/month` за IPv4, всего около `4210 RUB/month`.
- Установлен WireGuard.
- Интерфейс: `wg0`.
- Порт: UDP `443`.
- VPN subnet: `10.10.0.0/24` (совместимо с текущей выдачей клиентских IP backend).
- Включены IPv4/IPv6 forwarding и NAT для исходящего трафика.
- `wg-quick@wg0` активен.
- Серверные WireGuard keys сгенерированы только на сервере и не записывались в repo/docs/chat.
- Метаданные узла записаны в `/etc/greenvpn/node.env`.
- Скрипты из `scripts/server/` скопированы на узел в `/opt/greenvpn-server/`.
- Установлен systemd timer `greenvpn-vpn-capacity-report.timer`.
- Reporter отправляет в backend capacity и peer traffic baseline без приватных ключей и без токенов в выводе.
- Backend `0.9.85` задеплоен live на `37.220.85.211`.
- Managed server catalog содержит внутреннюю запись `tw-7879598-nl1`.
- На origin-сервере создан server-only каталог `/etc/bluevpn/vpn_nodes`.
- Для `tw-7879598-nl1` на origin лежит server-only env `/etc/bluevpn/vpn_nodes/tw-7879598-nl1.env`.
- Origin ходит на новый VPN-node по отдельному root-only SSH-ключу из `/etc/bluevpn/vpn_nodes`.
- Backend получил профиль `remote_ssh_wg0`: он умеет добавлять WireGuard peer на удалённый VPN-node по server-only SSH и собирать клиентский конфиг с публичным ключом выбранного узла.
- Protected admin check `/api/v1/admin/server-catalog/tw-7879598-nl1/remote-provisioning-check` проходит: origin видит удалённый `wg0`, публичный ключ совпадает с server-only env.
- Внешний service probe на `72.56.32.197` обновлён: он умеет проверять конкретный draft-сервер через `--server-health-server-id`.
- Для `tw-7879598-nl1` включён черновой canary без публикации узла клиентам; проверка `5.129.216.42:443` отправлена в backend как `healthy`.
- DNS `nl2.vpn.greenvpn.pro` уже резолвится в `5.129.216.42`.
- Managed catalog host и server-only `GREENVPN_NODE_PUBLIC_HOST` обновлены на `nl2.vpn.greenvpn.pro`.
- Внешний canary после DNS-переключения зелёный: `nl2.vpn.greenvpn.pro:443`.
- Для повторяемого безопасного переключения добавлен dry-run-first сценарий `scripts/windows/prepare_remote_vpn_node_dns_promotion.ps1`.
- Добавлен protected smoke endpoint `/api/v1/admin/server-catalog/tw-7879598-nl1/remote-peer-smoke`.
- Smoke endpoint успешно добавил тестовый peer на удалённый `wg0`, подтвердил наличие peer, удалил его и подтвердил удаление. Private key, preshared key и полный public key не возвращаются.
- Добавлен protected smoke endpoint `/api/v1/admin/server-catalog/tw-7879598-nl1/client-config-smoke`.
- Client-config smoke успешно собрал форму клиентского WireGuard-конфига для `nl2.vpn.greenvpn.pro:443`, подтвердил временный peer, удалил его и не вернул `configText`, private key, preshared key или полный public key.
- Добавлен controlled publication gate: `GET /api/v1/admin/server-catalog/{server_id}/publication-gate`, `POST /api/v1/admin/server-catalog/{server_id}/publish`, `POST /api/v1/admin/server-catalog/{server_id}/unpublish`.
- Backend теперь блокирует прямое сохранение `isPublic=true`, если VPN-узел не проходит publication gate.
- Dry-run publication gate для `tw-7879598-nl1` зелёный: `canPublish=true`, `candidateActive=true`, `candidatePublic=true`, `candidateEligible=true`, blockers нет.
- В админке `https://admin.greenvpn.pro` в разделе `Серверы -> Управляемые серверы` для таких remote-узлов появились кнопки `Peer-smoke`, `Тест конфига` и безопасное действие `Открыть клиентам` / `Скрыть`; они запускают protected endpoints без показа секретов.

## Текущее безопасное состояние

- Новый узел не выдается пользователям.
- Запись в каталоге оставлена скрытой от клиентов.
- `status=healthy`.
- `isActive=false`.
- `isPublic=false`.
- `clientConfigProfile=remote_ssh_wg0`.
- `clientConfigReady=true`.
- Публичный client catalog по-прежнему отдает только рабочий текущий endpoint `nl1.vpn.greenvpn.pro:443`.
- Внешний canary по DNS уже зелёный, но это не открывает сервер для клиентов автоматически.

Это сделано специально: сервер уже подготовлен как инфраструктура и backend уже умеет выдавать под него peer/config, но его нельзя показывать клиентам без ручного promotion gate.

## Что осталось перед публичным включением

1. Проверить, что capacity reporter продолжает обновлять load/capacity.
2. Только после ручного решения нажать `Открыть клиентам` в админке или вызвать protected `POST /api/v1/admin/server-catalog/tw-7879598-nl1/publish`.
3. После включения проверить, что public catalog добавил новый endpoint, а клиент получает конфиг без ошибок.

## Проверки

- `https://api.greenvpn.pro/healthz` возвращает backend `0.9.85`.
- `wg-quick@wg0` на `5.129.216.42` активен.
- `greenvpn-vpn-capacity-report.timer` на `5.129.216.42` активен.
- WireGuard слушает UDP `443`.
- `wg0` на новом узле имеет `10.10.0.1/24`.
- Admin catalog: `tw-7879598-nl1` имеет host `nl2.vpn.greenvpn.pro`, `clientConfigProfile=remote_ssh_wg0`, `clientConfigReady=true`, `status=healthy`, `isActive=false`, `isPublic=false`.
- External server-health: `tw-7879598-nl1` проверен probe `external-site-72` как `healthy`, target `nl2.vpn.greenvpn.pro:443`.
- Remote peer smoke: `ok=true`, `applied=true`, `existsAfterApply=true`, `removed=true`, `existsAfterRemove=false`, smoke IP `10.10.0.253`.
- Client-config smoke: `ok=true`, `applied=true`, `existsAfterApply=true`, `configShapeOk=true`, `configTextBytes=330`, `removed=true`, `existsAfterRemove=false`, smoke IP `10.10.0.252`.
- Publication gate dry-run: `ok=true`, `version=0.9.85`, `canPublish=true`, `blockerCodes=[]`, `candidateEligible=true`.
- Admin UI: live `app.js` на `72.56.32.197` содержит действия `Peer-smoke`, `Тест конфига`, `Открыть клиентам` и `Скрыть` для управляемых записей.
- После smoke на новом узле: `wg show wg0 peers | wc -l` вернул `0`, smoke-блоков в `/etc/wireguard/wg0.conf` нет.
- Public catalog не содержит новый недонастроенный узел.

## Обновление 2026-05-11 после backend 0.9.88

- Live backend обновлён до `0.9.88`.
- `tw-7879598-nl1` проверен повторно: `status=healthy`, `clientConfigProfile=remote_ssh_wg0`, `clientConfigReady=true`.
- Узел всё ещё не выдаётся пользователям: `isActive=false`, `isPublic=false`.
- DNS `nl2.vpn.greenvpn.pro -> 5.129.216.42` подтверждён.
- На узле активны `wg-quick@wg0` и `greenvpn-vpn-capacity-report.timer`.
- WireGuard слушает UDP `443`; peer count после smoke остаётся `0`.
- Admin catalog видит узел и его readiness, public catalog его не показывает.
- Publication gate зелёный, но публикация не выполнена намеренно. Следующий шаг только по решению владельца: открыть узел клиентам и сделать реальный клиентский smoke.

## Обновление 2026-05-12 после backend 0.9.89

- Live backend обновлён до `0.9.89`.
- DNS `nl2.vpn.greenvpn.pro -> 5.129.216.42` подтверждён.
- Публичный клиентский каталог проверен: новый node не виден пользователям, наружу отдаётся только `intelligent_smew` / `nl1.vpn.greenvpn.pro:443`.
- Проверка через origin-only SSH без вывода секретов: `wg-quick@wg0` активен, `greenvpn-vpn-capacity-report.timer` активен, IPv4 forwarding включён, WireGuard слушает UDP `443`, peer count `0`.
- Новый node остаётся hidden canary: `isActive=false`, `isPublic=false`, `clientConfigReady=true`.
- Publication gate остаётся зелёным, но автоматическая публикация намеренно не выполнялась. Следующий шаг только по решению владельца: открыть узел клиентам, проверить реальный Windows-клиент и после этого оставить узел публичным.

## Обновление 2026-05-13 после Android E2E

- Повторно проверено, что Android E2E не опубликовал новый VPN-node и не оставил временных peer/users.
- Публичный каталог всё ещё отдаёт только `intelligent_smew` / `nl1.vpn.greenvpn.pro:443`.
- `nl2.vpn.greenvpn.pro` резолвится в `5.129.216.42`.
- Проверка нового узла выполнена только через origin server-only SSH:
  - host `greenvpn-nl1-vpn-20260511`;
  - `wg-quick@wg0` active;
  - WireGuard listen port `443`;
  - `net.ipv4.ip_forward=1`;
  - peer count `0`.
- Состояние остаётся безопасным: `tw-7879598-nl1` готов как hidden canary, но не выдается обычным пользователям.

## Секреты

- Timeweb token не выводился.
- Admin token не выводился.
- WireGuard private key не выводился.
- Значения секретов не записаны в repo/docs/chat.
