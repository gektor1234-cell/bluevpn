# Неприкосновенные правила

## Бренд и имена

- Видимый бренд: `Green VPN`.
- Внутренние имена пока не переименовывать:
  - `BlueVPNDev1`;
  - `WireGuardTunnel$BlueVPNDev1`;
  - `C:\ProgramData\BlueVPN`.

Причина: эти имена завязаны на установленный WireGuard tunnel, service/task logic, installer cleanup, runtime state and rollback.

## Чужие VPN не трогать

Нельзя трогать:

- Friendly Linnet/personal server;
- Amnezia;
- WARP;
- чужие WireGuard tunnels;
- WireGuard installation itself.

Green VPN cleanup должен удалять только Green VPN artifacts.

## Секреты

Нельзя писать в repo, docs или чат:

- admin token;
- SSH/root password;
- SMTP password;
- SMS API key;
- YooKassa secret key;
- Telegram bot token;
- WireGuard private key;
- full private WireGuard config.

Все секреты - только server-side env на `37.220.85.211`.

## Git/destructive

Нельзя без прямого разрешения:

- `git reset --hard`;
- `git checkout --`;
- recursive destructive cleanup;
- массово удалять build/output/worktree файлы.

## Installer

Не собирать новый installer после каждого backend/admin шага.

Новый installer нужен только:

- на финальном handoff;
- по явной просьбе пользователя;
- после изменений в пользовательском клиенте, когда нужен fresh install test.

## Product positioning

Не писать публично:

- обход блокировок;
- разблокируем YouTube/Instagram/Discord;
- анонимность без следов;
- невозможно заблокировать;
- работает всегда и везде;
- безлимит без ограничений.

Использовать:

- защищенное подключение;
- стабильный доступ к привычным онлайн-сервисам;
- защита в публичных Wi-Fi;
- понятная подписка;
- поддержка и простой installer.
