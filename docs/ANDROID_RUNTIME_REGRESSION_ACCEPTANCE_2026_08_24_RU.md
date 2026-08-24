# Green VPN Android: runtime regression acceptance

Дата фиксации: 2026-08-24 MSK.

## Итог

Android candidate `0.4.7+2026082401` закрывает три регрессии stable
`0.4.6+2026082001`:

- запуск другого VPN полностью останавливает Green VPN и разоружает
  автоматическое восстановление;
- foreground-подключение ограничено по времени и не ждёт YouTube-проверку;
- режим выбранных приложений включает только реально установленные пакеты,
  остаётся fail-closed и не запускает full-tunnel failover.

Candidate прошёл exact release full-tunnel smoke на эмуляторе и физическом
Android 9, takeover на Android 9 и Android 16, exact-source selected-app
data-plane проверку, а также сценарии полностью отсутствующей и сильно
деградировавшей сети. Candidate не опубликован:
`productionPublished=false`. Windows, backend, production manifests и Friendly
Linnet `5.129.237.163` не менялись.

## Source и исправление

- Branch: `green-vpn-transport-canary-20260711`.
- Exact source commit:
  `be72d1325a568fe56cb4d10ecff03c823e5b780e`.
- Competing-VPN detection сверяет системного владельца VPN с собственным
  package, останавливает Green runtime и сохраняет failover разоружённым после
  исчезновения конкурента.
- Android selected-app policy отбрасывает отсутствующие package names до
  `VpnService.Builder.addAllowedApplication`; пустой или неоднозначный набор не
  расширяется до full tunnel.
- Runtime failover не включается в selected-app режиме.
- Android foreground ограничен двумя кандидатами; bootstrap/config имеют
  ограниченные бюджеты, cached route может стартовать немедленно, а
  post-connect YouTube probe выполняется в фоне.

## Exact artifact

Build root:
`C:\BlueVPN_Builds\android_regression_candidate_20260824_v4`.

| Компонент | Размер | SHA-256 |
|---|---:|---|
| `GreenVPN_Android_0.4.7_2026082401.apk` | `56362397` | `4BA46905702F7A42DD46F768119050FF7F36A31869A2986C0928BBC6F40E5ED2` |

- Application ID: `pro.greenvpn.app`.
- Version: `0.4.7+2026082401`.
- APK подписан; signer SHA-256:
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
- 16 KB page-size compatibility подтверждена.

## Exact release full-tunnel smoke

Эмулятор, API 36:

- evidence root:
  `C:\BlueVPN_Builds\android_regression_smoke_20260824_v4\full-release-v4`;
- installed APK совпал с candidate byte-for-byte;
- direct egress: `5.129.237.163`;
- VPN egress: `37.220.85.211`;
- API: HTTP `200`; YouTube: HTTP `204`;
- foreground connect: `10588 ms`;
- background YouTube: HTTP `204`;
- crash buffer чист, final VPN отключён.

Физический Samsung SM-A530F, Android 9 / API 28:

- evidence root:
  `C:\BlueVPN_Builds\android_regression_smoke_20260824_v4\physical-sm-a530f-full-v1`;
- in-place upgrade `0.4.6+2026082001 -> 0.4.7+2026082401`;
- installed APK совпал с candidate byte-for-byte;
- direct egress: `109.252.21.231`;
- VPN egress: `37.220.85.211`;
- API: HTTP `200`; YouTube: HTTP `204`;
- foreground connect: `13650 ms`;
- background YouTube: HTTP `204`;
- crash buffer чист, final VPN отключён.

Disconnected/connected screenshots на обоих устройствах визуально проверены:
состояния различимы, основные действия помещаются, перекрытий нет.

## Competing-VPN takeover

Exact release прошёл оба системных пути:

- Android 16 emulator: competitor стал активным VPN; Green записал
  `runtime_failover_disarmed reason=competing_vpn_active`; после остановки
  competitor VPN не восстановился в течение `20 s`.
- Android 9 physical: system VPN owner сменился с exact Green UID на test probe
  UID; Green VPN и runtime failover service исчезли. После остановки competitor
  в течение `30 s` не появился ни один VPN, failover service отсутствовал, UI
  показывал `НЕ ЗАЩИЩЕНО`.

Тестовый competing-VPN probe:
`2096699` bytes, SHA-256
`A95AD253B37BAC48828173E9A596DFD4C9B2110EA71429F18AC77B1B4587AD17`.

## Selected-app data plane

Release package не содержит debug control API, поэтому routing contract
проверен отдельным release-signed debug package из того же exact source commit.
Это не подменяет exact release smoke выше и не заявляется как byte-identical
release evidence.

- Debug package: `pro.greenvpn.app.beta`, version
  `0.4.7+2026082402`, SHA-256
  `ABC7B95C48127C94FEAD79E0BCE3F0DE51BFEAC216D18315E2F180CD982A71D8`.
- Android 9 VPN UID range включал только выбранный
  `pro.greenvpn.transportprobe`.
- Selected egress: `37.220.85.211`.
- Unselected direct egress: `109.252.21.231`.
- Selected YouTube: HTTP `204`.
- Runtime failover: `desired=false`.
- Cleanup: VPN отсутствует, preview engines остановлены, failover разоружён.

Таким образом selected package идёт через VPN, unselected package остаётся
direct, а selected режим не наследует full-tunnel fallback.

## Плохая сеть

На API 36 emulator выполнены два изолированных сценария с обязательным
восстановлением сети и очисткой VPN:

- airplane mode: foreground завершился disconnected за `3299 ms`, VPN не
  появился и не восстановился в течение `30 s`;
- `netem delay 1500 ms +/- 500 ms, loss 20%`: foreground завершился
  disconnected за `23286 ms`, то есть до порога `30 s`; ложного VPN и
  повторного подключения не было.

После удаления `netem` production API вернул HTTP `200`, YouTube вернул HTTP
`204`, qdisc вернулся в `noqueue`, VPN отсутствовал. Это подтверждает, что
плохая сеть приводит к ограниченному отказу, а не к безграничному spinner или
скрытому cascade.

## Автоматические проверки

- `flutter analyze`: без замечаний.
- Flutter tests: `138` passed, `14` intentionally skipped.
- Focused transport policy: `22` passed.
- Android unit tests и lint: passed.
- Deterministic exact candidate build и package checks: passed.

## Границы

- Stable production остаётся `0.4.6+2026082001` до отдельного решения о
  публикации `0.4.7`.
- Этот acceptance не меняет Windows/iOS/backend и не выполняет принудительный
  rollout.
- Physical test оставляет exact production `0.4.7+2026082401` установленным,
  но отключённым; это локальный test device, не production publication.
