# Green VPN: server infrastructure audit 2026-07-05

Дата: 2026-07-05.

Документ фиксирует актуальную серверную карту после read-only аудита и минимального cleanup/fix. Секреты, токены, private keys и WireGuard private keys здесь не указываются.

## Правила

- Friendly Linnet / FriendlyLynet не трогать.
- Stable/main не менять без явного решения владельца.
- Удаления live-данных сначала делать через quarantine или backup.
- KZ, London и новые узлы не публиковать/не убирать из stable вслепую: сначала сверить с текущей политикой и real-device smoke.

## Provider inventory

### Timeweb

API видит 5 серверов:

- `5572365` / Friendly Linnet / `5.129.237.163` / no-touch.
- `7126733` / Intelligent Smew / `37.220.85.211` / origin/backend/nl1.
- `7841818` / Friendly Cetus / `72.56.32.197` / public site, admin static site, API reverse proxy.
- `7879598` / GreenVPN NL1 VPN 20260511 / `5.129.216.42` / managed Netherlands #2 VPN node.
- `8360589` / greenvpn-tw-kz1-test-01 / `94.198.221.206` / KZ test node, currently unreachable from backend and nonpublic.

Timeweb balance at audit: about `4870.76 RUB`.

### RUVDS

API sees 1 server:

- `2584554` / LD8 London / `88.218.250.86` / active / RUVDS London #1 and current public backend host behind the API proxy.

RUVDS balance at audit: `267 RUB`; Zurich create gate is not ready.

### Serverspace

Project active, balance about `0.50 EUR`, server count `0`.

## DNS and public routing

- `greenvpn.pro` -> `72.56.32.197`.
- `api.greenvpn.pro` -> `72.56.32.197`.
- `nl1.vpn.greenvpn.pro` -> `37.220.85.211`.
- `nl2.vpn.greenvpn.pro` -> `5.129.216.42`.
- `gb1.vpn.greenvpn.pro` has no A record.
- `kz1.vpn.greenvpn.pro` has no A record.

`72.56.32.197` nginx now terminates TLS for `api.greenvpn.pro` and proxies API traffic to the local Moscow backend: `http://127.0.0.1:8000`.

`https://88-218-250-86.sslip.io` remains an application fallback URL for already built clients, but its catalog has been aligned with the primary catalog and no longer publishes the old built-in `intelligent_smew` entry.

## Live catalog state

Stable and preview currently expose the same public VPN servers through the Moscow primary API and the RUVDS fallback API:

- `current_wg0` / Netherlands #1 / `nl1.vpn.greenvpn.pro:443` / `remote_ssh_wg0`.
- `ruvds-2584554-ld8` / RUVDS London #1 / `88.218.250.86:443` / `remote_ssh_wg0`.
- `tw-7879598-nl1` / Netherlands #2 / `nl2.vpn.greenvpn.pro:443` / `remote_ssh_wg0`.

The old built-in catalog entry `intelligent_smew` is disabled on control-plane backends with `GREENVPN_DISABLE_BUILTIN_WG0_CATALOG=1`.

Important policy note: RUVDS London is still a foreign fallback/control backend because no separate RUVDS Russia control-plane server exists yet. The desired final shape is two Russian control-plane servers, one in Timeweb and one in RUVDS, with foreign VPS used only as VPN nodes.

Inactive/nonpublic entries:

- `tw-8147243-de1` / Germany #1 / disabled / retired.
- `tw-kz1-test-01` / Kazakhstan #1 / maintenance / nonpublic / remote provisioning fails by timeout.

## VPN node status

- `37.220.85.211`: `wg0` active, about 42 peers, `10.10.0.1/24`, NAT enabled.
- `5.129.216.42`: `wg0` active, about 11 peers, `10.10.0.1/24`, NAT enabled.
- `88.218.250.86`: `wg0` active, about 12 peers, `10.10.0.1/24` and `10.66.66.1/24`, NAT enabled.
- `94.198.221.206`: SSH port `22222` timed out; backend remote provisioning reports timeout.

## Fixes applied

On `88.218.250.86`:

