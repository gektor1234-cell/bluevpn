param(
    [string]$PackageName = "pro.greenvpn.app",
    [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
    [Alias("ServerHost")]
    [string]$ControlPlaneHost = "",
    [string]$SmokeEmailPrefix = "android-smoke",
    [string]$SmokeEmailDomain = "example.invalid",
    [string]$SmokePassword = "Smoke123456a",
    [switch]$InstallApk,
    [switch]$EnableServerCleanup,
    [switch]$SkipServerCleanup
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$adb = Join-Path $sdkRoot "platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb.exe not found: $adb"
}

$buildDir = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $adb @Args
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed with exit code ${LASTEXITCODE}: $($Args -join ' ')"
    }
}

function Install-AndroidApk {
    param(
        [string]$Serial,
        [string]$PackageName,
        [string]$Apk
    )
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $adb -s $Serial install -r $Apk 2>&1
        $exit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($exit -ne 0 -and (($output -join "`n") -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE")) {
        Write-Host "Existing Android package has a different signature; reinstalling cleanly for E2E."
        & $adb -s $Serial uninstall $PackageName | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "adb uninstall failed for $PackageName"
        }
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & $adb -s $Serial install -r $Apk 2>&1
            $exit = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
    }
    $output | Out-Host
    if ($exit -ne 0) {
        throw "adb install failed with exit code $exit"
    }
}

function Get-AndroidSerial {
    $line = Invoke-Adb devices | Where-Object { $_ -match "^emulator-\d+\s+device$" } | Select-Object -First 1
    if (-not $line) {
        throw "No booted Android emulator found. Run scripts\windows\run_android_emulator_smoke.ps1 first."
    }
    return ($line -split "\s+")[0]
}

