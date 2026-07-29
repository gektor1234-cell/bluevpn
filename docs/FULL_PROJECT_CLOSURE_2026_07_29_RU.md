# Полное закрытие Green VPN перед production-разрешением

Дата: 29.07.2026, Europe/Moscow

## Итог

Все автономно выполнимые блокеры аудита 28.07 закрыты. Green VPN имеет чистый
source anchor, permanent-Free product contract, два здоровых control plane,
три VPN-узла, exact Android/Windows `0.3.19` candidates, проверенный
шестиступенчатый transport cascade и fail-closed денежные/рекламные функции.

`0.3.19` не опубликован. Это сознательная граница: production publication,
передача ключа подписи и юридические/денежные решения принадлежат владельцу.

## Зафиксированный контракт

| Область | Фактическое состояние |
|---|---|
| Вход | guest-first; email только перед оплатой/restore; SMS отсутствует |
| Free | permanent, не Trial |
| Free quota | stored `3 GB/month`, enforcement off |
| Скорость | stored `10/20 Mbit/s`, rate enforcement off |
| Устройства | stored one device |
| Тарифы | `249/649/1099 RUB`, checkout закрыт |
| Ads | off |
| Forced disconnect | off |
| Paid sales | off |
| Refund execution | off |
| Tax workflow confirmation | off |
| Auto-renew charges | off |

Quota, speed, device count and enforcement are server-side. Их можно менять без
обновления Android/Windows.

## Что исправлено после полного аудита

| Прежний хвост | Результат |
|---|---|
| Публичные старые backend на NL1/London | unit removed, `8000` closed, HTTP tombstone `410` |
| Дублированные DB/env | удалены после полного теста encrypted checkpoint |
| Free/Trial противоречие | выбран permanent Free |
| Невоспроизводимый mixed tree | clean commit `c52ba7d6b3f3cfbda49e63515013ab9a37eaf48a` |
| Android 16 KB/lint/native gate | passed |
| Exact Android matrix | `16/16` routes plus background failover |
| Exact Quick Tile order | WG, AWG, H2, VLESS, Naive, dnstt |
| Exact Windows payload | `63/63` files match installer |
| Windows fallback | injected failure recovered without overlap |
| Stale paid-beta renewal timer | disabled; manual run `enabled=False` |
| NL2 pending maintenance | updated, rebooted, no reboot required |
| `danted` boot race | deterministic `After/Requires=wg-quick@wg0` |
| Temporary test/recovery state | removed from Windows, Android and NL2 |

## Точные кандидаты

Source:

- branch `green-vpn-transport-canary-20260711`;
- commit `c52ba7d6b3f3cfbda49e63515013ab9a37eaf48a`;
- app `0.3.19`;
- Android build `2026072914`;
- Windows build `2914`;
- backend `0.9.152-release-ready.1`.

Artifacts:

| Artifact | SHA-256 | Published |
|---|---|---|
| Android final candidate APK | `16A48F555D2640717A87D3B8927A08F859F05A1169E4DA3D02ED324218A5D990` | no |
| Windows exact installer | `6D5E33B0EAB146C9E2EAA78E8B5F6636B9BCBDDC11D387A07C5B71CB6E9894FB` | no |
| Windows transport ZIP | `F0337840FB021AD4758B420203DAB47A0B52447399DA1AB911AF7B657C1D7D4D` | no |
| Android paid-beta APK | `99EB6C2D44C955F43441039B5375CEC5AF925D19EDAFEE1D17042FAE6E2ED8A7` | no |
| Windows paid-beta installer | `E1451CED069941A431B383E74B20B8E938CD2758C99CBD129F45A731AF1B44D1` | no |

The production Android candidate is signed. Windows production and paid-beta
remain `NotSigned`.

## Физические доказательства

Android:

- exact signed candidate: guest launch, Free UI, real NL1 egress, API,
  YouTube, background retention and clean disconnect;
- exact paid-beta candidate: isolated package, real VPN/API/YouTube and clean
  disconnect;
- post-NL2-maintenance report:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260729_b2914\evidence\android-matrix2914-post-nl2-maintenance-physical.json`,
  SHA-256
  `8B34832AD83C2954837A2F319364DB23204BC8370EE12F268D56153D14F7B3C0`;
- post-maintenance Quick Tile report:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260729_b2914\evidence\android-matrix2914-post-nl2-maintenance-quick-tile.json`,
  SHA-256
  `806E7333A5144FD3833560DB976BAB1B0669C90EE1D4277E5F1C07FB47CE56AF`.

