# Green VPN: обновление основного сайта

Дата фиксации: 2026-08-25 MSK.

## Итог

Исправленный сайт опубликован на `https://greenvpn.pro/`. На странице нет
скриншотов приложения: они не входят в HTML, пакет или webroot обоих production
узлов. Единственное изображение страницы — фирменный значок Green VPN.

Текущий дизайн использует бело-графитовую основу и зелёный, голубой и янтарный
акценты. Страница ведёт прямо к загрузке Android и Windows, кратко описывает два
режима и основные действия приложения, не публикует исторические цены и честно
предупреждает о разрешении Android на установку APK и о возможном SmartScreen.

## Причина hotfix

Первый refresh был проверен только в чистом профиле браузера. В уже открытом
профиле пользователя новый HTML соединился со старым закэшированным CSS. Из-за
этого ссылка пропуска стала видимой, layout разрушился, а продуктовые скриншоты
стали огромными.

Hotfix устраняет обе причины:

- CSS подключается через новый cache key `/styles.css?v=20260825-r2`;
- все продуктовые скриншоты удалены из разметки, пакета, исходников и обоих
  production webroot;
- guarded installer отклоняет пакет со ссылками на эти изображения;
- runbook теперь требует проверку и в свежем профиле, и в браузере со старым
  кэшем.

## Точный пакет R2

Архив:
`C:\BlueVPN_Builds\main_site_hotfix_20260825_r2\greenvpn-main-site-20260825-r2.tar.gz`.

- размер: `29407` bytes;
- SHA-256:
  `0D9BBD8F6246894A2B3B127A5CF5265B3FD44490E4A152F0CFA84B173BD7DDFC`;
- entries: `4`, без symlink и без `downloads/`.

| Путь | Размер | SHA-256 |
|---|---:|---|
| `index.html` | `10850` | `4C336BB97EA5C3BC74FF200DE9F3E8F3E592308B63DCD40392ABB42946C9909E` |
| `styles.css` | `15412` | `8A56E8F0FBC57F051A6F27741AAC81A247F844F7CB7D279918952D13431DE14E` |
| `assets/app_icon.ico` | `20282` | `D6E2F6F5AA38F222C28448F13E63C6362EFAF3C7086B34111F8172A6083485B4` |
| `privacy/index.html` | `6500` | `28F4074C909058DCDC1D05F5CEDAAA0D0972ED8DCBC59C334F6DB1FAEDFFA829` |

Guarded installer `scripts/server/install_main_site_release.sh` имеет SHA-256
`F987B235C61055B2D0043269EF23F945014A3D4BD0E374EE1C7507A90F0509E9`.

## Публикация и откат

На каждом узле выполнены dry-run и apply в порядке fallback, затем primary.

Первая попытка apply на fallback создала backup
`/root/greenvpn-main-site-backups/20260825T142815Z`, но verifier ожидал CSS по
корневому HTTPS location, который на этом узле намеренно проксируется в backend
и возвращает `404`. Guarded installer автоматически восстановил предыдущую
версию; primary на этом этапе не запускался. Verifier исправлен: CSS проверяется
по точному локальному файлу, HTTPS — по существующему static asset.

| Узел | Результат | Rollback root |
|---|---|---|
| fallback `176.113.81.35` | dry-run/apply success | `/root/greenvpn-main-site-backups/20260825T142928Z` |
| primary `72.56.32.197` | dry-run/apply success | `/root/greenvpn-main-site-backups/20260825T143004Z` |

## Проверки

- Все четыре файла primary и fallback совпадают с локальными SHA-256.
- Три прежних PNG отсутствуют в обоих webroot. Fallback возвращает для них
  `404`; main-domain fallback route возвращает HTML, но не image bytes.
- Живые проверки `2560 x 1336`, `1440 x 1050` и `390 x 844`: horizontal
  overflow `false`, broken images `0`, browser warnings/errors `0`.
- На `390 x 844` первый экран оставляет видимым начало следующего раздела.
- В DOM главной есть только `assets/app_icon.ico`; CSS URL содержит
  `v=20260825-r2`; skip-link вне экрана до keyboard focus.
- Открытая вкладка Green VPN в Яндекс Браузере пользователя после публикации
  обновлена через hard refresh.
- Главная, `/healthz`, пять legal routes и обе стабильные загрузки возвращают
  HTTP `200`.
- `check_public_download_manifests.ps1`: manifests `10/10`, static manifests
  `2/2`, downloads `8/8`.
- Bash syntax и `git diff --check` прошли; release gate завершился с
  warnings/errors `0/0`.

QA-кадры сохранены только как локальные evidence и не публикуются:
`C:\BlueVPN_Builds\main_site_hotfix_20260825_r2\visual`.

## Границы

Не изменялись:

- Android APK, Windows installer и их публичные bytes;
- stable и paid-beta manifests;
- backend, production databases и systemd units;
- VPN routes, tunnels и пользовательские сессии;
- Friendly Linnet `5.129.237.163`.
