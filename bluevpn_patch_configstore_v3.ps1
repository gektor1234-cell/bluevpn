param(
  [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

# Keep output ASCII-friendly to avoid mojibake in legacy consoles
try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  [Console]::InputEncoding  = New-Object System.Text.UTF8Encoding($false)
} catch {}

function Info($s){ Write-Host $s -ForegroundColor Cyan }
function Ok($s){ Write-Host $s -ForegroundColor Green }
function Warn($s){ Write-Host $s -ForegroundColor Yellow }

$proj = $PSScriptRoot
if (-not $proj -or $proj.Trim().Length -eq 0) { $proj = (Get-Location).Path }
Set-Location $proj

$main = Join-Path $proj "lib\main.dart"
$manifest = Join-Path $proj "windows\runner\Runner.exe.manifest"

if (!(Test-Path $main)) { throw "main.dart not found: $main" }

# Stop running app to avoid file locks
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# Backup
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $proj ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item $main (Join-Path $bakDir "main.dart") -Force
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $bakDir "Runner.exe.manifest") -Force }
Ok ("Backup created: " + $bakDir)

# Write safe manifest (asInvoker) to avoid mt.exe/LNK1327 related issues
Info "Writing safe Runner.exe.manifest (asInvoker)..."
$manifestXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" processorArchitecture="*" name="BlueVPN" type="win32"/>
  <description>BlueVPN</description>

  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>

  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
'@

if (Test-Path (Split-Path -Parent $manifest)) {
  $manifestXml | Set-Content -Encoding UTF8 -Path $manifest
  Ok "Manifest updated."
} else {
  Warn "Manifest folder missing, skipped."
}

# =========================
# Patch CONFIG STORE block
# =========================
Info "Patching CONFIG STORE block in lib/main.dart ..."

$text = Get-Content -Raw -Encoding UTF8 $main

$cfgKeyPos = $text.IndexOf("CONFIG STORE (HIDDEN)")
if ($cfgKeyPos -lt 0) { throw "CONFIG STORE (HIDDEN) marker not found in main.dart" }

$cfgStart = $text.LastIndexOf("/* =========================", $cfgKeyPos)
if ($cfgStart -lt 0) { throw "CONFIG STORE section header not found" }

$authKeyPos = $text.IndexOf("AUTH UI", $cfgKeyPos)
if ($authKeyPos -lt 0) { throw "AUTH UI marker not found (needed to locate end of CONFIG STORE section)" }

$authStart = $text.LastIndexOf("/* =========================", $authKeyPos)
if ($authStart -lt 0 -or $authStart -le $cfgStart) { throw "Cannot determine CONFIG STORE section bounds" }

# New ConfigStore with all required methods referenced by the app
$newCfgBlock = @'
/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  String _programData() {
    final base = Platform.environment['ProgramData'];
    if (base != null && base.trim().isNotEmpty) return base.trim();
    return r'C:\ProgramData';
  }

  Future<String> _baseDir() async {
    final dir = Directory('${_programData()}\\BlueVPN\\configs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> managedConfigPath() async {
    final dir = await _baseDir();
    return '$dir\\$kTunnelName.conf';
  }

  Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    final p = await managedConfigPath();
    return File(p).existsSync();
  }

  Future<void> writeManagedConfig(String configText) async {
    if (kIsWeb) return;
    final p = await managedConfigPath();
    final f = File(p);
    if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
    await f.writeAsString(configText);
  }

  Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;
    try {
      final p = await managedConfigPath();
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

'@

$text2 = $text.Substring(0, $cfgStart) + $newCfgBlock + $text.Substring($authStart)
Set-Content -Path $main -Value $text2 -Encoding UTF8
Ok "CONFIG STORE patched."

if ($NoBuild) {
  Warn "NoBuild specified. Done."
  exit 0
}

# =========================
# Build (Release)
# =========================
Info "flutter pub get..."
flutter pub get | Out-Host

Info "flutter clean..."
flutter clean | Out-Host

Info "flutter build windows --release -t .\lib\main.dart ..."
flutter build windows --release -t .\lib\main.dart | Out-Host

$release = Join-Path $proj "build\windows\x64\runner\Release"
if (!(Test-Path $release)) { throw "Release folder not found. Build failed. Expected: $release" }

Ok ("Build OK: " + $release)

# =========================
# Deploy to Desktop (new folder; no deletes to avoid OneDrive locks)
# =========================
Info "Deploying to Desktop..."
$desktop = [Environment]::GetFolderPath('Desktop')
$dst = Join-Path $desktop ("BlueVPN_build_" + $stamp)
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $release "*") -Destination $dst -Recurse -Force

$exe = Join-Path $dst "bluevpn.exe"
if (!(Test-Path $exe)) { throw "bluevpn.exe not found in deployed folder: $dst" }

# Shortcut
$lnk = Join-Path $desktop "BlueVPN.lnk"
if (Test-Path $lnk) { Remove-Item $lnk -Force }
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Ok ("Deployed folder: " + $dst)
Ok ("Shortcut updated: " + $lnk)
Warn "If ON/OFF asks for UAC, accept it (WireGuard service needs admin)."
