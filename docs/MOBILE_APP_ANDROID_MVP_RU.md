# Green VPN Android MVP

## Обновление 2026-05-24 08:42 MSK

- Актуальный live APK `0.2.8` / `2026052401` опубликован на `https://greenvpn.pro/downloads/GreenVPN_Android.apk`; размер `61,342,829` bytes; SHA256 `2AC8AEE9BB47C5EB9572155BA43E534C775EF4FD70A7FCE5DB5492D563D6B467`.
- Эта основная публичная сборка trial-only: без Yandex Ads SDK, без рекламного gate, без платёжных экранов. Trial остаётся основным пользовательским режимом.
- В APK есть Android Quick Settings tile Green VPN: плитку можно добавить в шторку Android; подключение через плитку работает при активном Trial/session, отключение доступно всегда.
- Проверено: build script `build_android_apk.ps1 -Mode release` прошёл analyze/test/build/signature, `aapt` подтвердил package `pro.greenvpn.app`, `versionName=0.2.8`, `versionCode=2026052401`, `GreenVpnQuickTileService` в manifest; live HTTPS download-back hash совпал.

## Обновление 2026-05-16 19:12 MSK

- Актуальный live APK `0.2.4` / `20260516` после clean rebuild опубликован на `https://greenvpn.pro/downloads/GreenVPN_Android.apk`; размер `61,736,549` bytes; SHA256 `9D0EDDCDD2BE7272A8951E8D5D46FA51E6F99468BC752B06AA181577B100388B`.
- Предыдущий APK с SHA256 `306D00AC59C4573ECBEEC7A431AB6318449647F38AA401BC057ABEA072C3C707` был заменен, потому что на emulator smoke проявил stale auth UI со старой телефонной вкладкой.
- Verification: `apksigner verify` OK, public download metadata `pro.greenvpn.app` / `0.2.4` / `20260516` / `Green VPN`, emulator smoke видит только `Email-код` и `Пароль`, Android VPN E2E прошел registration/connect/disconnect/cleanup.

Последнее обновление: 2026-05-16

## Статус

Android-версия Green VPN подготовлена как MVP в исходниках и локально собирается в APK. Это ещё не Google Play сборка и не production-релиз для массовой рекламы.

Что уже сделано:

- Обновление 2026-05-16: актуальный live APK `0.2.4` / `20260516` опубликован на `https://greenvpn.pro/downloads/GreenVPN_Android.apk`; размер `61,736,549` bytes; SHA256 `9D0EDDCDD2BE7272A8951E8D5D46FA51E6F99468BC752B06AA181577B100388B`. APK clean-rebuilt после перехода public auth на `Email-код` + `Пароль`, SMS-вкладка на входе убрана, поле одноразового кода ограничено 4 цифрами. Актуальные локальные копии: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.4_20260516.apk`, `C:\BlueVPN_Builds\GreenVPN_Android_LATEST.apk`, `public_demo_site\downloads\GreenVPN_Android.apk`.
- Обновление 2026-05-15: актуальный live APK `0.2.3` / `20260515` опубликован на `https://greenvpn.pro/downloads/GreenVPN_Android.apk`; размер `61,736,597` bytes; SHA256 `33914EB0AAD86864D8C014FBC544828E4F22F6263C190C07AD0500A2537CD6EF`. APK собран из свежего общего Flutter UI без вкладки `Задания`, с тёмной тарифной карточкой и настройками карты/автопродления. Актуальные локальные копии: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.3_20260515.apk`, `C:\BlueVPN_Builds\GreenVPN_Android_LATEST.apk`, `public_demo_site\downloads\GreenVPN_Android.apk`.
- 2026-05-15 владелец подтвердил реальную проверку свежего APK `0.2.3/20260515` на Android-телефоне: Android-версия работает.
- Flutter-клиент теперь определяет платформу как `android` и отправляет её в backend при bootstrap/login.
- Android package/application id: `pro.greenvpn.app`.
- Видимое имя приложения на Android/iOS: `Green VPN`.
- Android launcher icon собран из существующего проектного `windows\runner\resources\app_icon.ico`, без новой AI/тестовой картинки.
- Добавлен нативный Android bridge `green_vpn/android_vpn`.
- Android bridge использует системный `android.net.VpnService` и официальный WireGuard backend `com.wireguard.android:tunnel:1.0.20260102`.
- Android умеет запросить системное VPN-разрешение, принять WireGuard config от backend, подключить/отключить tunnel и вернуть статус в Flutter.
- Android хранит полученный WireGuard config через нативный bridge в Android Keystore + AES/GCM, а не только в памяти процесса.
- Локально установлен Android SDK Command-line Tools, принят набор Android licenses, Flutter настроен на SDK/JDK.
- Ранее были собраны APK `0.2.2/20260513`:
  - debug: `C:\Users\gekto\projects\bluevpn\build\app\outputs\flutter-apk\app-debug.apk`, SHA256 `54B2DE8BEA0A532A6AC0949AF30A19234511E075575EB248C36CE57E8EE5386B`;
  - release для тестов: `C:\Users\gekto\projects\bluevpn\build\app\outputs\flutter-apk\app-release.apk`, SHA256 `40413E778E2EADA97E5E882F9053AE26D543DDC11C86F74FF316FE2616396769`.
  - старые удобные копии для ручного теста: `C:\BlueVPN_Builds\GreenVPN_Android_0.2.2_20260513.apk`; SHA256 `40413E778E2EADA97E5E882F9053AE26D543DDC11C86F74FF316FE2616396769`.
