# BlueVPN patch: fix VPN toggle backend (WireGuard service + endpoint route), fix manifest, build & deploy
# Works on Windows PowerShell 5.1+

$ErrorActionPreference = 'Stop'

function Info($s){ Write-Host $s -ForegroundColor Cyan }
function Ok($s){ Write-Host $s -ForegroundColor Green }
function Warn($s){ Write-Host $s -ForegroundColor Yellow }
function Err($s){ Write-Host $s -ForegroundColor Red }

# --- project root (script must be in %USERPROFILE%\projects\bluevpn) ---
$proj = Join-Path $env:USERPROFILE 'projects\bluevpn'
if (!(Test-Path $proj)) { throw "Project folder not found: $proj" }
Set-Location $proj

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $proj ("_patch_backup\\$stamp")
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

# --- stop running app to avoid locks ---
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

# --- paths ---
$main = Join-Path $proj 'lib\main.dart'
$manifest = Join-Path $proj 'windows\runner\Runner.exe.manifest'

if (!(Test-Path $main)) { throw "main.dart not found: $main" }
if (!(Test-Path $manifest)) { throw "Runner.exe.manifest not found: $manifest" }

Copy-Item $main (Join-Path $backupDir 'main.dart') -Force
Copy-Item $manifest (Join-Path $backupDir 'Runner.exe.manifest') -Force
Ok "Backup created: $backupDir"

# ============================
# 1) Write SAFE manifest (asInvoker)
# ============================
Info 'Writing safe Runner.exe.manifest (asInvoker)...'
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

# Windows PowerShell 5.1: UTF8 writes BOM (good for Cyrillic if any)
$manifestXml | Set-Content -Path $manifest -Encoding UTF8
Ok 'Manifest updated.'

# ============================
# 2) Patch main.dart sections
#    - ensure required imports exist
#    - replace CONFIG STORE (HIDDEN) block (optional)
#    - replace BACKEND (WIREGUARD FOR WINDOWS) block
# ============================

function Ensure-ImportLine([string]$filePath, [string]$importLine) {
  $t = Get-Content -Raw -Encoding UTF8 $filePath
  if ($t -match [regex]::Escape($importLine)) { return }

  $lines = Get-Content -Encoding UTF8 $filePath
  $lastImport = -1
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart().StartsWith('import ')) { $lastImport = $i }
  }
  if ($lastImport -ge 0) {
    $newLines = @()
    $newLines += $lines[0..$lastImport]
    $newLines += $importLine
    if ($lastImport + 1 -lt $lines.Count) { $newLines += $lines[($lastImport+1)..($lines.Count-1)] }
    $newLines | Set-Content -Encoding UTF8 -Path $filePath
  } else {
    # no import lines found, prepend
    ($importLine + "`r`n" + (Get-Content -Raw -Encoding UTF8 $filePath)) | Set-Content -Encoding UTF8 -Path $filePath
  }
}

Info 'Ensuring required imports...'
Ensure-ImportLine $main "import 'dart:io';"
Ensure-ImportLine $main "import 'package:flutter/foundation.dart';"
Ok 'Imports OK.'

# ---- helper: replace one section by marker between /* ========================= headers ----
function Replace-Section([string]$filePath, [string]$marker, [string]$newBlock) {
  $text = Get-Content -Raw -Encoding UTF8 $filePath
  $idx = $text.IndexOf($marker)
  if ($idx -lt 0) { return $false }

  $start = $text.LastIndexOf('/* =========================', $idx)
  if ($start -lt 0) { throw "Section header not found for marker: $marker" }

  $next = $text.IndexOf('/* =========================', $idx + $marker.Length)
  if ($next -lt 0) { $next = $text.Length }

  $patched = $text.Substring(0, $start) + $newBlock + $text.Substring($next)
  $patched | Set-Content -Encoding UTF8 -Path $filePath
  return $true
}

