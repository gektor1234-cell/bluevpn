# Green VPN Fusion Windows: selected-app acceptance

Дата фиксации: 2026-08-20 MSK.

## Итог

Windows candidate `0.4.6+4635` технически принят по точному физическому
сценарию `full -> applications -> full`. Selected executable подтвердил
выход через dedicated VPN `5.129.216.42`, selected YouTube вернул HTTP `204`,
Diagnostics при работающем full tunnel визуально показал `Подключение: активно`,
а после прогона исходный Amnezia/API/YouTube baseline был восстановлен.

Предшественник `+4634` прошел routing acceptance, но после owner review был
superseded из-за отдельного Diagnostics false negative. Исправленный
clean-source successor `+4635` повторил полный routing smoke и закрыл этот
последний технический дефект.

Ни один candidate не опубликован. `productionPublished=false`; stable
production, Android, backend и Friendly Linnet `5.129.237.163` не менялись.

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

## Diagnostics successor `0.4.6+4635`

- Exact source commit:
  `fcd0c6e8a83742aa71e4aabf480cfa9df19321d3`.
- Screenshot harness commit: `c74061f` (pushed).
- Exact protected Amnezia recovery hardening: `2aac4b5` (pushed).
- Build root:
  `C:\BlueVPN_Builds\fusion_production_promotion_20260820_b4635_diagnostics_v1`.
- Root cause: Diagnostics выполнял прямой `wg.exe show` из обычного процесса;
  Windows возвращал `Permission denied`, пока authenticated local service
  одновременно подтверждал `tunnelState=running`, `wireGuardState=running` и
  `routingMode=full`.
- Fix использует authenticated GreenVPNService status как authoritative source,
  сохраняет direct `wg.exe` только как legacy fallback при недоступном service и
  отображает transitional/unavailable state как `проверяется` или
  `не удалось проверить`, а не как ложное `не активно`.

| Компонент | Размер | SHA-256 |
|---|---:|---|
| `GreenVPN_Setup_0.4.6.exe` | `54026240` | `0FBB24B4E79081A393D162130D593327B956D92453361A5944E89E661811ECB7` |
| packaged `greenvpn.exe` | `149504` | `E2DD276C55EDCC343D63EBC9925D0E9DC5A5B5708898D0D05D25488B1E1F2847` |
| packaged `app.so` | `7046064` | `D9F882BD003CA10682BDF6CD96EC6A05379228AD3ABD99D331131E3061BB0231` |
| packaged `greenvpn_service.exe` | `117760` | `4E0A63A0B2787CDEB3295F62B61AABAAEBC0F24A9A0B37FB10B4BE114E6B77DE` |
| `ProxyBridge_CLI.exe` | `204288` | `6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569` |
| `ProxyBridgeCore.dll` | `231424` | `B4759403D1550594A6032DA4869C6666B234B88868ED19D8A1FD38372B7349CE` |

- Authenticode: `NotSigned`.
- Package audit: `success=true`, channel `production`, `66` payload entries,
  `0` errors.
- Clean-source validation: `flutter analyze` без замечаний; `135` tests passed,
  `14` intentionally skipped; focused Fusion tests passed; Windows release gate
  `0` warnings, `0` errors.
- Manifest retains `ownerApprovalRequired=true` and
  `productionPublished=false`.
- Installed `+4634` remained running unchanged during build; no app, tunnel,
  route or service transition was performed during build/validation. The later
  physical acceptance safely installed and retained exact `+4635`.

## Build verification

- Две независимые MSVC-сборки process-router core дали одинаковые размер и
  SHA-256.
- Selective-routing policy regression прошел.
- `flutter analyze`: без замечаний.
- Clean-source Flutter tests для `+4635`: `135` passed, `14` intentionally
  skipped.
- Focused Fusion tests в clean source прошли.
- Windows release gate: `0` warnings, `0` errors.

## Physical acceptance

Evidence root:
`C:\BlueVPN_Builds\fusion_production_windows_mode_smoke_20260820_b4635_diagnostics_v1`.

Главный отчет:
`windows-mode-reconcile-autonomous-summary.json`.

- Прогон начат `2026-08-20T11:49:02.1272590Z`, завершен
  `2026-08-20T11:54:14.1063663Z`; `success=true`, `failure=null`.