- `app-release.apk` подписан локальным Green VPN upload key, а не debug-ключом Gradle. Keystore и `android\key.properties` лежат локально, игнорируются git и не содержатся в repo/docs/chat. Для Google Play всё равно нужно решение владельца по публикации и хранению upload key.
- Локально создан Android Emulator AVD `GreenVPN_API36` на Android 36 Google APIs x86_64; WHPX acceleration проверен как usable.
- Добавлен повторяемый smoke script `scripts\windows\run_android_emulator_smoke.ps1`. Он запускает/использует AVD, ставит APK, открывает Green VPN, проверяет фокус окна, UI dump, screenshot и отсутствие fatal crash в logcat.
- Добавлен повторяемый E2E script `scripts\windows\run_android_vpn_e2e.ps1`. Он ставит APK, при смене подписи безопасно переустанавливает package, создаёт временного smoke-пользователя, получает backend config, поднимает Android VPN, проверяет `tun0`, отключает VPN и удаляет smoke-пользователя с backend.
- Эмуляторный smoke пройден: `pro.greenvpn.app` установлен, `MainActivity` открыта, экран входа показывает `Green VPN`, `Телефон`, `Email-код`, `Пароль`; сеть эмулятора достучалась до `api.greenvpn.pro`.
- Эмуляторный smoke 2026-05-15 на опубликованном APK `0.2.3/20260515` также пройден.
- Полный Android E2E на эмуляторе пройден на release APK: регистрация тестового аккаунта, выдача WireGuard config, системное VPN-разрешение Android, `VPN CONNECTED` через `tun0`, отключение, отсутствие fatal crash в logcat, cleanup тестового пользователя. После теста `android-smoke-%@example.invalid` в live DB = `0`, VPN на эмуляторе выключен.
- Windows-логика `C:\ProgramData\BlueVPN`, `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1` сохранена и не переименована.
- iOS пока только подготовлен по бренду. Реальный VPN на iOS требует Apple Developer, Network Extension entitlement и отдельную нативную реализацию.

## Локальная сборка APK

Сборка на текущем компьютере теперь подготовлена. Основная команда:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build_android_apk.ps1 -Mode both
```

Скрипт:

- выставляет `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `JAVA_HOME`;
- временно отключает desktop targets только на время `flutter pub get`, потому что Windows Developer Mode/symlink support выключен;
- возвращает desktop targets обратно;
- запускает анализ, тесты, сборку APK и `apksigner verify`;
- печатает путь, размер и SHA256 APK.

## Эмуляторный smoke

Поднять Android-эмулятор, установить тестовый APK и проверить первый экран можно одной командой:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\run_android_emulator_smoke.ps1
```

Скрипт использует AVD `GreenVPN_API36`, APK `build\app\outputs\flutter-apk\app-release.apk`, package `pro.greenvpn.app` и сохраняет артефакты:

- `C:\Users\gekto\projects\bluevpn\build\android_emulator_greenvpn_screen.png`;
- `C:\Users\gekto\projects\bluevpn\build\android_emulator_window.xml`.

Это smoke первого запуска. Полный end-to-end VPN-тест на эмуляторе теперь запускается отдельной командой:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\run_android_vpn_e2e.ps1 -InstallApk
```

Этот E2E создаёт только временного smoke-пользователя `android-smoke-*` и в конце удаляет его. На физическом Android-устройстве всё ещё нужен отдельный ручной тест владельца.

