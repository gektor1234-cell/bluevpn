# Green VPN: project index

Дата фиксации: 2026-07-10.

Этот файл отвечает на вопрос: где что лежит и куда смотреть в первую очередь.

## Основной проект

Корень проекта:

```text
C:\Users\gekto\projects\bluevpn
```

Важные директории:

- `lib/` - общий Flutter-код Android/Windows.
- `android/` - Android native bridge, VpnService, quick tile, APK install.
- `windows/` - Windows runner/native packaging.
- `backend_live/` - backend FastAPI.
- `admin_support_app/` - локальная админка/support panel.
- `scripts/windows/` - сборка Android/Windows, release checks.
- `scripts/infra/` - provider API, создание/проверка VPS/VPN nodes.
- `scripts/ops/` - аварийные backend/SQLite/remote-node операции.
- `scripts/monitoring/` - probes/monitoring.
- `paid_beta_site/` - закрытая noindex paid beta-страница, не production root.
- `docs/` - handoff/runbooks/product state.
- `secrets/` - локальные secret-файлы, ignored by git.

## Главные документы

- `docs/CURRENT_HANDOFF.md` - короткая актуальная точка входа: stable, paid beta, owner gate.
- `docs/PAID_BETA_EXECUTION_PLAN_2026_07_10_RU.md` - обязательный порядок paid beta.
- `docs/PAID_BETA_TEST_CONTOUR_2026_07_10_RU.md` - live test-only контур, hashes, backups и rollback.
- `docs/PAID_BETA_OPS_AUDIT_2026_07_10_RU.md` - аудит всех control/VPN nodes и граница production-решений.
- `docs/PAID_BETA_FIRST20_RUNBOOK_2026_07_10_RU.md` - owner gate и запуск первых 20.
- `docs/STABLE_FREEZE_2026_07_10_RU.md` - восстановление production stable.
- `docs/GREENVPN_WORKING_MODEL_RU.md` - текущая рабочая логика продукта.
- `docs/GREENVPN_CURRENT_TRIAGE_2026_07_05_RU.md` - текущие проблемы, порядок расследования.
- `docs/SERVER_INFRA_AUDIT_2026_07_05_RU.md` - актуальная карта серверов, Moscow control-plane migration, RUVDS Moscow fallback, live catalog, cleanup/fix.
- `docs/RELEASE_STATE.md` - compact stable/paid-beta release state.
- `docs/INFRA_PROVIDER_AUTOMATION_RU.md` - provider automation runbook.
- `docs/WIREGUARD_MANUAL_CONFIG_NOTES_RU.md` - важная заметка по London manual configs.

Часть старых RU-документов повреждена кодировкой. Использовать их только как исторический материал, не как точный регламент.

## Секреты

Основное внешнее хранилище:

```text
D:\GreenVPN_Secrets
```

Проектный fallback:

```text
C:\Users\gekto\projects\bluevpn\secrets
```

Правило:

- реальные секреты остаются вне git;
- в repo можно хранить только шаблоны без значений;
- значения не печатать в чат;
- перед работой с API использовать скрипты, которые выводят только redacted/status.

Известные secret-файлы без раскрытия значений:

- `provider_api.local.ps1`;
- `ruvds_access.txt`;
- `serverspace_access.txt`;
- `timeweb_access.txt`;
- `smtp_access.txt`;
- `sms_ru_access.txt`;
- `yookassa_access.txt`;
- `admin_staff_owner_access.txt`.

## Ключевые файлы кода

### Flutter client

- `lib/main.dart`
  - API base URL logic;
  - session store;
  - auth start/verify;
  - bootstrap/config;
  - update UI;
  - server picker;
  - support reports.
- `lib/services/managed_config_service.dart`
  - managed config;
  - Android social-only/per-app VPN.

### Android native

- `android/app/src/main/kotlin/pro/greenvpn/app/MainActivity.kt`
  - VpnService bridge;
  - Android owns/does-not-own VPN detection;
  - APK install;
  - native status.
- `android/app/src/main/kotlin/pro/greenvpn/app/GreenVpnQuickTileService.kt`
  - Android quick tile connect/disconnect path.
- `android/app/src/main/AndroidManifest.xml`
  - permissions, VpnService, tile service.

### Backend

- `backend_live/app/main.py`
  - auth/email code;
  - SMTP send;
  - catalog;
  - bootstrap/config;
  - admin/support endpoints;
  - update manifests.

### Admin

- `admin_support_app/app.js`
  - local admin UI data loading;
  - support/users/payments/monitoring views.

## Build scripts

- `scripts/windows/build_android_apk.ps1`
  - Android APK build;
  - preview/stable flags;
  - deploy preview APK.
- `scripts/windows/build_installer.ps1`
  - Windows installer build.
- `scripts/windows/build_release.ps1`
  - release wrapper.
- `scripts/ops/check_public_download_manifests.ps1`
  - APK/EXE manifest mixup check.
- `scripts/ops/create_paid_beta_first20_package.py`
  - защищённый one-shot export 20 персональных beta-кодов после owner gate;
  - полные коды никогда не печатаются в stdout и не попадают в repo.
- `scripts/server/install_paid_beta_contour.sh`
  - изолированная установка/update paid beta на `:8010`;
  - не заменяет production service/DB/downloads.
- `scripts/monitoring/install_paid_beta_probe_systemd.sh`
  - отдельный monitoring timer только для двух разрешённых beta API.

## Provider/infra scripts

- `scripts/infra/test_provider_api.ps1` - safe API inventory/status.
- `scripts/infra/check_scaling_readiness.ps1` - provider readiness.
- `scripts/infra/check_preview_vpn_nodes.ps1` - preview VPN nodes smoke.
- `scripts/infra/prepare_remote_wireguard_node.ps1` - remote WG node bootstrap.
- `scripts/infra/new_test_vps_plan.ps1` - quote/create test VPS with provider API.

## Working tree policy

- Paid beta ведётся в branch `green-vpn-paid-beta-20260710` тематическими commits.
- Не удалять и не откатывать чужие изменения; перед работой всегда проверять `git status --short`.
- Generated builds остаются в `C:\BlueVPN_Builds`, stable checkpoints - в `C:\Users\gekto\GreenVPN_Checkpoints`, secrets - вне Git.
- Старые документы использовать только как историю, если они противоречат `CURRENT_HANDOFF.md` или paid beta-плану.
