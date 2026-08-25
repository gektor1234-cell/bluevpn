# Green VPN: provider-neutral privacy notice

Дата фиксации: 2026-08-25 MSK.

## Итог

На основной странице политики конфиденциальности удалена устаревшая жёсткая
привязка обработки платёжных данных к YooKassa. Текст теперь ссылается на
подключённого платёжного провайдера и остаётся корректным при выборе нового
провайдера.

Изменён только `public_demo_site/privacy/index.html`. Главная страница, стили,
иконка, приложения, backend и VPN data plane не менялись.

## Exact bundle

Пакет:
`C:\BlueVPN_Builds\main_site_privacy_hotfix_20260825_r1\green-vpn-main-site-privacy-hotfix-20260825-r1.tar.gz`.

| Поле | Значение |
|---|---|
| Размер | `29440` bytes |
| SHA-256 | `49CD7392C560BB0096BF5B85D6684F4F6EA87EFBCE5C7A4A6041E16B2340070A` |
| Состав | `index.html`, `styles.css`, `assets/app_icon.ico`, `privacy/index.html` |

Exact deployed file hashes:

| Файл | SHA-256 |
|---|---|
| `index.html` | `D63D450E3E10EE7F49127F8D05BB3E64040E0AE8DB91DF53E7B7BAEE539BE393` |
| `styles.css` | `8A56E8F0FBC57F051A6F27741AAC81A247F844F7CB7D279918952D13431DE14E` |
| `assets/app_icon.ico` | `D6E2F6F5AA38F222C28448F13E63C6362EFAF3C7086B34111F8172A6083485B4` |
| `privacy/index.html` | `0D7F705079481086B2B2B8B3408FBDF58F76555D6FDB5D7AB66B9ECF7E1E2653` |

## Deployment

Guarded installer `scripts/server/install_main_site_release.sh` прошёл dry-run
и apply сначала на fallback `176.113.81.35`, затем на primary
`72.56.32.197`. На обоих узлах `nginx -t` прошёл успешно, а четыре deployed
hash совпали с локальным пакетом.

Rollback directories:

| Узел | Каталог |
|---|---|
| fallback | `/root/greenvpn-main-site-backups/20260825T200105Z` |
| primary | `/root/greenvpn-main-site-backups/20260825T200241Z` |

## Public verification

- `https://greenvpn.pro/` — HTTP `200`.
- `https://greenvpn.pro/privacy/` — HTTP `200`, новый provider-neutral текст
  присутствует, `YooKassa` отсутствует.
- `https://greenvpn.pro/legal/offer` — HTTP `200`.
- Android download — HTTP `200`, `Content-Length: 56362397`.
- Windows download — HTTP `200`, `Content-Length: 52809216`.

Действующие stable Android и Windows артефакты не заменялись. Friendly Linnet
`5.129.237.163` не контактировался и не изменялся.
