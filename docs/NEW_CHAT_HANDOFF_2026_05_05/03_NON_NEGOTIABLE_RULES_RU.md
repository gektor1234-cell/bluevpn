# Нельзя нарушать

Это правила проекта, важнее локального удобства конкретной задачи.

## Секреты

Нельзя писать в репозиторий:

- SSH password;
- server password;
- admin token;
- YooKassa secret key;
- SMTP password;
- SMS provider token;
- WireGuard private keys;
- session tokens;
- device tokens;
- private server config.

Нельзя выводить секреты в чат, логи, docs, markdown, release notes.

Если для проверки нужен секрет, использовать переменные окружения, локальный prompt или существующий серверный env, но не сохранять его в git.

## Git / рабочее дерево

В worktree много незакоммиченных изменений.

Нельзя:

- `git reset --hard`;
- `git checkout --`;
- destructive cleanup;
- массово удалять untracked files;
- откатывать чужие изменения без прямого разрешения.

Перед работой:

`git status --short`

Если изменения не относятся к задаче, их не трогать.

## WireGuard / VPN names

Пока не переименовывать внутренние имена:

- `BlueVPNDev1`
- `WireGuardTunnel$BlueVPNDev1`
- `C:\ProgramData\BlueVPN`

Видимое имя продукта:

- `Green VPN`

Почему так: внутренние имена завязаны на рабочий туннель, ProgramData, config/state и существующий device/session flow.

## Friendly / Amnezia / WARP

Нельзя трогать:

- Friendly Linnet/personal server;
- Amnezia;
- WARP;
- чужие WireGuard tunnels;
- чужие VPN services.

Green VPN может детектить competing VPN, показывать статус, мягко отказаться подключаться или предложить отключить другой VPN, но не должен убивать чужие процессы без явного решения.

## Пользовательский UI

Обычный пользователь не должен видеть:

- Backend Admin;
- admin token;
- service health internals;
- raw diagnostics;
- WireGuard private keys;
- endpoint internals;
- dev bypass;
- backend bootstrap terms.

Пользователь должен видеть:

- VPN;
- тариф;
- аккаунт;
- поддержка;
- настройки;
- обновление;
- простые сообщения об ошибках.

## Backend/admin

Admin tooling должно быть отдельно:

- `admin_support_app`;
- admin API;
- role-based access позже.

Admin token не хранить в `localStorage` как единственную долгосрочную модель для production. Сейчас browser-only ручной ввод допустим как MVP/internal, но production должен перейти к нормальному auth/roles.

## Installer

Если меняется пользовательский клиент или service/helper:

- пересобрать Windows release;
- пройти release gate;
- собрать installer;
- проверить, что installer пакует свежий build, а не старый freeze;
- сохранить rollback;
- обновить docs.

Если меняется только backend/admin static app:

- пользовательский installer не нужен.

## Documentation

После стабильного шага обновлять:

- `CURRENT_HANDOFF.md`;
- `RELEASE_STATE.md`;
- `GREENVPN_MASTER_PLAN.md`, если изменился статус плана;
- compact context, если новый чат должен продолжить без старой переписки.