- Выполнен ровно один delayed detached runner с начальной задержкой `180`
  секунд, независимым deadman `900` секунд и `try/finally` recovery.
- Initial state содержал работающий Green `+4634` и отсутствующий внешний
  tunnel service. До acceptance runner восстановил exact
  `AmneziaWGTunnel$maxim_pc_full` из защищенного `.conf.dpapi`; delayed baseline
  подтвердил Amnezia/API `200`/YouTube `204`, отсутствие metric `42739` и
  failsafes.
- Exact installer, version, payload hashes и paid owner session подтверждены.
- Foreground full connect: `8.603` wall seconds, `5.982` client-log seconds;
  один candidate, data-plane probe и privileged takeover подтверждены.
- Applications switch: `31.638` wall seconds, `29.584` client-log seconds;
  UI и runtime согласованы, process-router обязателен, запущен ровно один exact
  process и его PID совпадает с registry evidence.
- Direct unselected, explicit SOCKS5 и selected-executable fingerprints
  получены. Raw addresses в evidence не сохранялись.
- Selected fingerprint отличается от direct и совпадает с обязательным
  dedicated egress `5.129.216.42`; selected YouTube вернул HTTP `204`.
- Direct IPv6 в этом прогоне отсутствовал, поэтому условие IPv6 escape было
  неприменимо; утечка не обнаружена.
- Возврат в full: `13.142` wall seconds, `10.251` client-log seconds; egress
  fingerprint получен и совпал с исходным full VPN.
- Main summary: `51385` bytes, SHA-256
  `79DA9B6BFA9386041180832D3114953FB4D6938DFD34E55A503CE065AE2448F6`.
- Diagnostics screenshot: `54404` bytes, SHA-256
  `A03C507310CDE0494D1E3E567EF633848C907A1E42E1247BCA2FFA012D0FADDA`.

## Router evidence

- `windows-process-router.stdout.log`: `9888` bytes;
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

Визуально проверены пять screenshot-файлов размером `980x720`:

- `windows-mode-external-vpn.png`;
- `windows-mode-full.png`;
- `windows-mode-full-diagnostics.png`;
- `windows-mode-selected.png`;
- `windows-mode-returned-full.png`.

Full и returned-full явно показывают `Пауза`, `Сменить подключение`,
`Диагностика` и `Детали`. Public IP, protocol и route не раскрываются.
Diagnostics явно показывает зеленую строку `Подключение` со значением `активно`,
а не `не активно`, `проверяется` или loading state.
Selected state визуально однозначен, список выбранных приложений помещается без
перекрытий. Все пять screenshot contracts имеют
`visualContractPassed=true`.

## Recovery и границы

Cleanup evidence подтверждает: Green UI/components и beta components
остановлены, process-router отсутствует, external Amnezia восстановлен,
metric `42739` и failsafes отсутствуют, scratch удален, исходное состояние не
изменено, deadman остановлен, exact install сохранен. Финальная проверка дала
Amnezia running, API HTTP `200` и YouTube HTTP `204`.

Независимая read-only post-run проверка повторно подтвердила exact installed
payload hashes `+4635`, running `AmneziaWGTunnel$maxim_pc_full`, отсутствие
managed `BlueVPNDev1`, standby probe, metric `42739` и трех smoke failsafes,
API HTTP `200` и YouTube HTTP `204`.

Никакой production deployment не выполнялся. Production release contract и
public manifests не менялись; candidate manifest остается локальным
`productionPublished=false`. Android, backend, серверные маршруты и Friendly
Linnet `5.129.237.163` не затрагивались.

## Owner gates и оставшаяся проверка

1. Fusion UI/email acceptance: принят. Владелец принял остальной UI и решил не
   делать отдельный live email-вход; automated auth/recovery tests прошли, а
   целевая проверка исправленного Diagnostics на exact `+4635` завершилась
   успешно.
2. Authenticode/unsigned SmartScreen: владелец решил пока пропустить. Gate не
   принят и остается блокирующим.
3. Stable production publication: не запрашивалась и не разрешена; из-за
   последовательности gates публикация остается заблокированной.

Техническая Windows Fusion acceptance завершена. Остались только явно
отложенный Authenticode/unsigned SmartScreen gate и отдельное stable-production
approval; production publication по-прежнему запрещена.