- Disabled and stopped `greenvpn-service-probe.timer`.
- Disabled and stopped `greenvpn-vpn-capacity-report.timer`.
- Added systemd drop-in `/etc/systemd/system/bluevpn-backend.service.d/zz-sqlite-wal.conf`.
- Set `BLUEVPN_SQLITE_ENABLE_WAL=1`.
- Restarted `bluevpn-backend`.
- Verified SQLite `journal_mode=wal`.

Result:

- Before fix, `/api/v1/catalog/servers` and `/api/v1/catalog/resilience` timed out.
- After fix, public catalog/resilience respond in about 3-7 seconds.
- Recent `database is locked` errors disappeared after restart/WAL/timer stop.

Additional repair after Android screenshots:

- Symptom: Android showed `Ошибка bootstrap (500)` for `https://88-218-250-86.sslip.io/api/v1/client/bootstrap`.
- Traceback on RUVDS: `sqlite3.DatabaseError: database disk image is malformed` during `subscription_traffic_usage_status(...)`; later the same DB corruption also hit `server_health_meta_for_entries(...)`.
- Full pre-repair DB snapshot was copied to `/root/greenvpn-db-repair-20260705_062514/` before destructive cleanup.
- Rebuilt damaged indexes for `device_traffic_usage` and `server_health_observations`.
- Dropped and recreated only noisy historical/telemetry tables: `admin_audit_log`, `admin_alert_events`, `client_route_events`, `resilience_route_observations`, `server_health_observations`, `service_availability_observations`.
- Preserved critical state: `users`, `tokens`, `devices`, `subscriptions`, `billing_orders`, `server_catalog_entries`, `client_endpoint_assignments`, admin staff/sessions/settings, support reports, auth/email/SMS records.
- Ran `VACUUM`; DB shrank from about 515 MB to about 848 KB.
- Verified `PRAGMA quick_check = ok`.
- Verified public fallback bootstrap with a temporary test user: `POST https://88-218-250-86.sslip.io/api/v1/client/bootstrap` returned `200`, `ok=true`, `trafficUsage` present; test user/device/token were removed.
- Verified no new `DatabaseError` / `500 Internal Server Error` entries in fresh backend logs after repair.

Follow-up after email-code login screenshot:

- Symptom: Android login screen showed `Ошибка сервера (500): Internal Server Error` after pressing `Получить код`.
- Traceback: `POST /api/v1/auth/challenge/start` failed in `ensure_user_for_email_code(...)`; SQLite reported `malformed database schema (...)`.
- The previous quick repair was not sufficient: the live SQLite schema became unreadable again after new writes.
- Performed full app-schema rebuild into a clean SQLite database:
  - source snapshot: `/root/greenvpn-db-repair-20260705_062514/`;
  - final rebuild directory: `/root/greenvpn-db-schema-rebuild-20260705_064310/`;
  - old live DB and old `bluevpn.db.bak_*` files were moved into the rebuild directory, not deleted.
- Imported critical live state into the clean DB: `users`, `tokens`, `devices`, `subscriptions`, `billing_orders`, `server_catalog_entries`, `client_endpoint_assignments`, admin/support/auth configuration and small auth/outbox tables.
- Removed old orphan rows during rebuild: `tokens` 7, `email_confirmations` 7, `email_outbox` 7.
- Kept noisy history empty in the clean DB: `admin_audit_log`, `admin_alert_events`, `client_route_events`, `device_traffic_usage`, `resilience_route_observations`, `server_health_observations`, `service_availability_observations`.
- Verified `PRAGMA foreign_key_check` count `0`.
- Verified `PRAGMA quick_check = ok` before and after `VACUUM`.
- Installed clean `/opt/bluevpn/backend/data/bluevpn.db` at about 804 KB.
- Verified `POST https://api.greenvpn.pro/api/v1/auth/challenge/start` for email-code login returned `200`, `ok=true`, `deliveryStatus=sent`, `codeDigits=4`.
- Verified public `healthz`, catalog, resilience, and Android preview update manifest return `200`.
- Verified no fresh `500`, `DatabaseError`, or `malformed database schema` log entries after backend restart at `2026-07-05 06:43:20 MSK`.

