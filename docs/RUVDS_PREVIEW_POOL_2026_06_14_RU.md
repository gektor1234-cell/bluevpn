# RUVDS preview pool — 2026-06-14

## Статус

- Основной публичный каталог не меняется: stable-клиенты видят только публичные рабочие узлы.
- Preview/adgate-клиенты дополнительно видят allowlist-узлы из `GREENVPN_PREVIEW_SERVER_IDS`.
- На origin задан allowlist: `ruvds-2584554-ld8`.
- RUVDS London узел доступен только для preview/test канала, пока не будет отдельно принято решение выпускать его в stable.

## Узел

- `ruvds-2584554-ld8`
- Публичный endpoint: `88.218.250.86:443`
- Локация: London / GB
- Профиль: `remote_ssh_wg0`
- Интерфейс: `wg0`

## Проверки

- Backend health после деплоя: `0.9.103`.
- Stable catalog: `intelligent_smew`, `tw-7879598-nl1`; RUVDS не виден.
- Preview catalog: `intelligent_smew`, `tw-7879598-nl1`, `ruvds-2584554-ld8`; RUVDS виден.
- `remote-peer-smoke`: ok, peer создаётся и удаляется.
- `client-config-smoke`: ok, клиентский WireGuard-конфиг валидный, smoke peer удаляется.
- External probe с `72.56.32.197`: RUVDS endpoint healthy, score 100.
- YouTube media probe: green, media throughput healthy.

## Android preview

- Preview APK собран и опубликован:
  - version: `0.2.26-adgate-preview-ruvds`
  - build name: `0.2.26`
  - build number: `2026061401`
  - URL: `https://greenvpn.pro/downloads/GreenVPN_Android_preview_latest.apk`
  - Preview page: `https://greenvpn.pro/release-preview-20260517-private/`

## Важно

- Основной сайт и основные no-ads сборки не обновлялись.
- Секреты, admin token, SSH keys, WireGuard private keys и provider API keys в repo не добавлялись.
- Для выпуска RUVDS в stable нужно отдельно перевести узел из preview allowlist в обычный публичный каталог и провести реальный Android/Windows smoke.