Ручные команды, если скрипт не нужен:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\openjdk\jdk-21.0.8'
$env:ANDROID_HOME="$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
flutter pub get
flutter build apk --debug
flutter build apk --release
```

## Проверки, которые уже прошли

```powershell
flutter doctor -v
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
apksigner verify --verbose build\app\outputs\flutter-apk\app-debug.apk
apksigner verify --verbose build\app\outputs\flutter-apk\app-release.apk
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\run_android_emulator_smoke.ps1 -ApkPath build\app\outputs\flutter-apk\app-release.apk
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\run_android_vpn_e2e.ps1 -InstallApk
```

Обычный `flutter analyze` в проекте по-прежнему показывает старые info-level legacy замечания, но без warning/error.

## Первый Android smoke после сборки

1. Собрать debug APK.
2. Установить на Android-устройство.
3. Войти через email/телефон/пароль.
4. Дождаться получения backend config.
5. Нажать подключение.
6. Подтвердить системное VPN-разрешение Android.
7. Проверить, что статус стал подключённым.
8. Проверить интернет через VPN.
9. Отключить VPN.
10. Закрыть и открыть приложение снова.

## Ограничения MVP

- APK `0.2.3/20260515` владелец проверил на физическом Android-устройстве; свежий APK `0.2.4/20260516` с 4-значными кодами ещё нужно вручную проверить на телефоне.
- Нет публикации в Google Play / RuStore.
- Нет финального Android app icon/adaptive icon.
- Нет Android foreground notification polish.
- Нет iOS VPN реализации.
- Новый APK `0.2.4/20260516` опубликован на сайт, но не опубликован в Google Play / RuStore.
 
## 2026-05-12 Email-код на Android

- На эмуляторе Android экран входа Green VPN открылся корректно, но вкладка `Email-код` показывала: `Email сейчас недоступен. Попробуй позже или войди по паролю.`
- Причина была не в APK и не в эмуляторе: live backend принимал challenge, но SMTP-отправка возвращала `deliveryStatus=failed`.
- На origin `37.220.85.211` в server-only env был пере применён SMTP app password для `no-reply@greenvpn.pro`; невидимый BOM-символ из локального файла пароля удалён перед записью.
- Backend `bluevpn-backend` перезапущен; `/healthz` остался зелёным.
- Live smoke `POST /api/v1/auth/challenge/start` для email-кода после исправления вернул `deliveryStatus=sent`.
- Android APK пересобирать для этого исправления не нужно: приложение использует тот же API и после cooldown снова сможет запросить код.

## 2026-05-13 Android release signing и полный E2E

- Добавлен `scripts\windows\create_android_release_keystore.ps1`.
- Скрипт создаёт локальный Android upload keystore и `android\key.properties`; оба файла уже игнорируются git. Пароли не печатаются и не документируются.
- `android\app\build.gradle.kts` теперь использует release signing config из `android\key.properties`, если файл существует. Если его нет, dev-сборка не ломается и временно падает обратно на debug signing.
- Локально создан Green VPN upload key в PKCS12 keystore.
- Release APK пересобран и подписан этим ключом:
  - path: `C:\Users\gekto\projects\bluevpn\build\app\outputs\flutter-apk\app-release.apk`;
  - versionName/versionCode: `0.2.2` / `20260513`;
  - SHA256: `40413E778E2EADA97E5E882F9053AE26D543DDC11C86F74FF316FE2616396769`;
  - signer DN: `CN=Green VPN, OU=Green VPN, O=Green VPN, L=Moscow, ST=Moscow, C=RU`.
- `scripts\windows\run_android_vpn_e2e.ps1` исправлен:
  - русские UI labels строятся через Unicode codepoints, чтобы PowerShell 5 не ломал кодировку;
  - приложение запускается напрямую через `am start -n pro.greenvpn.app/.MainActivity`, без случайного ухода в Google Messages;
  - `adb install` теперь проверяет exit-code и при `INSTALL_FAILED_UPDATE_INCOMPATIBLE` делает clean reinstall.
- Полный E2E на эмуляторе прошёл уже после release signing:
  - APK установлен;
  - тестовый пользователь создан;
  - config получен;
  - Android VPN подключился через `tun0`;
  - VPN отключился;
  - smoke user cleanup выполнен;
  - `android_smoke_users 0`;
  - `ANDROID_VPN_DISCONNECTED_OK`;
  - `ANDROID_LOGCAT_FATAL_OK`.