Cleanup moved to quarantine, not deleted:

- On `88.218.250.86` and `37.220.85.211`, retired Frankfurt `tw-8147243-de1` node env/key files moved from `/etc/bluevpn/vpn_nodes` to `/root/greenvpn-cleanup-quarantine-20260705/...`.
- Zero-byte `/opt/bluevpn/backend/data/bluevpn.sqlite` moved to the same quarantine.

## Control-plane migration 2026-07-05

Root cause found after the Android 500 screenshots:

- `37.220.85.211` had `greenvpn-sync-backup-api.timer` running every 5 minutes.
- The script `/usr/local/sbin/greenvpn-sync-backup-api.sh` copied a SQLite snapshot directly into the live RUVDS DB path `/opt/bluevpn/backend/data/bluevpn.db` while the RUVDS backend was running.
- This is why RUVDS DB corruption returned after initial repair.
- The timer/service were disabled on `37.220.85.211`: `greenvpn-sync-backup-api.timer` and `greenvpn-sync-backup-api.service`.

Moscow control-plane now active:

- `72.56.32.197` has a local FastAPI backend under `/opt/bluevpn/backend`.
- `bluevpn-backend.service` runs on `127.0.0.1:8000`.
- nginx `greenvpn-api` now proxies `api.greenvpn.pro` to `http://127.0.0.1:8000`.
- nginx backup before switch: `/root/greenvpn-nginx-backups/greenvpn-api.20260705T041556Z`.

Database/control data:

- Clean SQLite DB was installed on `72.56.32.197` and `88.218.250.86`.
- `PRAGMA quick_check = ok` on both.
- Critical counts after migration: `users=28`, `tokens=90`, `devices=52`, `subscriptions=28`, `server_catalog_entries=5`.

Remote VPN node provisioning:

- `current_wg0` was converted from `builtin_wg0` to managed `remote_ssh_wg0` on both primary and fallback control backends.
- Dedicated server-only SSH keys were created for `current_wg0` on `72.56.32.197` and `88.218.250.86`; only public keys were installed on `37.220.85.211`.
- RUVDS London node env had a stale WireGuard public key; it was synced to the actual `wg0` public key. Private keys were not printed or copied into docs.
- `ruvds-2584554-ld8.env` on RUVDS remains protected with immutable attribute.

Code/config change:

- `backend_live/app/main.py` now supports `GREENVPN_DISABLE_BUILTIN_WG0_CATALOG=1`.
- The flag is enabled via systemd drop-in on `72.56.32.197` and `88.218.250.86`.
- With the flag enabled, local `wg0` is not published as `intelligent_smew`; clients receive only managed remote catalog entries.

Verification after migration:

- `https://api.greenvpn.pro/healthz` returns `200`.
- `https://api.greenvpn.pro/api/v1/catalog/servers` returns default `current_wg0` and exactly 3 servers: `current_wg0`, `ruvds-2584554-ld8`, `tw-7879598-nl1`.
- `https://88-218-250-86.sslip.io/api/v1/catalog/servers` returns the same 3 server IDs and the same default.
- Both primary and fallback catalog bootstrap blocks expose only `https://api.greenvpn.pro`; old raw `http://37.220.85.211:8000` was removed from active RUVDS systemd drop-ins.
- Remote provisioning checks are green for all 3 public nodes on both primary and fallback.
- Client-config smoke is green for all 3 public nodes on both primary and fallback: peer applied, config shape ok, peer removed.
- Auth/email/network readiness are green on the Moscow backend.

Cleanup moved to quarantine, not deleted:

- On `72.56.32.197`: `/root/greenvpn-control-plane-quarantine-20260705T0418Z`, 66 old env/backup files.
- On `88.218.250.86`: `/root/greenvpn-control-plane-quarantine-20260705T0422Z`, 12 old env/backup files.

## Moscow DB state sync 2026-07-05

Goal:

- Keep Timeweb Moscow `72.56.32.197` and RUVDS Moscow `176.113.81.35` close enough that API fallback keeps knowing current users, tokens, devices, ad grants, login codes, releases, and catalog state.
- Remove the old unsafe pattern where a SQLite file was copied into a live backend DB path.

