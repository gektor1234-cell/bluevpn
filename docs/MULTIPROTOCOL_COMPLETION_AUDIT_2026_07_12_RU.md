# Аудит завершённости multiprotocol-контура Green VPN

Дата: 2026-07-12.

## Решение

Контур технически готов за исключением одного обязательного физического gate: Android dnstt через публичную DNS-делегацию. До его прохождения цель не считается полностью завершённой и preview нельзя переносить в stable.

## Матрица доказательств

| Требование | Статус | Авторитетное доказательство |
|---|---|---|
| Stable WireGuard не изменён | Доказано | Production backend `0.9.105`; stable APK SHA-256 `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`; verifier не нашёл preview payload, manifest-компоненты или DEX-пакеты |
| Изоляция preview | Доказано | Отдельный package `pro.greenvpn.app.transportpreview`; paid-beta API path; все stable preview-флаги выключены |
| Порядок пяти транспортов | Доказано | Dart и native Kotlin policy tests: AWG2, Hysteria2, VLESS REALITY/XHTTP, Naive HTTPS, dnstt; WireGuard идёт только после preview-цепочки |
| Main UI failover/cooldown | Доказано | Candidate loop обрабатывает config/connect/handshake/YouTube failures; cooldown `1/3/10/30`; Flutter tests `11/11` |
| Quick Settings failover/cooldown | Доказано | Native tests `3/3`; физический Samsung: AWG2 первым, Hysteria2 после AWG2 cooldown; success marker только после YouTube probe |
| Timeweb/RUVDS control plane | Доказано | Оба работают на `r19`, backend `0.9.113-transport-preview.7`; Android contract probe `10/10`, по пять корректных конфигов через primary и fallback |
| AWG2 Android data plane | Доказано | NL2 egress, YouTube, lifecycle и восстановление состояния зафиксированы в `ANDROID_AWG2_PREVIEW_2026_07_11_RU.md` |
| Hysteria2 Android data plane | Доказано | NL2 egress, API/YouTube, watchdog и plaintext cleanup зафиксированы в `ANDROID_HYSTERIA2_PREVIEW_2026_07_12_RU.md` |
| VLESS Android data plane | Доказано | NL2 egress, API/YouTube, watchdog, reconnect и background/relaunch зафиксированы в `ANDROID_VLESS_REALITY_PREVIEW_2026_07_12_RU.md` |
| Naive Android data plane | Доказано | NL2 egress, API/YouTube, watchdog, reconnect, background и plaintext cleanup зафиксированы в `NAIVE_HTTPS_NL2_CANARY_2026_07_12_RU.md` |
| dnstt server data plane | Доказано | NL2 readiness: `server_data_plane_ready=true`, YouTube и egress прошли, stable transports active, `secrets_printed=false` |
| dnstt Android config contract | Доказано | Primary/fallback оба выдали корректный dnstt профиль внутри общего отчёта `10/10` |
| dnstt Android public DoH data plane | Не доказано | `tns.greenvpn.pro` и `t.greenvpn.pro` пока NXDOMAIN; без A/NS delegation физический тест намеренно fail-closed |
| Monitoring | Доказано в границах preview | Probe timers Timeweb/RUVDS активны; последние runs `success`, status `0`, observations `posted=true`; неподтверждённые control-plane сигналы не могут продвинуть транспорт |
| Release gate | Доказано | Backend `28/28` и `33/33`; Flutter `11/11`; native Kotlin `3/3`; release gate `0 warnings`, `0 errors`; APK verifier и signature pass |
| Восстановительный checkpoint | Доказано | Git bundle с полной историей, APK, безопасные отчёты, docs, rollback paths и SHA-256 manifest находятся в `C:\Users\gekto\GreenVPN_Checkpoints\five_stage_transport_preview_20260712` |

## Единственный оставшийся сценарий

1. Сохранить в REG.RU `A tns.greenvpn.pro -> 5.129.216.42`.
2. Сохранить `NS t.greenvpn.pro -> tns.greenvpn.pro`.
3. Дождаться публичного ответа Cloudflare/Google DNS.
4. Запустить NL2 readiness с `--require-delegation`.
5. Запустить `test_android_dnstt_preview_physical.ps1`.
6. Подтвердить Android NL2 egress, production и оба paid-beta API, YouTube, watchdog fail-closed cleanup, reconnect и отсутствие plaintext profile.
7. Обновить checkpoint и только после этого отметить цель выполненной.

YooKassa recurring-payment review является отдельным внешним launch gate и не подменяет multiprotocol-аудит.
