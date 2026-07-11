# Android AWG2 transport preview

Дата: 2026-07-11.

## Границы этапа

- Production stable, основной сайт, публичные загрузки, платежи и production API не менялись.
- AWG2 доступен только отдельному Android package `pro.greenvpn.app.transportpreview` через paid-beta API.
- Stable-клиент продолжает объявлять только `wireguard_udp` и не видит AWG2 endpoint.
- Серверный canary работает отдельно от `wg0`: NL2 `5.129.216.42`, `awgcanary0`, UDP/1443, `10.202.0.0/24`.

## Реализация

- Backend поддерживает `remote_ssh_awg2`, AWG2 interface fields и `awg-quick` config format.
- Capability negotiation fail-closed: AWG2 выдаётся только клиенту с capability `amneziawg`, preview channel и allowlist server id.
- `GREENVPN_AMNEZIAWG_CLIENT_CONFIG_ENABLED=1` включён только в paid-beta contour.
- Для AWG2 обязателен отдельный `GREENVPN_NODE_CLIENT_SUBNET`. Диапазон, пересекающийся с production WireGuard, блокируется.
- Таблица `device_transport_assignments` хранит sticky IP отдельно от `devices.assigned_ip`. Production WireGuard-адрес устройства не изменяется.
- Android preview использует официальный AmneziaWG Android 2.0.1 commit `fb64e74ba5a0a54e9185b8776bcb8088afb772c9` и только userspace `libwg-go.so`, переименованный в `libawg2-go.so`.
- Stable Android build не подключает AWG-модуль. Preview build использует один AWG2 Go runtime для WG/AWG, чтобы не загружать два несовместимых Go shared runtime в один процесс.
- Выбранный server id и UI prefs на Android хранятся в постоянном `files/greenvpn_state`, а не в очищаемом при обновлении `code_cache`.

## Развёрнуто

- Timeweb Moscow `72.56.32.197` и RUVDS Moscow `176.113.81.35`:
  - release `/opt/bluevpn-paid-beta/releases/paid-beta-0.3.0-paid-beta.6-2026071106-r15-awg2-active-active`;
  - backend `0.9.109-transport-preview.3`;
  - service `greenvpn-paid-beta.service` active;
  - SQLite `quick_check=ok` и таблица transport assignments присутствует;
  - node env `/etc/bluevpn/vpn_nodes/nl2-awg2-canary.env`, mode `0600`.
- Rollback backup Timeweb: `/root/greenvpn-awg2-preview-prechange/20260711T185642Z-r15-active-active`.
- Rollback backup RUVDS: `/root/greenvpn-awg2-preview-prechange/20260711T185702Z-r15-active-active`.
- Оба backup-каталога имеют mode `0700`, файлы внутри `0600`.
- `device_transport_assignments` включена в двустороннюю 10-секундную SQLite-синхронизацию. На обоих control-plane count `1`, canonical SHA-256 `b1eae793194edda5e25d74ab138db64d0ecc4626284717822da7780f1e383e21` и `quick_check=ok`.
- Новые transport IP выбираются детерминированно по production host number устройства; существующие assignments остаются sticky.

## Android artifact

- APK: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_awg2_transport_preview4_paid_beta_debug.apk`.
- Package/label: `pro.greenvpn.app.transportpreview` / `Green VPN Transport Preview`.
- Version code: `2026070506`.
- Size: `176477534` bytes.
- SHA-256: `EAC700378406484E273DFBD4892220F8D403331167BA7DEB070E5414B30B78B1`.
- Debug signer SHA-256: `959fa99cc911ae99116d9d707bbd9936303c0793fa89bf3ee410cf0c214a4d5c`.
- Это внутренний preview artifact, не публичный релиз.

## Физическая проверка

Устройство: Samsung SM-A226B, Android 13.

1. Paid-beta авторизация и скрытый `NL2 Protected Preview` доступны.
2. Backend выдал `10.202.0.2/32`; production IP `10.10.0.183` не был изменён.
3. Android создал `tun0`, owner UID preview-приложения, full-tunnel routes и status `VALIDATED`.
4. AWG2 handshake получен; server route `10.202.0.2` идёт через `awgcanary0`.
5. HTTPS-запрос увеличил server RX/TX; внешний IP телефона `5.129.216.42`.
6. YouTube Shorts загрузился и воспроизводился.
7. После сворачивания и возврата сессия и VPN сохранились.
8. После реального свайпа карточки из Android Recents процесс foreground VPN и tunnel продолжили работать.
9. После повторного запуска UI показал `Включено` и тот же `NL2 Protected Preview`, без повторного логина.
10. Preview отключён после теста; официальный `bluevpn-phone-3` восстановлен и `VALIDATED`.

## Найденные и устранённые дефекты

- Два Go c-shared runtime в одном Android-процессе приводили к `fatal error: unknown caller pc`. Preview теперь использует только AWG2 runtime.
- Первый AWG2 config получил production IP `10.10.0.183`; обратный route уходил в `wg0`. Отдельная transport assignment выдала `10.202.0.2` и устранила конфликт.
- Android UI prefs находились в `code_cache` и исчезали после обновления APK. State перенесён в постоянный app files directory.
- AWG build-скрипт теперь по умолчанию запрещает production package id и требует paid-beta API.

## Известный долг

- Официальный prebuilt AWG userspace library пишет нефатальную ошибку UAPI для жёстко заданного пути `/data/data/org.amnezia.awg`. Tunnel, handshake и traffic работают. Перед публичным выпуском нужно собрать библиотеку для Green VPN package и убрать этот лог.
- Android preview доказан; Windows AWG2 engine ещё не реализован. AWG2 нельзя публиковать в stable catalog до Windows preview и общего fallback selector.

## Rollback

1. На control-plane атомарно вернуть symlink `/opt/bluevpn-paid-beta/current` на r14 или исходный r13 release, восстановить `paid-beta.env`, node env и при необходимости SQLite из соответствующего root-only backup.
2. Перезапустить только `greenvpn-paid-beta.service` и проверить `/healthz`, `quick_check` и sync timer.
3. Для полного удаления server canary использовать guard-скрипт из `AMNEZIAWG2_NL2_CANARY_2026_07_11_RU.md`; `wg0` не трогать.
4. На телефоне удалить только `pro.greenvpn.app.transportpreview`. Stable и официальный WireGuard package независимы.
