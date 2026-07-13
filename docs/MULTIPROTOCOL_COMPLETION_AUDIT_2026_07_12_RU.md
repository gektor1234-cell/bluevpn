# Аудит завершённости multiprotocol-контура Green VPN

Дата: 2026-07-12.

## Решение

Тестовый multiprotocol-контур технически завершён: публичная DNS-делегация dnstt, server readiness и физический Android data-plane gate пройдены. Все transport остаются preview-only; этот аудит не является разрешением переносить их в stable.

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
| dnstt Android public DoH data plane | Доказано | Cloudflare возвращает оба NS и SOA; readiness: `doh_delegation_ready=true`; Samsung: NL2 egress, production/оба paid-beta API, YouTube, watchdog, reconnect и cleanup; report SHA-256 `1D4B1F8A3350CA3CD6FA0DA25A1967A3AFE265A3586E2DD7A9EA3A4A9D9562C4` |
| Monitoring | Доказано в границах preview | Probe timers Timeweb/RUVDS активны; последние runs `success`, status `0`, observations `posted=true`; неподтверждённые control-plane сигналы не могут продвинуть транспорт |
| Release gate | Доказано | Backend `28/28` и `33/33`; Flutter `11/11`; native Kotlin `3/3`; release gate `0 warnings`, `0 errors`; APK verifier и signature pass |
| Восстановительный checkpoint | Доказано | Git bundle с полной историей, APK, безопасные отчёты, docs, rollback paths и SHA-256 manifest находятся в `C:\Users\gekto\GreenVPN_Checkpoints\five_stage_transport_preview_20260712` |

## Итог

Обязательные multiprotocol gates закрыты. Следующее добавление сервера выполняется по `SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md`: новый паспорт, guarded canary, оба control plane, физический data-plane proof, release gate и отдельный checkpoint. На другие серверы в рамках этого этапа ничего не развёрнуто.

YooKassa recurring-payment review является отдельным внешним launch gate и не подменяет multiprotocol-аудит.
