# BlueVPN PATCH ALL v7
# - Fix Runner.exe.manifest (asInvoker)
# - Patch CONFIG STORE (managed config path + CRUD)
# - Patch BACKEND (WireGuard for Windows: install/uninstall tunnel service, start/stop, endpoint bypass route)
# - Fix any .managedConfigPath() call sites -> .managedConfigPath
# - (Optional) Build + Deploy (same logic as bluevpn_build_release.ps1)

param(
  [switch]$SkipBuild
  [switch]$SkipDeploy
  [string]$TunnelName = 'BlueVPN'
  [string]$BuildRoot = 'C:\BlueVPN_Builds'
)

$ErrorActionPreference = 'Stop'

function Info([string]$s) { Write-Host $s -ForegroundColor Cyan }
function Ok([string]$s)   { Write-Host $s -ForegroundColor Green }
function Warn([string]$s) { Write-Host $s -ForegroundColor Yellow }

Info "== BlueVPN PATCH ALL v7 =="

$proj = Join-Path $env:USERPROFILE 'projects\bluevpn'
if (!(Test-Path $proj)) { throw "Project folder not found: $proj" }

Set-Location $proj
Info ("Project: " + (Get-Location).Path)

# stop app (best-effort)
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $proj '_patch_backup'
$backup = Join-Path $backupRoot $stamp
New-Item -ItemType Directory -Force -Path $backup | Out-Null

$main = Join-Path $proj 'lib\main.dart'
$manifest = Join-Path $proj 'windows\runner\Runner.exe.manifest'

if (!(Test-Path $main)) { throw "main.dart not found: $main" }

Copy-Item $main (Join-Path $backup 'main.dart') -Force
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $backup 'Runner.exe.manifest') -Force }

Ok ("Backup created: " + $backup)

# =========================
# 1) Safe manifest (asInvoker)
# =========================
Info "Writing safe Runner.exe.manifest (asInvoker)..."

$manifestDir = Split-Path -Parent $manifest
if (!(Test-Path $manifestDir)) { New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null }

@'
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
'@ | Set-Content -Encoding UTF8 -Path $manifest

Ok "Manifest updated."

# =========================
# Helpers: patch text
# =========================
function Get-RawText([string]$path) {
  return Get-Content -Raw -Encoding UTF8 $path
}

