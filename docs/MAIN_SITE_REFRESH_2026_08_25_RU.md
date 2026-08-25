# Green VPN: обновление основного сайта

Дата фиксации: 2026-08-25 MSK.

## Итог

Обновлённая продуктовая страница опубликована на
`https://greenvpn.pro/`. Публикация выполнена только для сайта и не меняла
клиенты, update manifests, backend, базы данных или VPN-маршрутизацию.

Новая страница:

- ведёт прямо к загрузке Android APK и Windows installer;
- показывает реальные принятые экраны Android и Windows;
- описывает актуальные режимы `Весь интернет` и `Только выбранное`;
- показывает доступные действия: пауза, смена подключения, диагностика и детали;
- не публикует исторические цены и устаревшие обещания при отключённых продажах;
- честно предупреждает о разрешении Android на установку APK и о возможном
  SmartScreen для неподписанного Windows installer;
- сохраняет ссылки на оферту, политику, правила, возвраты, реквизиты и поддержку.

## Точный пакет

Архив:
`C:\BlueVPN_Builds\main_site_refresh_20260825_v1\greenvpn-main-site-20260825-v1.tar.gz`.

- размер: `518187` bytes;
- SHA-256:
  `A19C1DC40D4469AAE98ABD472C9A71D4EEE2429EF59D76D1A399BC7888534BB3`;
- entries: `7`, без symlink и без `downloads/`.

| Путь | Размер | SHA-256 |
|---|---:|---|
| `index.html` | `10488` | `AE37015C8BA8586969A82C3BD1F6C963D4A1388CB58A9D66DC9837AF475AA560` |
| `styles.css` | `14079` | `AC15F65022645614E3E8356467C7311FD800E3118D4186E21C62C08E8BDF7FE6` |
| `privacy/index.html` | `6344` | `348E535A648F5458E7E73A6BE838AD9A3B077510F96BDABE4607837D2E9895B7` |
| `assets/app_icon.ico` | `20282` | `D6E2F6F5AA38F222C28448F13E63C6362EFAF3C7086B34111F8172A6083485B4` |
| `assets/app_android_full.png` | `244181` | `B09ADA02F258F97C37915B0C031333D0E97A28CD5F722019AE7C69A050B7C335` |
| `assets/app_windows_full.png` | `145414` | `DBC3AD7702FC0AF1FD60E89F9D2C50E774E2F3E6E0FEDABE11E51C91C6CB00C4` |
| `assets/app_windows_selected.png` | `133239` | `99430CE45BB00F7EE66D263F6609A6A559278C291F8B5640BB3197E567764015` |

Guarded installer `scripts/server/install_main_site_release.sh` имеет SHA-256
`F1A69C911B39A5E80994DAD4761646A62E948BBF08A9451C86F7A0D2000F143E`.
Он разрешает только перечисленные семь файлов, проверяет актуальные тексты и
download links и отклоняет исторические цены и формулировки.

## Публикация и откат

На каждом узле сначала прошёл dry-run, затем apply. Порядок: fallback, затем
primary.

| Узел | Результат | Rollback root |
|---|---|---|
| fallback `176.113.81.35` | dry-run/apply success | `/root/greenvpn-main-site-backups/20260825T135634Z` |
| primary `72.56.32.197` | dry-run/apply success | `/root/greenvpn-main-site-backups/20260825T135841Z` |

Primary отдаёт основную публичную страницу. На fallback корневой location по
существующей nginx-схеме остаётся backend proxy; точные static assets установлены
в webroot и проверены напрямую. Эта публикация не меняла nginx topology.

## Проверки

- Все семь primary public files совпадают с локальными SHA-256.
- Главная, `/healthz`, пять legal routes и обе стабильные загрузки возвращают
  HTTP `200`.
- Живые desktop `1440 x 1050` и mobile `390 x 844` проверки: horizontal
  overflow `false`, broken images `0`, missing anchors `0`, browser warnings и
  errors `0`.
- Живая privacy page на `390 px`: overflow `false`, broken images `0`, missing
  anchors `0`, browser warnings и errors `0`.
- Скриншоты сохранены в
  `C:\BlueVPN_Builds\main_site_refresh_20260825_v1\visual`.
- `check_public_download_manifests.ps1`: manifests `10/10`, static manifests
  `2/2`, downloads `8/8`.
- Bash syntax и `git diff --check` прошли; release gate завершился с
  warnings/errors `0/0`.
- Stable Android остаётся `0.4.7` с `required=true`; stable Windows остаётся
  `0.4.6` с `required=true`. Paid-beta manifests остаются неизменными и
  необязательными.

## Границы

Не изменялись:

- Android APK, Windows installer и их публичные bytes;
- stable и paid-beta manifests;
- backend, production databases и systemd units;
- VPN routes, tunnels и пользовательские сессии;
- Friendly Linnet `5.129.237.163`.
