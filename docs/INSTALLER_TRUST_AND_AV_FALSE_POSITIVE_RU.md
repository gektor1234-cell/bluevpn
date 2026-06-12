# Installer trust и ложное срабатывание AV

Дата: 2026-05-10

## Что произошло

Текущий публичный файл `GreenVPN_Setup.exe` был заблокирован Microsoft Defender как `Trojan:Win32/Wacatac.B!ml`.

`!ml` означает machine-learning/эвристическую классификацию. Это не доказывает, что в файле есть известный вирус, но для пользователя результат такой же: Windows и браузеры могут заблокировать скачивание или запуск.

## Что уже сделано

- Публичная загрузка старого flagged `https://greenvpn.pro/downloads/GreenVPN_Setup.exe` была временно закрыта.
- Старый файл сохранен на сервере `72.56.32.197` в закрытом карантине: `/root/greenvpn-quarantine/GreenVPN_Setup_DefenderWacatacML_20260509.exe`.
- 2026-05-09 по прямой просьбе владельца собрана и опубликована новая unsigned hardened-сборка:
  - public URL: `https://greenvpn.pro/downloads/GreenVPN_Setup_HiddenInstaller_20260509.exe`;
  - compatibility URL: `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`;
  - SHA256: `5A25D68A2CAFC1D68719D552C51FCD997E733ED48D6B22C46CD5CE8027E0C9CE`;
  - локальный release gate passed;
  - локальный Microsoft Defender scan: `found no threats`;
  - public download hash matches local artifact.
- После проверки на машине владельца обнаружен системный `LocalMachine AllSigned`, из-за которого предыдущий unsigned installer мог молча закрываться при запуске внутренних `.ps1`. Текущая опубликованная сборка использует `-ExecutionPolicy RemoteSigned` вместо пустого режима/`Bypass`; это не заменяет Code Signing, но устраняет локальный no-op на такой политике.
- После проверки повторного запуска добавлен single-instance guard в Windows runner: второй foreground-запуск поднимает уже открытое окно `Green VPN`, а `--background`/`--tray` дубль тихо выходит. Это предотвращает два окна/две UI-сессии одного клиента.
- После проверки UX установки убран видимый elevated PowerShell: bootstrap, UAC-релонч, cleanup и repair запускают PowerShell в скрытом режиме, а пользователь должен видеть только UAC и branded-окно `Green VPN Installer`.
- Сайт `https://greenvpn.pro/` снова показывает кнопку скачивания, но это временный unsigned build, а не финальный trusted Windows release.
- Из следующего installer pipeline убраны самые подозрительные признаки:
  - `install.vbs`;
  - `wscript.exe`;
  - install-time `Register-ScheduledTask`;
  - runtime `schtasks.exe` в клиенте/tray;
  - installer/runtime `-ExecutionPolicy Bypass`;
  - видимое PowerShell/CMD-окно во время установки.
- Tray connect/disconnect теперь обращается к локальному `GreenVPNService` по `127.0.0.1:48737`, а не запускает scheduled tasks.
- Release gate теперь проверяет отсутствие этих подозрительных installer/client паттернов.
- Добавлен и усилен скрипт подписи/проверки артефактов: `scripts/windows/sign_release_artifacts.ps1`.
  - умеет подписывать release-папку, отдельный installer/MSI/EXE и DLL;
  - проверяет Authenticode, SHA256, ожидаемого издателя, обязательные имена артефактов и timestamp;
  - умеет писать JSON-отчёт через `-ReportPath`;
  - умеет `-VerifyOnly -SkipSignToolVerify`, чтобы до покупки сертификата/Windows SDK проверить текущий статус через `Get-AuthenticodeSignature`;
  - release gate теперь проверяет наличие этого tooling и PowerShell syntax.

## Как это делают нормальные VPN