function Get-UiDump {
    param(
        [string]$Serial,
        [string]$Name
    )
    Invoke-Adb -s $Serial shell uiautomator dump /sdcard/window.xml | Out-Null
    $path = Join-Path $buildDir "$Name.xml"
    Invoke-Adb -s $Serial pull /sdcard/window.xml $path | Out-Null
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Get-BoundsCenter {
    param(
        [string]$Ui,
        [string]$Needle
    )
    $escaped = [regex]::Escape($Needle)
    $patterns = @(
        "content-desc=`"[^`"]*$escaped[^`"]*`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`"",
        "text=`"[^`"]*$escaped[^`"]*`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`""
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Ui, $pattern)
        if ($match.Success) {
            return [pscustomobject]@{
                x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
                y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
            }
        }
    }
    throw "UI text not found: $Needle"
}

function Tap-Text {
    param(
        [string]$Serial,
        [string]$Ui,
        [string]$Needle
    )
    $center = Get-BoundsCenter -Ui $Ui -Needle $Needle
    $x = $center.x
    $y = $center.y
    Invoke-Adb -s $Serial shell input tap $x $y
}

function Get-HintBoundsCenter {
    param(
        [string]$Ui,
        [string]$Needle
    )
    $escaped = [regex]::Escape($Needle)
    $patterns = @(
        "bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`"[^>]*hint=`"[^`"]*$escaped[^`"]*`"",
        "hint=`"[^`"]*$escaped[^`"]*`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`""
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Ui, $pattern)
        if ($match.Success) {
            return [pscustomobject]@{
                x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
                y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
            }
        }
    }
    throw "UI hint not found: $Needle"
}

function Tap-Hint {
    param(
        [string]$Serial,
        [string]$Ui,
        [string]$Needle
    )
    $center = Get-HintBoundsCenter -Ui $Ui -Needle $Needle
    $x = $center.x
    $y = $center.y
    Invoke-Adb -s $Serial shell input tap $x $y
}

function Test-UiHint {
    param(
        [string]$Ui,
        [string]$Needle
    )
    try {
        Get-HintBoundsCenter -Ui $Ui -Needle $Needle | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Wait-UiHint {
    param(
        [string]$Serial,
        [string]$Needle,
        [string]$Name,
        [int]$TimeoutSeconds = 8
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $ui = Get-UiDump -Serial $Serial -Name $Name
        if (Test-UiHint -Ui $ui -Needle $Needle) {
            return $ui
        }
    } while ((Get-Date) -lt $deadline)
    throw "UI hint not found before timeout: $Needle"
}

function New-TextFromCodepoints {
    param([int[]]$Codepoints)
    return -join ($Codepoints | ForEach-Object { [char]$_ })
}

function Remove-AndroidSmokeUsers {
    param([string]$HostName)
    if ($SkipServerCleanup -or -not $EnableServerCleanup) { return }
    $allowedControlPlaneHosts = @('72.56.32.197', '176.113.81.35')
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        throw "-ControlPlaneHost is required when -EnableServerCleanup is used."
    }
    if ($HostName -notin $allowedControlPlaneHosts) {
        throw "Refusing Android smoke cleanup on non-control-plane host: $HostName"
    }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "wsl.exe not found; server cleanup skipped."
        return
    }

    $remoteScript = @'
set -euo pipefail
DB=/opt/bluevpn/backend/data/bluevpn.db
PATTERN='android-smoke-%@example.invalid'
set +e
PKEYS=$(python3 - "$DB" "$PATTERN" <<'PY'
import sqlite3, sys
db_path, pattern = sys.argv[1:]
con = sqlite3.connect(db_path)
cur = con.cursor()
try:
    rows = cur.execute("""
        select d.client_public_key
        from devices d join users u on u.id=d.user_id
        where u.email like ? and d.client_public_key is not null and d.client_public_key != ''
    """, (pattern,)).fetchall()
except sqlite3.Error:
    rows = []
for (public_key,) in rows:
    print(public_key)
PY
)
set -e
for public_key in $PKEYS; do
  [ -n "$public_key" ] && wg set wg0 peer "$public_key" remove || true
done
python3 - "$DB" "$PATTERN" <<'PY'
import sqlite3, sys
db_path, pattern = sys.argv[1:]
con = sqlite3.connect(db_path)
cur = con.cursor()
tables = {row[0] for row in cur.execute("select name from sqlite_master where type='table'")}
ids = [row[0] for row in cur.execute("select id from users where email like ?", (pattern,)).fetchall()]
emails = [row[0] for row in cur.execute("select email from users where email like ?", (pattern,)).fetchall()]
if ids:
    marks = ",".join("?" for _ in ids)
    for table, column in [
        ("endpoint_assignments", "user_id"),
        ("client_endpoint_assignments", "user_id"),
        ("devices", "user_id"),
        ("subscriptions", "user_id"),
        ("support_reports", "user_id"),
        ("payments", "user_id"),
        ("billing_orders", "user_id"),
    ]:
        if table in tables:
            try:
                cur.execute(f"delete from {table} where {column} in ({marks})", ids)
            except sqlite3.Error:
                pass
    if "auth_challenges" in tables and emails:
        cols = {row[1] for row in cur.execute("pragma table_info(auth_challenges)")}
        email_marks = ",".join("?" for _ in emails)
        for col in ("contact", "email"):
            if col in cols:
                cur.execute(f"delete from auth_challenges where {col} in ({email_marks})", emails)
    cur.execute(f"delete from users where id in ({marks})", ids)
con.commit()
print(f"android_smoke_users_cleaned={len(ids)}")
PY
wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || true
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
    wsl.exe ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@$HostName" "echo $encoded | base64 -d | bash"
}

$serial = Get-AndroidSerial
$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
if ($InstallApk) {
    Install-AndroidApk -Serial $serial -PackageName $PackageName -Apk $resolvedApk
}

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$emailLocal = "$SmokeEmailPrefix-$stamp"
$email = "$emailLocal@$SmokeEmailDomain"
$labelPassword = New-TextFromCodepoints @(0x041F, 0x0430, 0x0440, 0x043E, 0x043B, 0x044C)
$labelCreateAccount = New-TextFromCodepoints @(0x0421, 0x043E, 0x0437, 0x0434, 0x0430, 0x0442, 0x044C, 0x0020, 0x0430, 0x043A, 0x043A, 0x0430, 0x0443, 0x043D, 0x0442)
$labelConnectVpn = New-TextFromCodepoints @(0x041F, 0x043E, 0x0434, 0x043A, 0x043B, 0x044E, 0x0447, 0x0438, 0x0442, 0x044C, 0x0020, 0x0056, 0x0050, 0x004E)
$labelDisconnectVpn = New-TextFromCodepoints @(0x041E, 0x0442, 0x043A, 0x043B, 0x044E, 0x0447, 0x0438, 0x0442, 0x044C, 0x0020, 0x0056, 0x0050, 0x004E)

try {
    Remove-AndroidSmokeUsers -HostName $ControlPlaneHost
    Invoke-Adb -s $serial shell pm clear $PackageName | Out-Null
    Invoke-Adb -s $serial shell am force-stop "com.google.android.apps.messaging" | Out-Null
    Invoke-Adb -s $serial shell am start -n "$PackageName/.MainActivity" | Out-Null
    Start-Sleep -Seconds 4

    $ui = Get-UiDump -Serial $serial -Name "android_e2e_auth_start"
    if (-not (Test-UiHint -Ui $ui -Needle $labelPassword)) {
        Tap-Text -Serial $serial -Ui $ui -Needle $labelPassword
        $ui = Wait-UiHint -Serial $serial -Needle $labelPassword -Name "android_e2e_password_tab"
    }

    Tap-Hint -Serial $serial -Ui $ui -Needle "Email"
    Invoke-Adb -s $serial shell input text $emailLocal
    Invoke-Adb -s $serial shell input keyevent 77
    Invoke-Adb -s $serial shell input text $SmokeEmailDomain

    $ui = Get-UiDump -Serial $serial -Name "android_e2e_email_filled"
    Tap-Hint -Serial $serial -Ui $ui -Needle $labelPassword
    Start-Sleep -Milliseconds 300
    Invoke-Adb -s $serial shell input text $SmokePassword
    Invoke-Adb -s $serial shell input keyevent 4

    Start-Sleep -Milliseconds 800
    $ui = Get-UiDump -Serial $serial -Name "android_e2e_filled"
    Tap-Text -Serial $serial -Ui $ui -Needle $labelCreateAccount

    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 3
        $ui = Get-UiDump -Serial $serial -Name "android_e2e_after_register"
        if ($ui -match [regex]::Escape($labelConnectVpn)) { break }
    } while ((Get-Date) -lt $deadline)
    if ($ui -notmatch [regex]::Escape($labelConnectVpn)) {
        throw "Registration did not reach the main VPN screen."
    }

    Tap-Text -Serial $serial -Ui $ui -Needle $labelConnectVpn
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Seconds 3
        $ui = Get-UiDump -Serial $serial -Name "android_e2e_permission_or_connected"
        if ($ui -match "OK") {
            Tap-Text -Serial $serial -Ui $ui -Needle "OK"
            Start-Sleep -Seconds 5
        }
        $connectivity = (Invoke-Adb -s $serial shell dumpsys connectivity |
            Select-String -Pattern "VPN CONNECTED extra: VPN:pro.greenvpn.app|InterfaceName: tun0|pro.greenvpn.app" -Context 0,1) -join "`n"
        if ($connectivity -match "VPN CONNECTED" -and $connectivity -match "tun0") { break }
    } while ((Get-Date) -lt $deadline)

    if ($connectivity -notmatch "VPN CONNECTED" -or $connectivity -notmatch "tun0") {
        throw "VPN did not become active."
    }

    $connectedScreenshot = Join-Path $buildDir "android_e2e_connected.png"
    & $adb -s $serial exec-out screencap -p > $connectedScreenshot

    $ui = Get-UiDump -Serial $serial -Name "android_e2e_connected"
    if ($ui -match [regex]::Escape($labelDisconnectVpn)) {
        Tap-Text -Serial $serial -Ui $ui -Needle $labelDisconnectVpn
        Start-Sleep -Seconds 5
    }
    $afterDisconnect = (Invoke-Adb -s $serial shell dumpsys connectivity |
        Select-String -Pattern "VPN CONNECTED extra: VPN:pro.greenvpn.app|InterfaceName: tun0|pro.greenvpn.app" -Context 0,1) -join "`n"

    [pscustomobject]@{
        ok = $true
        serial = $serial
        package = $PackageName
        apk = $resolvedApk
        smokeEmail = $email
        connected = $true
        disconnected = ($afterDisconnect -notmatch "VPN CONNECTED")
        screenshot = $connectedScreenshot
    }
} finally {
    Remove-AndroidSmokeUsers -HostName $ControlPlaneHost
}