function Set-RawText([string]$path, [string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

function Ensure-Import([ref]$textRef, [string]$importLine) {
  $text = $textRef.Value
  if ($text -match [regex]::Escape($importLine)) { return }
  # insert after last import; if none, insert at top
  $m = [regex]::Matches($text, "(?m)^\s*import\s+['""][^'""]+['""]\s*;\s*$")
  if ($m.Count -gt 0) {
    $last = $m[$m.Count-1]
    $pos = $last.Index + $last.Length
    $text = $text.Insert($pos, "`r`n$importLine")
  } else {
    $text = "$importLine`r`n$text"
  }
  $textRef.Value = $text
}

function Replace-Section([ref]$textRef, [string]$marker, [string]$newBlock, [switch]$ToEOF) {
  $text = $textRef.Value
  $pos = $text.IndexOf($marker)
  if ($pos -lt 0) { throw "Marker not found: $marker" }

  $start = $text.LastIndexOf("/* =========================", $pos)
  if ($start -lt 0) { throw "Section header not found for marker: $marker" }

  if ($ToEOF) {
    $textRef.Value = $text.Substring(0, $start) + $newBlock + "`r`n"
    return
  }

  $next = $text.IndexOf("/* =========================", $start + 10)
  if ($next -lt 0) {
    # fallback to EOF
    $textRef.Value = $text.Substring(0, $start) + $newBlock + "`r`n"
    return
  }

  $textRef.Value = $text.Substring(0, $start) + $newBlock + $text.Substring($next)
}

# =========================
# 2) Patch main.dart
# =========================
Info "Patching lib/main.dart ..."

$t = Get-RawText $main
$tref = [ref]$t

# --- ensure imports needed by backend/config store ---
Ensure-Import $tref "import 'dart:io';"
Ensure-Import $tref "import 'dart:convert';"
Ensure-Import $tref "import 'dart:typed_data';"
Ensure-Import $tref "import 'package:flutter/foundation.dart';"

# --- CONFIG STORE block (use ProgramData\BlueVPN\<tunnel>.conf) ---
$newCfg = @'
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
    final dir = Directory('${_programData()}\\BlueVPN');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  // Use as a property (not a method): `await store.managedConfigPath`
  Future<String> get managedConfigPath async {
    final dir = await _baseDir();
    return '$dir\\$kTunnelName.conf';
  }

  Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    final p = await managedConfigPath;
    return File(p).existsSync();
  }

  Future<void> writeManagedConfig(String configText) async {
    if (kIsWeb) return;
    final p = await managedConfigPath;
    final f = File(p);
    if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
    await f.writeAsString(configText);
  }

  Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;
    try {
      final p = await managedConfigPath;
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

'@

Replace-Section $tref "CONFIG STORE (HIDDEN)" $newCfg

# --- BACKEND block (replace to EOF) ---
$newBackend = @'
/* =========================
   BACKEND (WIREGUARD FOR WINDOWS)
   ========================= */

class VpnBackendResult {
  final bool ok;
  final String? message;
  const VpnBackendResult({required this.ok, this.message});
}

abstract class VpnBackend {
  const VpnBackend();

  Future<VpnBackendResult> connect({required String configPath});
  Future<VpnBackendResult> disconnect();
  Future<bool> isConnected();

  static VpnBackend createDefault({required String tunnelName}) {
    if (kIsWeb) {
      return const UnsupportedVpnBackend(
        reason: 'Web: реальное подключение недоступно. Запусти Windows-версию.',
      );
    }
    if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason: 'Платформа не поддерживается (пока только Windows).',
    );
  }
}

class UnsupportedVpnBackend extends VpnBackend {
  final String reason;
  const UnsupportedVpnBackend({required this.reason});

  @override
  Future<VpnBackendResult> connect({required String configPath}) async =>
      VpnBackendResult(ok: false, message: reason);

  @override
  Future<VpnBackendResult> disconnect() async =>
      VpnBackendResult(ok: false, message: reason);

  @override
  Future<bool> isConnected() async => false;
}

class WireGuardWindowsBackend extends VpnBackend {
  final String tunnelName;
  final String _exe;

  String? _lastConfigPath;

  WireGuardWindowsBackend({required this.tunnelName})
      : _exe = _resolveWireGuardExe();

  static String _resolveWireGuardExe() {
    final candidates = <String>[];
    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];

    if (pf != null && pf.trim().isNotEmpty) {
      candidates.add('${pf.trim()}\\WireGuard\\wireguard.exe');
    }
    if (pf86 != null && pf86.trim().isNotEmpty) {
      candidates.add('${pf86.trim()}\\WireGuard\\wireguard.exe');
    }

    candidates.add(r'C:\Program Files\WireGuard\wireguard.exe');
    candidates.add(r'C:\Program Files (x86)\WireGuard\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return 'wireguard.exe';
  }

  String get _serviceName => r'WireGuardTunnel$' + tunnelName;

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  // UAC: run PowerShell as admin (inner script passed via -EncodedCommand UTF-16LE Base64)
  Uint8List _utf16le(String s) {
    final units = s.codeUnits;
    final b = BytesBuilder(copy: false);
    for (final u in units) {
      b.addByte(u & 0xFF);
      b.addByte((u >> 8) & 0xFF);
    }
    return b.toBytes();
  }

  Future<ProcessResult> _runElevatedPowerShell(String innerScript) async {
    final enc = base64.encode(_utf16le(innerScript));
    final outer = r'''
$ErrorActionPreference="Stop"
$enc="__ENC__"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-EncodedCommand",$enc
)
exit $p.ExitCode
'''.replaceAll('__ENC__', enc);

    return _run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      outer,
    ]);
  }

  Future<VpnBackendResult> _ensureWireGuardPresent() async {
    final isAbs = _exe.contains(':\\') || _exe.startsWith(r'\\');
    if (isAbs && !File(_exe).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message: 'WireGuard не найден по пути:\n$_exe\n\nУстанови WireGuard for Windows.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  static String? _extractEndpointIPv4(String cfg) {
    final re = RegExp(
      r'^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<void> _ensureEndpointBypassRoute(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return;

      final ps = r'''
$ErrorActionPreference="SilentlyContinue"
$ep="__EP__"
$rt = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
$gw = $rt.NextHop
if (-not $gw -or $gw -eq "0.0.0.0") { exit 0 }
route.exe delete $ep | Out-Null
route.exe add $ep mask 255.255.255.255 $gw metric 1 | Out-Null
'''.replaceAll('__EP__', ep);

      await _runElevatedPowerShell(ps);
    } catch (_) {}
  }

  Future<void> _removeEndpointBypassRouteFromConfig(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return;

      final ps = r'''
$ErrorActionPreference="SilentlyContinue"
$ep="__EP__"
route.exe delete $ep | Out-Null
'''.replaceAll('__EP__', ep);

      await _runElevatedPowerShell(ps);
    } catch (_) {}
  }

  Future<bool> _waitForState(String want, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final q = await _run('sc', ['query', _serviceName]);
      final out = ('${q.stdout}\n${q.stderr}').toString();
      if (out.contains(want)) return true;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<String?> _configPathForCleanup() async {
    if (_lastConfigPath != null && _lastConfigPath!.trim().isNotEmpty) {
      return _lastConfigPath;
    }
    // best-effort: read current binpath from sc qc
    try {
      final res = await _run('sc', ['qc', _serviceName]);
      if (res.exitCode != 0) return null;
      final out = ('${res.stdout}\n${res.stderr}').toString();
      final re = RegExp(r'([A-Za-z]:\\[^"\r\n]+\.conf)', caseSensitive: false);
      return re.firstMatch(out)?.group(1);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    _lastConfigPath = configPath;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(ok: false, message: 'Конфиг не найден:\n$configPath');
    }

    try {
      await _ensureEndpointBypassRoute(configPath);

      final ps = r'''
$ErrorActionPreference="Stop"
$exe="__EXE__"
$cfg="__CFG__"
$tn="__TN__"
$svc="__SVC__"

sc.exe stop $svc | Out-Null
& $exe /uninstalltunnelservice $tn | Out-Null
& $exe /installtunnelservice $cfg | Out-Null
sc.exe start $svc | Out-Null
'''.replaceAll('__EXE__', _exe)
        .replaceAll('__CFG__', configPath)
        .replaceAll('__TN__', tunnelName)
        .replaceAll('__SVC__', _serviceName);

      final pr = await _runElevatedPowerShell(ps);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(ok: false, message: msg.isEmpty ? 'Ошибка подключения (PowerShell/UAC).' : msg);
      }

      final running = await _waitForState('RUNNING', const Duration(seconds: 8));
      if (!running) {
        return const VpnBackendResult(
          ok: false,
          message: 'Сервис не вышел в RUNNING (проверь Endpoint/AllowedIPs/DNS).',
        );
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'WireGuard ошибка: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    try {
      final ps = r'''
$ErrorActionPreference="Stop"
$svc="__SVC__"
sc.exe stop $svc | Out-Null
'''.replaceAll('__SVC__', _serviceName);

      final pr = await _runElevatedPowerShell(ps);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(ok: false, message: msg.isEmpty ? 'Ошибка отключения (PowerShell/UAC).' : msg);
      }

      await _waitForState('STOPPED', const Duration(seconds: 8));

      final p = await _configPathForCleanup();
      if (p != null && p.trim().isNotEmpty && File(p).existsSync()) {
        await _removeEndpointBypassRouteFromConfig(p);
      }

      final on = await isConnected();
      if (on) {
        return const VpnBackendResult(ok: false, message: 'Сервис всё ещё RUNNING после stop.');
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Disconnect ошибка: $e');
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final res = await _run('sc', ['query', _serviceName]);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('RUNNING');
    } catch (_) {
      return false;
    }
  }
}