Installed files on both Russian control-plane servers:

- `/usr/local/sbin/greenvpn_sqlite_snapshot_stdout.py`
- `/usr/local/sbin/greenvpn_sqlite_state_sync.py`
- `/usr/local/sbin/greenvpn_db_sync_from_peer.sh`
- `/etc/bluevpn/db-sync.env`
- `/etc/systemd/system/greenvpn-db-sync.service`
- `/etc/systemd/system/greenvpn-db-sync.timer`

Runtime behavior:

- `greenvpn-db-sync.timer` runs every 30 seconds after boot.
- Each server connects to the peer over the dedicated root SSH key `/root/.ssh/greenvpn_db_sync_ed25519`.
- The peer creates a consistent SQLite backup snapshot with the SQLite backup API and streams it over SSH.
- The receiver stores the peer snapshot in `/var/lib/greenvpn-db-sync/` and merges rows into `/opt/bluevpn/backend/data/bluevpn.db`.
- Merge is by natural application keys, not by blind file replacement.
- Rows are updated only when the peer row is newer by known timestamp columns.
- Conflicts are counted in the summary JSON and left untouched.

Current peers:

- Timeweb `72.56.32.197` pulls from RUVDS `176.113.81.35`, peer name `ruvds_m9`.
- RUVDS `176.113.81.35` pulls from Timeweb `72.56.32.197`, peer name `timeweb`.

Verification after enabling:

- `systemctl is-active greenvpn-db-sync.timer` returned active on both servers.
- `systemctl --failed` returned no failed units on both servers.
- `PRAGMA quick_check` returned `ok` on both live DBs.
- Public health endpoints returned OK:
  - `https://api.greenvpn.pro/healthz`
  - `https://176-113-81-35.sslip.io/healthz`
- Last stable sync summaries reached `inserted=0`, `updated=0`, `conflicts=0`, `errors=0`.
- Critical table counts matched on both servers:
  - `users=29`
  - `tokens=94`
  - `devices=54`
  - `subscriptions=29`
  - `ad_challenges=81`
  - `free_access_grants=76`
  - `client_endpoint_assignments=52`
  - `email_login_codes=134`
  - `email_outbox=140`
  - `billing_orders=4`

Pre-change live DB backups:

- Timeweb: `/root/greenvpn-db-sync-prechange/bluevpn.db.before_state_sync_20260705T074327Z.sqlite`
- RUVDS: `/root/greenvpn-db-sync-prechange/bluevpn.db.before_state_sync_20260705T074327Z.sqlite`

Disable sync only:

```bash
systemctl disable --now greenvpn-db-sync.timer
```

Full rollback outline if sync itself must be removed:

```bash
systemctl disable --now greenvpn-db-sync.timer
systemctl stop greenvpn-db-sync.service || true
rm -f /etc/systemd/system/greenvpn-db-sync.timer /etc/systemd/system/greenvpn-db-sync.service
systemctl daemon-reload
```

To restore one of the pre-change SQLite backups, stop the backend first, copy the chosen backup over `/opt/bluevpn/backend/data/bluevpn.db`, fix ownership/permissions if needed, then start the backend and run `PRAGMA quick_check`.

Design limitation:

- This is a practical near-real-time SQLite state merge for the current two-Russian-server control-plane.
- It is not a mathematically perfect active-active DB cluster. If both sides accept conflicting writes at the same time during a split-brain, the conflict is logged and not auto-overwritten.
- For strict active-active semantics, migrate the control-plane DB to PostgreSQL, rqlite, LiteFS, or another replication layer with explicit consistency guarantees.

## Ads temporarily disabled 2026-07-05

Owner request: turn off rewarded ads and the free-ad session timer for now.

Applied on:

- Timeweb Moscow `72.56.32.197`
- RUVDS Moscow `176.113.81.35`
- RUVDS London legacy `88.218.250.86`

Changed in `/etc/bluevpn/backend.env` on each server:

