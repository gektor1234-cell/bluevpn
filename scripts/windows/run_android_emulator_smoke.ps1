param(
    [string]$AvdName = "GreenVPN_API36",
    [string]$PackageName = "pro.greenvpn.app",
    [string]$SystemImage = "system-images;android-36;google_apis;x86_64",
    [string]$DeviceProfile = "medium_phone",
    [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
    [ValidateSet("auto", "host", "software", "lavapipe", "swiftshader", "swangle")]
    [string]$GpuMode = "swiftshader",
    [switch]$ColdBoot,
    [switch]$WipeData,
    [switch]$NoWindow,
    [int]$BootTimeoutSeconds = 480
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$javaHome = "C:\Program Files\Android\openjdk\jdk-21.0.8"
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:JAVA_HOME = $javaHome
$env:Path = "$sdkRoot\platform-tools;$sdkRoot\emulator;$javaHome\bin;$env:Path"

$sdkManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
$avdManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\avdmanager.bat"
$emulator = Join-Path $sdkRoot "emulator\emulator.exe"
$adb = Join-Path $sdkRoot "platform-tools\adb.exe"

foreach ($tool in @($sdkManager, $avdManager, $emulator, $adb)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Android tool not found: $tool"
    }
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$buildDir = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$emulatorStdOut = Join-Path $buildDir "android_emulator_stdout.log"
$emulatorStdErr = Join-Path $buildDir "android_emulator_stderr.log"

$installed = (& $sdkManager --list_installed) -join "`n"
if ($installed -notmatch [regex]::Escape("emulator") -or $installed -notmatch [regex]::Escape($SystemImage)) {
    & $sdkManager "emulator" $SystemImage
}

$avds = (& $avdManager list avd) -join "`n"
if ($avds -notmatch "Name:\s+$([regex]::Escape($AvdName))\b") {
    "no" | & $avdManager create avd -n $AvdName -k $SystemImage -d $DeviceProfile --force
}

& $adb start-server | Out-Null
$deviceLine = (& $adb devices) | Where-Object { $_ -match "^emulator-\d+\s+device$" } | Select-Object -First 1
if ($deviceLine) {
    $serial = ($deviceLine -split "\s+")[0]
} else {
    Get-Process | Where-Object { $_.ProcessName -match "^(emulator|qemu-system-x86_64)$" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $avdDir = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
    if (Test-Path -LiteralPath $avdDir) {
        Get-ChildItem -LiteralPath $avdDir -Force -Filter "*.lock" -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    $emulatorArgs = @(
        "-avd", $AvdName,
        "-netdelay", "none",
        "-netspeed", "full",
        "-gpu", $GpuMode,
        "-no-snapshot-save",
        "-no-boot-anim"
    )
    if ($ColdBoot) {
        $emulatorArgs += "-no-snapshot-load"
    }
    if ($WipeData) {
        $emulatorArgs += "-wipe-data"
    }
    if ($NoWindow) {
        $emulatorArgs += "-no-window"
    }
    Start-Process -FilePath $emulator -ArgumentList $emulatorArgs -RedirectStandardOutput $emulatorStdOut -RedirectStandardError $emulatorStdErr -WindowStyle Hidden | Out-Null
    $serial = $null
}

$deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $deviceLine = (& $adb devices) | Where-Object { $_ -match "^emulator-\d+\s+device$" } | Select-Object -First 1
    if ($deviceLine) {
        $serial = ($deviceLine -split "\s+")[0]
        $bootCompleted = ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
        $bootAnim = ((& $adb -s $serial shell getprop init.svc.bootanim 2>$null) -join "").Trim()
        if ($bootCompleted -eq "1" -and ($bootAnim -eq "stopped" -or [string]::IsNullOrWhiteSpace($bootAnim))) {
            break
        }
    }
    Start-Sleep -Seconds 5
}

if (-not $serial) {
    $tail = ""
    if (Test-Path -LiteralPath $emulatorStdErr) {
        $tail = (Get-Content -LiteralPath $emulatorStdErr -Tail 80 -ErrorAction SilentlyContinue) -join "`n"
    }
    throw "No Android emulator device appeared before timeout. Emulator stderr tail:`n$tail"
}

$bootCompleted = ((& $adb -s $serial shell getprop sys.boot_completed) -join "").Trim()
if ($bootCompleted -ne "1") {
    throw "Android emulator did not finish booting before timeout. Serial: $serial"
}

& $adb -s $serial install -r $resolvedApk
& $adb -s $serial logcat -c | Out-Null
& $adb -s $serial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 4

$appPid = ((& $adb -s $serial shell pidof $PackageName 2>$null) -join "").Trim()
if ([string]::IsNullOrWhiteSpace($appPid)) {
    throw "Green VPN process is not running after launch."
}

$focus = ((& $adb -s $serial shell dumpsys window) | Select-String -Pattern "mCurrentFocus|mFocusedApp" | Select-Object -First 5) -join "`n"
if ($focus -notmatch [regex]::Escape($PackageName)) {
    throw "Green VPN is not focused after launch. Focus:`n$focus"
}

$screenPath = Join-Path $buildDir "android_emulator_greenvpn_screen.png"
$xmlPath = Join-Path $buildDir "android_emulator_window.xml"

& $adb -s $serial exec-out screencap -p > $screenPath
& $adb -s $serial shell uiautomator dump /sdcard/window.xml | Out-Null
& $adb -s $serial pull /sdcard/window.xml $xmlPath | Out-Null

$ui = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
$emailCodeLabel = "Email-" + (-join ([char[]]@(0x043A, 0x043E, 0x0434)))
$passwordLabel = -join ([char[]]@(0x041F, 0x0430, 0x0440, 0x043E, 0x043B, 0x044C))
foreach ($needle in @("Green VPN", $emailCodeLabel, "Tab 1 of 2", $passwordLabel, "Tab 2 of 2")) {
    if ($ui -notmatch [regex]::Escape($needle)) {
        throw "Expected UI text not found in emulator dump: $needle"
    }
}

$phoneLabel = -join ([char[]]@(0x0422, 0x0435, 0x043B, 0x0435, 0x0444, 0x043E, 0x043D))
if ($ui -match [regex]::Escape("${phoneLabel}&#10;Tab")) {
    throw "Unexpected legacy phone auth tab found in emulator dump."
}

$fatal = (& $adb -s $serial logcat -d -t 500) | Select-String -Pattern "FATAL EXCEPTION|\sE\s+AndroidRuntime" | Select-Object -First 1
if ($fatal) {
    throw "Android logcat contains a fatal crash marker: $fatal"
}

[pscustomobject]@{
    ok = $true
    serial = $serial
    package = $PackageName
    pid = $appPid
    apk = $resolvedApk
    screenshot = $screenPath
    uiDump = $xmlPath
}