Windows:

- five alternate transports:
  `C:\BlueVPN_Builds\public_product_20260729_b2914\windows-exact-transport-cascade-physical.json`,
  SHA-256
  `6B54A96996AF5E5A7E03D6BE5E1A68A8827607596E54F49E0FA816278E276F19`;
- installed payload exactness:
  `C:\BlueVPN_Builds\public_product_20260729_b2914\windows-installed-payload-exactness.json`,
  SHA-256
  `AC9FB88AF5A7A267BEE535CB8B1FBEC29FE964E5C1AB9266AAD8E304AB8B8E01`;
- production runtime failover:
  `C:\BlueVPN_Builds\public_product_20260729_b2914\windows-public-runtime-failover-physical.json`,
  SHA-256
  `D67D443CA0AF096FF6E46E2B4ECEF75E1C1AFF1A72FC69B498ABFFDC1AC26746`.

Windows cleanup restored the owner's original Amnezia tunnel and egress. The
temporary emergency watchdog/failsafe was removed.

## Серверы

Allowed nodes were audited by direct IP; Friendly Linnet was not touched.

- Timeweb control `72.56.32.197`: prod/beta active, sync active, zero failed
  units, zero actionable updates.
- RUVDS control `176.113.81.35`: prod/beta active, sync active, zero failed
  units, zero actionable updates.
- Paid-beta fail-closed policy is explicit rather than default-dependent on both
  control planes: quota/rate enforcement, paid sales, tax confirmation, refund
  execution, renewal charging and every Rewarded/test gate are set off. The
  guarded env backups are:
  `/root/greenvpn-paid-beta-explicit-failclosed-backups/20260729T072608Z`
  on Timeweb and
  `/root/greenvpn-paid-beta-explicit-failclosed-backups/20260729T072610Z`
  on RUVDS.
- NL1 `37.220.85.211`: five transports active, legacy backend absent.
- London `88.218.250.86`: five transports active, legacy backend absent.
- NL2 `5.129.216.42`: all transports including dnstt active; system current;
  `qemu-guest-agent` remains intentionally held by provider policy.

Secret-safe final runtime reports are in:

`C:\BlueVPN_Builds\public_product_final_candidate_20260729_b2914\server-audit-final`.

## Security and rollback

- Defender scanned all exact APK/ZIP/EXE candidates with zero detections.
- tracked, untracked and Git-history secret scan passed.
- Final source-tree verification passed: backend `174/174`, Flutter `64`
  passed with `6` intentional skips, Android Gradle/unit/lint
  `283` tasks, strict release gate `0` warnings / `0` errors and Python
  dependency audit with no known vulnerabilities.
- production and paid-beta databases pass SQLite quick check.
- Keyed, value-blind comparison proves exact primary/fallback functional
  contract parity in both contours for `server_catalog_entries`,
  `app_releases`, `admin_feature_flags` and
  `admin_owner_action_statuses`. Node-local timestamps and latency observations
  were deliberately excluded from the functional projection.
- public downloads still match all eight current manifests.
- Post-hardening public-surface probe passed `31/31`; report:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260729_b2914\evidence\public-surface-final-post-hardening.json`,
  SHA-256
  `D2484A62CE3865B734F0F5E1AFEE1DA09A5152D1CE6F343483E5A8EFD2FA5E2C`.
- encrypted checkpoint:
  `C:\Users\gekto\GreenVPN_Checkpoints\full_closure_pre_20260728_2230`;
  server archive passes full `7z t` and its manifest covers all five allowed
  nodes.

## Что осталось владельцу

For Free direct release:

1. Provide an Authenticode Code Signing identity/private-key mechanism.
2. Give explicit production go/no-go for exact signed successors.
3. Perform the short final owner smoke after publication.

Only before paid sales:

4. Confirm legal/tax/KYC status and the valid receipt/refund process.
5. Explicitly authorize any real refund or auto-renew charge test.

Optional future scopes:

- Google Play publication/account work;
- Rewarded provider selection and paid-beta smoke;
- dnstt redundancy;
- canonical landing parity before a future RСЯ reapplication.

None of these optional scopes blocks the current permanent-Free direct product.