- `GREENVPN_FREE_AD_GATE_ENABLED=0`
- `GREENVPN_FREE_AD_GATE_PROVIDER=disabled`
- `GREENVPN_FREE_AD_GATE_CLIENT_MARKER=`
- `GREENVPN_FREE_AD_GATE_PLATFORMS=`
- `GREENVPN_FREE_AD_SESSION_TIMER_ENABLED=false`
- `GREENVPN_FREE_AD_SESSION_SECONDS=0`
- `GREENVPN_FREE_AD_SESSION_MAX_CONNECTS=0`
- `GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED=0`
- `GREENVPN_YANDEX_REWARDED_ANDROID_AD_UNIT_ID=`

Backups were saved before editing:

- `/root/greenvpn-ad-disable-backup/backend.env.20260705T075941Z` on `72.56.32.197`
- `/root/greenvpn-ad-disable-backup/backend.env.20260705T075941Z` on `176.113.81.35`
- `/root/greenvpn-ad-disable-backup/backend.env.20260705T075853Z` on `88.218.250.86`

Verification:

- `bluevpn-backend.service` restarted and is active on all three servers.
- Public `/healthz` is OK on all three servers.
- `/api/v1/ads/free-access/me` returns:
  - `enabled=false`
  - `required=false`
  - `sessionTimerEnabled=false`
  - `sessionTtlSeconds=0`
  - `androidRewarded.enabled=false`
  - no Android ad unit id

## Stable production release 2026-07-05

Owner request: promote the currently verified client line to the main site and enable the update popup.

Windows stable:

- Version in manifest: `0.2.39-windows-clean-server-ui`.
- Public primary URL: `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`.
- Public RUVDS Moscow URL: `https://176-113-81-35.sslip.io/downloads/GreenVPN_Setup.exe`.
- Size: `12814336` bytes.
- SHA256: `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Manifest status on primary, RUVDS Moscow, and legacy London:
  - `required=true`
  - `updateAvailable=true` for old Windows clients
  - `releaseBlocked=false`

Android stable:

- Stable APK was rebuilt from the current client code without the `preview` version marker.
- Version: `0.2.44`.
- Android `versionCode`: `2026070504`.
- Local artifact: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_2026070504_stable.apk`.
- Public primary URL: `https://greenvpn.pro/downloads/GreenVPN_Android.apk`.
- Public RUVDS Moscow URL: `https://176-113-81-35.sslip.io/downloads/GreenVPN_Android.apk`.
- Versioned copy on both download servers: `/var/www/greenvpn/downloads/GreenVPN_Android_0.2.44_2026070504_stable.apk`.
- Size: `65543311` bytes.
- SHA256: `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- APK signature verification: v2 signature valid, one signer.
- Main Android alias backups were saved under `/root/greenvpn-site-backups/GreenVPN_Android_pre_stable_0.2.44_*.apk`.

Android manifest change:

- `GREENVPN_ANDROID_LATEST_VERSION=0.2.44`.
- `GREENVPN_ANDROID_UPDATE_REQUIRED=true`.
- `GREENVPN_ANDROID_PREVIEW_LATEST_VERSION=0.2.44`.
- `GREENVPN_ANDROID_PREVIEW_UPDATE_REQUIRED=true`.
- Stable and preview Android clients are both moved to the stable `0.2.44` APK.

Backend env backups before the Android manifest switch:

- Timeweb Moscow: `/root/greenvpn-stable-release-backup/backend.env.before_android_0.2.44_20260705T082558Z`.
- RUVDS Moscow: `/root/greenvpn-stable-release-backup/backend.env.before_android_0.2.44_20260705T082557Z`.
- RUVDS London legacy: `/root/greenvpn-stable-release-backup/backend.env.before_android_0.2.44_20260705T082510Z`.

Verification:

- Public `/healthz` is OK on Timeweb Moscow, RUVDS Moscow, and legacy London.
- Public HTTP HEAD for both Android aliases returns `Content-Length: 65543311`.
- Public HTTP HEAD for both Windows aliases returns `Content-Length: 12814336`.
- Server-side hashes match manifest values on both download servers.
- Manifest checks:
  - Android old stable `0.2.23-trial-only-android-vpn-takeover` -> `latestVersion=0.2.44`, `required=true`, `updateAvailable=true`.
  - Android preview `0.2.43-preview` -> `latestVersion=0.2.44`, `required=true`, `updateAvailable=true`.
  - Android current `0.2.44` -> `updateAvailable=false`.
  - Windows old `0.2.22-trial-only-manual-server-switch` -> `latestVersion=0.2.39-windows-clean-server-ui`, `required=true`, `updateAvailable=true`.

## Remaining cleanup candidates

- Large DB backups on `37.220.85.211` and `88.218.250.86`: keep until a real backup-retention rule is decided.
- Many old APK preview files and `/root/greenvpn-site-backups` on `72.56.32.197`: safe to prune only after deciding how many rollback artifacts must remain.
- DB row for retired `tw-8147243-de1`: leave disabled for history unless owner confirms hard removal.
- KZ server: currently paid/running but unreachable; decide whether to repair, stop, or delete after provider-panel check.
- RUVDS London in stable: decide whether to keep public or demote to preview after Android real-device traffic smoke.

## Current verification commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ops\check_public_download_manifests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\check_preview_vpn_nodes.ps1 -SkipPeerSmoke -SkipClientConfigSmoke
```