# ---- CONFIG STORE block (optional) ----
$configBlock = @'
/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  // Stored in ProgramData (common for all users, ok without admin in most setups)
  static final Directory _baseDir = Directory(r'C:\\ProgramData\\BlueVPN\\configs');

  static String get managedConfigPath => '${_baseDir.path}\\BlueVPN.conf';

  static Future<void> ensureReady() async {
    if (!await _baseDir.exists()) {
      await _baseDir.create(recursive: true);
    }
  }

  static Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    await ensureReady();
    return File(managedConfigPath).existsSync();
  }

  static Future<String?> readManagedConfig() async {
    if (kIsWeb) return null;
    await ensureReady();
    final f = File(managedConfigPath);
    if (!f.existsSync()) return null;
    return f.readAsString();
  }

  static Future<void> writeManagedConfig(String text) async {
    if (kIsWeb) return;
    await ensureReady();
    final f = File(managedConfigPath);
    await f.writeAsString(text);
  }

  static Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;
    await ensureReady();
    final f = File(managedConfigPath);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

'@

$didConfig = Replace-Section $main 'CONFIG STORE (HIDDEN)' $configBlock
if ($didConfig) { Ok 'CONFIG STORE patched.' } else { Warn 'CONFIG STORE marker not found (skipped).' }

# ---- BACKEND (WireGuard) ----
$backendBlock = @'
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
        reason: 'Web mode: VPN is not available. Run Windows build.',
      );
    }
    if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason: 'Unsupported platform (Windows-only backend).',
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

    candidates.add(r'C:\\Program Files\\WireGuard\\wireguard.exe');
    candidates.add(r'C:\\Program Files (x86)\\WireGuard\\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    // fallback (if in PATH)
    return 'wireguard.exe';
  }

  String get _serviceName => 'WireGuardTunnel\$' + tunnelName;

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  Future<VpnBackendResult> _ensureWireGuardPresent() async {
    final isAbs = _exe.contains(':\\') || _exe.startsWith(r'\\');
    if (isAbs && !File(_exe).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message: 'WireGuard not found at:\n$_exe\nInstall WireGuard for Windows.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  String _psConnect(String cfgPath) {
    final exe = _exe;
    final tn = tunnelName;
    final svc = _serviceName;

    // Everything inside ONE elevated script (route + reinstall service + start)
    return r'''
$ErrorActionPreference="Stop"
$exe="__EXE__"
$cfg="__CFG__"
$tn="__TN__"
$svc="__SVC__"

if (!(Test-Path $cfg)) { throw "Config not found: $cfg" }

# Parse endpoint IPv4
$txt = Get-Content -Raw -Encoding UTF8 $cfg
$ep = $null
if ($txt -match '^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') {
  $ep = $matches[1]
}

# Add route to endpoint via current default gateway (prevents handshake going into tunnel)
if ($ep) {
  $rt = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
  $gw = $rt.NextHop
  if ($gw -and $gw -ne "0.0.0.0") {
    route.exe delete $ep | Out-Null
    route.exe add $ep mask 255.255.255.255 $gw metric 1 | Out-Null
  }
}

# Stop service (ignore)
sc.exe stop $svc | Out-Null

# Reinstall tunnel service to point to our cfg
& $exe /uninstalltunnelservice $tn | Out-Null
& $exe /installtunnelservice $cfg | Out-Null

# Start
sc.exe start $svc | Out-Null
'''
        .replaceAll('__EXE__', exe.replaceAll('\"', ''))
        .replaceAll('__CFG__', cfgPath.replaceAll('\"', ''))
        .replaceAll('__TN__', tn.replaceAll('\"', ''))
        .replaceAll('__SVC__', svc.replaceAll('\"', ''));
  }

  String _psDisconnect(String? cfgPath) {
    final svc = _serviceName;

    // Stop service and remove endpoint route (best-effort)
    return r'''
$ErrorActionPreference="SilentlyContinue"
$svc="__SVC__"
$cfg="__CFG__"

sc.exe stop $svc | Out-Null

if ($cfg -and (Test-Path $cfg)) {
  $txt = Get-Content -Raw -Encoding UTF8 $cfg
  $ep = $null
  if ($txt -match '^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') {
    $ep = $matches[1]
  }
  if ($ep) {
    route.exe delete $ep | Out-Null
  }
}
'''
        .replaceAll('__SVC__', svc.replaceAll('\"', ''))
        .replaceAll('__CFG__', (cfgPath ?? '').replaceAll('\"', ''));
  }

  Future<VpnBackendResult> _runElevatedScript(String psScript) async {
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('bluevpn_uac_');
      final ps1 = File('${tmp.path}\\bluevpn_uac.ps1');
      await ps1.writeAsString(psScript, flush: true);

      // Outer script (non-elevated) triggers UAC and waits.
      final safePath = ps1.path.replaceAll("'", "''");
      final outer = r'''
$ErrorActionPreference="Stop"
$ps1='__FILE__'
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-File", $ps1
)
exit $p.ExitCode
'''.replaceAll('__FILE__', safePath);

      final res = await _run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        outer,
      ]);

      final out = ('${res.stdout}\n${res.stderr}').trim();
      if (res.exitCode != 0) {
        return VpnBackendResult(
          ok: false,
          message: out.isEmpty
              ? 'UAC/PowerShell failed with code ${res.exitCode}'
              : out,
        );
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Elevated PowerShell error: $e');
    } finally {
      try {
        if (tmp != null) await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<bool> _waitForState(String want, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        final q = await _run('sc', ['query', _serviceName]);
        final out = ('${q.stdout}\n${q.stderr}').toString();
        if (out.contains(want)) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<String?> _currentServiceConfigPath() async {
    try {
      final res = await _run('sc', ['qc', _serviceName]);
      if (res.exitCode != 0) return null;
      final out = ('${res.stdout}\n${res.stderr}').toString();
      final re = RegExp(r'([A-Za-z]:\\[^\"\r\n]+\.conf)', caseSensitive: false);
      final m = re.firstMatch(out);
      return m?.group(1);
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
      return VpnBackendResult(ok: false, message: 'Config not found:\n$configPath');
    }

    // run elevated connect script
    final pr = await _runElevatedScript(_psConnect(configPath));
    if (!pr.ok) return pr;

    final running = await _waitForState('RUNNING', const Duration(seconds: 8));
    if (!running) {
      return const VpnBackendResult(
        ok: false,
        message: 'Service did not reach RUNNING. Check Endpoint/AllowedIPs/DNS.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    final cfg = await _currentServiceConfigPath() ?? _lastConfigPath;
    final pr = await _runElevatedScript(_psDisconnect(cfg));
    if (!pr.ok) return pr;

    await _waitForState('STOPPED', const Duration(seconds: 8));

    final on = await isConnected();
    if (on) {
      return const VpnBackendResult(ok: false, message: 'Service still RUNNING after stop.');
    }
    return const VpnBackendResult(ok: true);
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

$didBackend = Replace-Section $main 'BACKEND (WIREGUARD FOR WINDOWS)' $backendBlock
if (!$didBackend) { throw 'BACKEND marker not found in main.dart' }
Ok 'BACKEND patched.'

# ============================
# 3) Build Release
# ============================
Info 'flutter pub get...'
flutter pub get | Out-Host

Info 'flutter clean...'
flutter clean | Out-Host

Info 'flutter build windows --release -t .\\lib\\main.dart ...'
flutter build windows --release -t .\\lib\\main.dart | Out-Host

# Find Release folder (robust)
$release = Join-Path $proj 'build\\windows\\x64\\runner\\Release'
if (!(Test-Path $release)) {
  $cand = Get-ChildItem -Path (Join-Path $proj 'build\\windows') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'runner\\Release' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
  if ($cand) { $release = $cand }
}
if (!(Test-Path $release)) { throw "Release folder not found. Build failed. Expected: $release" }

# ============================
# 4) Deploy build to LOCALAPPDATA (avoid OneDrive Desktop locks)
# ============================
$deployRoot = Join-Path $env:LOCALAPPDATA 'BlueVPN\\builds'
$dst = Join-Path $deployRoot ("BlueVPN_" + $stamp)
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $dst -Recurse -Force

$exe = Join-Path $dst 'bluevpn.exe'
if (!(Test-Path $exe)) { throw "bluevpn.exe not found after copy: $exe" }

# ============================
# 5) Shortcut on Desktop -> latest build
# ============================
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'BlueVPN.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Ok 'DONE.'
Ok ("Build folder: " + $dst)
Ok ("Shortcut: " + $lnk)
Warn 'If UAC prompt appears on ON/OFF - accept it (WireGuard service needs admin rights).'
