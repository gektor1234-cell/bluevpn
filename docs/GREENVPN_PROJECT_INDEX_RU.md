# Green VPN: legacy project index

Этот путь сохранён для старых ссылок. Актуальная навигация находится в
`docs/README.md`; дублировать здесь карту проекта больше не нужно.

Порядок чтения:

1. `docs/CURRENT_HANDOFF.md` - живое состояние и запреты.
2. `docs/RELEASE_STATE.md` - версии, rollback и launch gates.
3. `docs/PROJECT_MAP_RU.md` - где находится код, runtime и операции.
4. `docs/PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md` - deploy/backup/restore.
5. `docs/SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md` - добавление нового
   сервера или transport preview.

Корень проекта: `C:\Users\gekto\projects\bluevpn`.

Секреты хранятся только во внешнем защищённом хранилище или root-only server
env/config. Реальные значения нельзя переносить в Git, документы, чат, логи или
обычные архивы.