Expected current result:

- Downloads/update manifests: ok.
- Catalog readable: yes.
- `tw-7879598-nl1`: ok.
- `ruvds-2584554-ld8`: ok.
- `tw-kz1-test-01`: fails remote provisioning and remains nonpublic.

## RUVDS Moscow control-plane completion 2026-07-05

New RUVDS Russia control-plane server:

- Provider/server id: `2677054`.
- Internal name: `greenvpn-ruvds-m9-control-01`.
- Public IPv4: `176.113.81.35`.
- HTTPS host: `https://176-113-81-35.sslip.io`.
- Datacenter: RUVDS Moscow M9.
- Role: Russian fallback control-plane/API/download mirror. It is not a public VPN node.

Runtime state:

- `/opt/bluevpn/backend` contains the FastAPI backend copied from Moscow Timeweb.
- `bluevpn-backend.service` runs uvicorn on `127.0.0.1:8000`.
- nginx terminates TLS for `176-113-81-35.sslip.io` and proxies API traffic to the local backend.
- `wireguard-tools` is installed only so backend smoke/client-config checks can generate temporary WireGuard keys.
- `GREENVPN_DISABLE_BUILTIN_WG0_CATALOG=1` is enabled.
- `GREENVPN_API_BASE_URLS=https://api.greenvpn.pro,https://176-113-81-35.sslip.io` is active on Timeweb Moscow, RUVDS Moscow, and legacy RUVDS London.

Downloads:

- `greenvpn.pro` still resolves to Russian Timeweb `72.56.32.197`.
- RUVDS Moscow mirrors only active public download aliases, not the full historical 2.7 GB build archive:
  - `/downloads/GreenVPN_Android.apk`;
  - `/downloads/GreenVPN_Android_preview_latest.apk`;
  - `/downloads/GreenVPN_Setup.exe`;
  - `/downloads/GreenVPN_Setup_preview_latest.exe`;
  - `/downloads/GreenVPN_Setup_0.2.10_adgate_preview_routeprobe.exe`.
- RUVDS Moscow nginx serves `/downloads/`, `/download/android`, and `/download/windows`.
- RUVDS Moscow and legacy RUVDS London update manifests now point download URLs to `https://176-113-81-35.sslip.io/downloads/...`.

Verification:

- `https://api.greenvpn.pro/healthz`, `https://176-113-81-35.sslip.io/healthz`, and `https://88-218-250-86.sslip.io/healthz` return `ok=true`, version `0.9.105`.
- Primary, RUVDS Moscow, and legacy London catalogs expose the same public VPN nodes: `current_wg0`, `ruvds-2584554-ld8`, `tw-7879598-nl1`.
- Catalog bootstrap blocks expose `https://api.greenvpn.pro` and `https://176-113-81-35.sslip.io`.
- Full remote provisioning, peer smoke, and client-config smoke are green from RUVDS Moscow for all three public VPN nodes.
- Email readiness, auth user-flow readiness, and network readiness are green on primary, RUVDS Moscow, and legacy London.