'@

Replace-Section $tref "BACKEND (WIREGUARD FOR WINDOWS)" $newBackend -ToEOF

# --- fix any managedConfigPath() call sites ---
$tref.Value = [regex]::Replace($tref.Value, "\.managedConfigPath\s*\(\s*\)", ".managedConfigPath")

Set-RawText $main $tref.Value
Ok "main.dart patched."

# =========================
# 3) Build
# =========================
if ($SkipBuild) {
  Warn "SkipBuild specified. Done."
  exit 0
}

Info "flutter pub get..."
flutter pub get | Out-Host

Info "flutter clean..."
flutter clean | Out-Host

Info "flutter build windows --release..."
flutter build windows --release | Out-Host

$release = Join-Path $proj 'build\windows\x64\runner\Release'
if (!(Test-Path $release)) { throw "Release folder not found. Build failed. Expected: $release" }
Ok ("Build OK: " + $release)

# =========================
# 4) Deploy
# =========================
if ($SkipDeploy) {
  Warn "SkipDeploy specified. Done."
  exit 0
}

Info "Deploying..."
if (!(Test-Path $BuildRoot)) { New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null }

$dst = Join-Path $BuildRoot ("BlueVPN_" + $stamp)
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $dst -Recurse -Force

$exe = Join-Path $dst 'bluevpn.exe'
if (!(Test-Path $exe)) { throw "bluevpn.exe not found after deploy: $exe" }

# Shortcut on Desktop
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'BlueVPN.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Ok ("OK: Release deployed to: " + $dst)
Ok ("OK: Shortcut updated:   " + $lnk)
Warn "Note: If ON/OFF asks for UAC, accept it (WireGuard service needs admin)."