- Code signing: подписывают installer/MSI/EXE, основной клиент, service executable и DLL. Статус Green VPN: не сделано; нужен OV Code Signing certificate или Microsoft Trusted Signing.
- Publisher trust: Windows должен показывать проверенного издателя Green VPN, а не `Unknown Publisher`. Статус Green VPN: не сделано.
- Отдельный сертификат для подписи кода: SSL/HTTPS сертификаты сайта не подходят для подписи `.exe`. Статус Green VPN: правило зафиксировано, SSL на REG.RU для этой задачи не покупать.
- Закрытое хранение ключа: приватный ключ подписи хранится в HSM/cloud signing/token, не в репозитории, не в чате и не в обычном файле. Статус Green VPN: правило зафиксировано.
- Чистый installer pipeline: MSI/WiX/NSIS/MSIX или другой нормальный подписанный installer без VBS, `wscript.exe`, PowerShell bootstrap, `ExecutionPolicy Bypass`, install-time scheduled tasks и runtime `schtasks.exe`. Статус Green VPN: частично сделано; самые подозрительные паттерны убраны, видимое PowerShell-окно скрыто, но переход на MSI/WiX остается желательным hardening шагом.
- Доверенный сетевой слой: не ставить собственные неподписанные драйверы; использовать WireGuard как проверенный компонент и не трогать чужие VPN. Статус Green VPN: сделано для текущего MVP.
- Репутация SmartScreen/Defender: после подписи новый издатель/хэш постепенно набирает репутацию; OV убирает `Unknown Publisher`, но не гарантирует мгновенное молчание SmartScreen. Статус Green VPN: не сделано, начнется после подписанного build.
- False positive workflow: если Microsoft Defender/Yandex Browser ошибочно блокируют файл, отправлять подписанный файл/URL на проверку, а не просить пользователя отключать защиту. Статус Green VPN: не сделано для нового build.

## Что еще обязательно нужно

1. Получить нормальную подпись издателя Green VPN.
   - Подойдет OV/EV code signing certificate или Microsoft Artifact Signing/Trusted Signing, если аккаунт и валидация доступны.
   - Важно: по актуальной документации Microsoft EV больше не дает автоматический обход SmartScreen; репутация все равно набирается по подписанному издателю/хэшу.
2. Установить сертификат в Windows Certificate Store на build-машине, подключить провайдерский токен или настроить cloud signing.
3. Подписывать все Windows-артефакты:
   - `greenvpn.exe`;
   - `greenvpn_service.exe`;
   - DLL/EXE в release-папке;
   - финальный installer/MSI/EXE.
4. После подписи прогонять:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\sign_release_artifacts.ps1 -CertificateThumbprint <CERT_SHA1_THUMBPRINT> -Path .\build\windows\x64\runner\Release
```

   Для промежуточной проверки без реальной подписи и без Windows SDK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\sign_release_artifacts.ps1 -VerifyOnly -AllowUnsignedInVerifyOnly -SkipSignToolVerify -Path .\build\windows\x64\runner\Release -ReportPath C:\BlueVPN_Builds\signing_report.json
```

   Для финального installer после сборки:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\sign_release_artifacts.ps1 -CertificateThumbprint <CERT_SHA1_THUMBPRINT> -Path C:\BlueVPN_Builds\GreenVPN_Setup.exe -RequiredLeafName GreenVPN_Setup.exe -ReportPath C:\BlueVPN_Builds\GreenVPN_Setup_signing_report.json
```

5. Перед локальным install/test обязательно чистить только Green VPN:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\greenvpn_clean_previous_install.ps1
```

6. Отправить ложное срабатывание:
   - Microsoft Security Intelligence file submission: `https://www.microsoft.com/security/portal/submit.aspx/`
   - Yandex Browser/Protect support: `https://browser.yandex.ru/help/security/file-checking`; через поддержку Яндекс Браузера приложить файл/URL/детали блокировки.

## Что не делать

- Не публиковать старый flagged `GreenVPN_Setup.exe` обратно.
- Не просить пользователей отключать Defender/браузерную защиту.
- Не считать текущий unsigned build финальным trusted release: для рекламы на холодную аудиторию всё равно нужен Code Signing и reputation/false-positive workflow.
- Не трогать WireGuard как приложение, Amnezia, WARP, Friendly Linnet или другие VPN при cleanup.