Client/build defaults:

- `lib/main.dart` fallback default is now `https://176-113-81-35.sslip.io`.
- Android Quick Tile fallback default is now `https://176-113-81-35.sslip.io`.
- Windows/Android build scripts default `BLUEVPN_API_BASE_URLS` / fallback API to `https://176-113-81-35.sslip.io`.

Client auth failover fix and preview release 2026-07-05:

- Point 4 was closed in the client with sticky API origin for auth/session flow.
- `Session` now persists `apiBaseUrl`.
- Email/phone/challenge code start remembers the API base that accepted the start request.
- Code verify is sent back to the same API base, so SQLite auth codes are not checked on a different control-plane copy.
- Bearer bootstrap/config requests prefer the saved session API base and only fail over on retriable network/5xx failures.
- Android Quick Tile also prefers `session.apiBaseUrl` for bootstrap/config.
- New Android preview APK: `0.2.41-preview`, build `2026070501`.
- Local artifact: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.41_2026070501_preview.apk`.
- Public primary URL: `https://greenvpn.pro/downloads/GreenVPN_Android_preview_latest.apk`.
- Public RUVDS Moscow URL: `https://176-113-81-35.sslip.io/downloads/GreenVPN_Android_preview_latest.apk`.
- Size: `66166687` bytes.
- SHA256: `2E4EF06D823226C4705D03F4FFA6EC1DC299B9B1FA5185C7968F1BDA44B19F70`.
- Primary, RUVDS Moscow, and legacy London preview update manifests now return `latestVersion=0.2.41-preview`, `updateAvailable=true`, `releaseBlocked=false`, and the same SHA256.
- Full GET hash verification passed for both public APK URLs.
- `scripts\ops\check_public_download_manifests.ps1` passed after publish.
- `flutter test --no-pub` passed. `dart analyze` still reports pre-existing warnings/infos in `lib/main.dart`; no syntax/build blocker for the APK.

SMTP/auth-code hotfix 2026-07-05:

- Symptom after `0.2.41-preview`: `TimeoutException after 0:00:08.000000: Future not completed` on `Получить код`.
- Direct checks showed `POST /api/v1/auth/email/code/start` timed out on primary Timeweb and RUVDS Moscow, while legacy London responded in about 1.7 s.
- Root cause: primary and RUVDS Moscow used `GREENVPN_SMTP_PORT=2587` against `smtp.yandex.ru`; this is not a working public Yandex SMTP port. Primary Timeweb also cannot reach Yandex SMTP ports directly from this VPS.
- RUVDS Moscow can reach `smtp.yandex.ru:465` and `smtp.yandex.ru:587`.
- Fix:
  - RUVDS Moscow backend now uses `GREENVPN_SMTP_HOST=smtp.yandex.ru`, `GREENVPN_SMTP_PORT=465`.
  - RUVDS Moscow runs `greenvpn-smtp-relay.service`, a restricted Python TCP relay on `0.0.0.0:2587` to `smtp.yandex.ru:587`, allowing only primary `72.56.32.197`.
  - Primary Timeweb backend now uses `GREENVPN_SMTP_HOST=176.113.81.35`, `GREENVPN_SMTP_PORT=2587`, `GREENVPN_SMTP_USE_TLS=1`.
- Verification after fix:
  - `api.greenvpn.pro` email-code start: about 1.5 s, `deliveryStatus=sent`.
  - `176-113-81-35.sslip.io` email-code start: about 1.3 s, `deliveryStatus=sent`.
  - `88-218-250-86.sslip.io` email-code start: about 1.7 s, `deliveryStatus=sent`.
  - `greenvpn-smtp-relay.service` on RUVDS Moscow is `enabled` and `active`.

Legacy note:

- `https://88-218-250-86.sslip.io` remains online only for already-built clients that still have the old hardcoded fallback.
- New builds should use the Russian RUVDS fallback and should not depend on London as a control-plane.
