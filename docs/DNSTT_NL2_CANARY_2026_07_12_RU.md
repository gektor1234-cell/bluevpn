# dnstt NL2 canary: checkpoint 2026-07-12

## Назначение

`dnstt` добавлен только как последний аварийный транспорт тестового контура Green VPN. Он не опубликован в основном каталоге, не включён в stable-сборку и не меняет существующий WireGuard.

Целевая preview-цепочка:

1. AmneziaWG2.
2. Hysteria2.
3. VLESS REALITY/XHTTP через TCP/443.
4. Naive HTTPS.
5. dnstt через публичный DoH.

## Серверный canary

- Узел: NL2, `5.129.216.42`.
- DNS-зона туннеля: `t.greenvpn.pro`.
- Авторитетный сервер: `tns.greenvpn.pro`.
- Публичный listener: только `5.129.216.42:53/udp`.
- Внутренний SOCKS: только `127.0.0.1:1083/tcp`, с аутентификацией.
- Сервисы: `greenvpn-dnstt-canary.service` и `greenvpn-dnstt-socks-canary.service`.
- Клиентский профиль: `/etc/greenvpn-transport/dnstt-canary.client.json`, `root:root`, mode `0600`.
- Private key и SOCKS auth не выводятся readiness-скриптом и не находятся в Git.

Bootstrap, readiness и rollback:

```text
scripts/server/bootstrap_dnstt_canary.sh
scripts/server/check_dnstt_canary_readiness.sh
scripts/server/remove_dnstt_canary.sh
```

Каждый изменяющий скрипт привязан к точному IP NL2. Bootstrap и rollback по умолчанию работают как dry-run. Bootstrap не меняет DNS регистратора, системный DNS, публичный каталог, базы данных или существующие транспорты.

## Требуемая делегация DNS

В зоне `greenvpn.pro` нужны ровно две записи:

```text
A   tns.greenvpn.pro  -> 5.129.216.42
NS  t.greenvpn.pro    -> tns.greenvpn.pro
```

До появления обеих записей у публичных резолверов физический DoH-тест считается незавершённым. Readiness с `--require-delegation` обязан завершиться ошибкой, если делегация отсутствует.

## Закреплённый upstream

- dnstt release: `20260501`.
- Source commit: `0c5c52a57d899c05428c116898941761a2ed83c2`.
- Архив SHA-256: `A7B21D3D787570D9127643E360E150D2DA7B33AA8039D0546A04DCFE8EE1864F`.
- Подпись архива проверена ключом David Fifield, fingerprint `AD1AB35C674DF572FBCE8B0A6BC758CBC11F6276`.
- Linux server SHA-256: `CF3E6A3091752B72E94E360EAAD76E3CB14B69923AF691E6477AA3F33E740895`.
- Linux client SHA-256: `366E30297CAF3289D9C03BF0A3C8F4522E8972FA7DDD3D289D7887AD01DAF8FE`.
- Android arm64 client SHA-256: `AAE616C0888DB31A61555CA4FE91B578E2A6734B7CEF7497B6FE30FFCDA1FDC5`.
- Windows amd64 client SHA-256: `282995EA68FD13514AC033BC953193AD11CF01F83BB6E3F97929089E5BD85A99`.
- Лицензия upstream: public domain; текст `COPYING` включён в APK.

## Android preview

- Отдельный package: `pro.greenvpn.app.transportpreview`.
- Feature flag: `GREENVPN_DNSTT_PREVIEW_ENABLED=true` только при явной preview-сборке.
- Resolver order: Cloudflare DoH, Google DoH, затем Cloudflare DoT.
- Локальный dnstt listener: `127.0.0.1:1983`.
- TUN/HEV: IPv4 full tunnel, mapdns, DNS и UDP приложений проходят через TCP-only SOCKS.
- Self-loop исключён через `addDisallowedApplication(packageName)`.
- Watchdog закрывает VPN fail-closed при остановке дочернего процесса.
- Runtime profile удаляется при disconnect и после теста.

Текущий пятиступенчатый preview APK:

```text
C:\BlueVPN_Builds\android_transport_preview_20260712_cascade_r19\GreenVPN_Android_five_stage_preview_0.2.45_2026071204.apk
size=140139681
sha256=984CBEF0EB4C0A88A4D982AC63C1A1DFB3F597CF785F51D639E6DEE05C1FEFD1
```

`verify_android_dnstt_preview_apk.ps1` проверил package, versionCode, закреплённый бинарник, license asset, manifest, DEX, BuildConfig, zipalign и APK signature.

Debug-only контрактный пробник на физическом Samsung получил корректные конфиги всех пяти транспортов через оба paid-beta control plane: `10/10`, HTTP `200`. Он не сохраняет токены, device ID или тела конфигов в отчёт.

## Stable isolation

Замороженный production APK прошёл `verify_android_stable_transport_isolation.ps1`:

```text
package=pro.greenvpn.app
size=65543311
sha256=308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F
```

Проверка запрещает payload, manifest-компоненты и DEX-пакеты Hysteria2, VLESS, Naive HTTPS и dnstt. Все пять preview-флагов, включая AWG2, должны быть `false`.

Общий `bluevpn_release_gate.ps1` после добавления dnstt: `0 warnings`, `0 errors`.

## Осталось до доказанного этапа

1. Добавить две DNS-записи у REG.RU.
2. Дождаться публичной делегации и пройти server readiness с `--require-delegation`.
3. Запустить `test_android_dnstt_preview_physical.ps1` на физическом телефоне.
4. Доказать NL2 egress, production/paid-beta API, YouTube, watchdog cleanup, reconnect и удаление plaintext profile.
5. dnstt уже включён последним только в отдельном preview selector, но до выполнения пунктов 1-4 не считается физически доказанным. Stable и production остаются без изменений.
