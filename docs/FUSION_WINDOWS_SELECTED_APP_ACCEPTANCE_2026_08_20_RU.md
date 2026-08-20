# Green VPN Fusion Windows: selected-app acceptance

Дата фиксации: 2026-08-20 MSK.

## Итог

Windows candidate `0.4.6+4634` технически принят по точному физическому
сценарию `full -> applications -> full`. Selected executable подтвердил
выход через dedicated VPN, selected YouTube вернул HTTP `204`, а после прогона
исходный Amnezia/API/YouTube baseline был восстановлен.

Candidate не опубликован. `productionPublished=false`; stable production,
Android, backend и Friendly Linnet `5.129.237.163` не менялись. До публикации
остаются только три последовательных owner gates, перечисленные в конце.

## Source и исправление

- Exact source commit:
  `58c3ac8c54395980b7addb5ad094a58786c8b30e`.
- Branch: `green-vpn-transport-canary-20260711`.
- Причина отказа `+4633`: после успешной attribution и `WinDivertSend`
  selected TCP packet сохранял внешний source при loopback destination, поэтому
  Windows не доставлял его локальному relay listener.
- Исправление переписывает обе стороны relay tuple в IPv4/IPv6 loopback,
  сохраняет исходный tuple для обратного восстановления и оставляет listener
  доступным только через loopback. Небезопасный remote-only или port-only
  attribution fallback не добавлялся; неоднозначность остается fail-closed.

Предыдущие результаты не перезапускались и не терялись: `+4630` не подтвердил
selected egress, `+4631` был отклонен package audit из-за кодировки installer
UI, `+4632` выявил catalog single-flight race, а `+4633` локализовал
post-attribution relay failure. Каждый candidate остался отклоненным и не
подлежит публикации.

## Exact artifact

Build root:
`C:\BlueVPN_Builds\fusion_production_promotion_20260820_b4634_loopback_tuple_v1`.

| Компонент | Размер | SHA-256 |
|---|---:|---|
| `GreenVPN_Setup_0.4.6.exe` | `54026752` | `79CE8577E1ADBCD08977B471FF797C0A8527253ABC056D1F5301E4988B6C1D7F` |
| installed `greenvpn.exe` | `149504` | `5795C05514D9877A40326A38925B939253817764385EB6B5D7BBE001287A7165` |
| installed `app.so` | `7046064` | `B7B0939D27837FF6D5082F03EEA6CD3231C8C5CE5CC1058A6F46106573343551` |
| installed `greenvpn_service.exe` | `117760` | `EDCD34A2F4180B689B42F8BD2B8A29D36CBE5FDAF5870F31AD8520427E2586B2` |
| `GreenVpnProxyBridge.exe` | `204288` | `6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569` |
| process-router core | `231424` | `B4759403D1550594A6032DA4869C6666B234B88868ED19D8A1FD38372B7349CE` |

- Installed version: `0.4.6+4634`.
- Authenticode: `NotSigned`.
- Package audit: `success=true`, channel `production`, `66` payload entries,
  `0` errors.
- Candidate manifest: `fusionUiEnabled=true`,
  `fusionProductionPromotionCandidate=true`, `ownerApprovalRequired=true`,
  `productionPublished=false`.

## Build verification

- Две независимые MSVC-сборки process-router core дали одинаковые размер и
  SHA-256.
- Selective-routing policy regression прошел.
- `flutter analyze`: без замечаний.
- Flutter tests: `130` passed, `14` intentionally skipped.
- Focused Fusion tests в clean source прошли.
- Windows release gate: `0` warnings, `0` errors.

## Physical acceptance

Evidence root:
`C:\BlueVPN_Builds\fusion_production_windows_mode_smoke_20260820_b4634_loopback_tuple_v1`.

Главный отчет:
`windows-mode-reconcile-autonomous-summary.json`.

- Прогон начат `2026-08-20T10:28:28.6519199Z`, завершен
  `2026-08-20T10:32:23.4416340Z`; `success=true`, `failure=null`.
- Выполнен ровно один delayed detached runner с начальной задержкой `120`
  секунд, независимым deadman `900` секунд и `try/finally` recovery.
- Exact installer, version, payload hashes и paid owner session подтверждены.
- Foreground full connect: `21.474` wall seconds, `17.988` client-log seconds;
  один candidate, data-plane probe и privileged takeover подтверждены.
- Applications switch: `27.937` wall seconds, `25.590` client-log seconds;
  UI и runtime согласованы, process-router обязателен, запущен ровно один exact
  process и его PID совпадает с registry evidence.
- Direct unselected, explicit SOCKS5 и selected-executable fingerprints
  получены. Raw addresses в evidence не сохранялись.
- Selected fingerprint отличается от direct и совпадает с обязательным
  dedicated egress `5.129.216.42`; selected YouTube вернул HTTP `204`.
- Direct IPv6 в этом прогоне отсутствовал, поэтому условие IPv6 escape было
  неприменимо; утечка не обнаружена.
- Возврат в full: `14.020` wall seconds, `11.231` client-log seconds; egress
  fingerprint получен и совпал с исходным full VPN.

## Router evidence

- `windows-process-router.stdout.log`: `9962` bytes;
  `windows-process-router.stderr.log`: `0` bytes.
- TCP listeners были только `127.0.0.1:34010` и `[::1]:34010`; UDP relay был
  только `127.0.0.1/[::1]:34011`.
- Для обоих selected probes записана полная privacy-safe цепочка:
  `Redirect scheduled` -> `Redirect injected` -> `Redirect accepted` ->
  `Upstream ready; type=SOCKS5`.
- После успешных selected probes при завершении режима был один отдельный
  `Process attribution unavailable` marker. Он остался fail-closed, не
  использовался как доказательство успеха и не привел к direct fallback или
  утечке.

## Visual evidence

Визуально проверены четыре screenshot-файла размером `980x720`:

- `windows-mode-external-vpn.png`;
- `windows-mode-full.png`;
- `windows-mode-selected.png`;
- `windows-mode-returned-full.png`.

Full и returned-full явно показывают `Пауза`, `Сменить подключение`,
`Диагностика` и `Детали`. Public IP, protocol и route не раскрываются.
Selected state визуально однозначен, список выбранных приложений помещается без
перекрытий. Все четыре screenshot contracts имеют
`visualContractPassed=true`.

## Recovery и границы

Cleanup evidence подтверждает: Green UI/components и beta components
остановлены, process-router отсутствует, external Amnezia восстановлен,
metric `42739` и failsafes отсутствуют, scratch удален, исходное состояние не
изменено, deadman остановлен, exact install сохранен. Финальная проверка дала
Amnezia running, API HTTP `200` и YouTube HTTP `204`.

Никакой production deployment не выполнялся. Production release contract и
public manifests не менялись; candidate manifest остается локальным
`productionPublished=false`. Android, backend, серверные маршруты и Friendly
Linnet `5.129.237.163` не затрагивались.

## Оставшиеся owner gates

Техническая часть закрыта. Дальше только внешние решения, строго по очереди:

1. Принять Fusion UI и email-коммуникацию.
2. Выбрать Authenticode либо явно принять unsigned/SmartScreen риск.
3. Отдельно разрешить stable production publication.
