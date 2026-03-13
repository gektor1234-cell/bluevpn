# BlueVPN - Patch CONFIG STORE + WireGuard BACKEND + safe manifest + build/deploy (Windows)
# Usage (from project root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v4.ps1
#
# Optional:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v4.ps1 -SkipBuild
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v4.ps1 -SkipDeploy
#
param(
  [switch]$SkipBuild,
  [switch]$SkipDeploy,
  [string]$TunnelName = "BlueVPN",
  [string]$BuildRoot = "C:\BlueVPN_Builds"
)

$ErrorActionPreference = "Stop"

function Info($s){ Write-Host $s -ForegroundColor Cyan }
function Ok($s){ Write-Host $s -ForegroundColor Green }
function Warn($s){ Write-Host $s -ForegroundColor Yellow }

# --- project root autodetect ---
$proj = (Get-Location).Path
if (!(Test-Path (Join-Path $proj "pubspec.yaml"))) {
  $fallback = Join-Path $env:USERPROFILE "projects\bluevpn"
  if (Test-Path (Join-Path $fallback "pubspec.yaml")) { $proj = $fallback }
}
Set-Location $proj

Info "== BlueVPN PATCH ALL v4 =="
Info "Project: $proj"

# --- stop running app to avoid locks ---
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# --- files ---
$main     = Join-Path $proj "lib\main.dart"
$manifest = Join-Path $proj "windows\runner\Runner.exe.manifest"

if (!(Test-Path $main)) { throw "main.dart not found: $main" }

# --- backup ---
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $proj ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item $main (Join-Path $backupDir "main.dart") -Force
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $backupDir "Runner.exe.manifest") -Force }

Ok "Backup created: $backupDir"

# ============================
# 1) SAFE MANIFEST (asInvoker)
# ============================
Info "Writing safe Runner.exe.manifest (asInvoker)..."
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

# ============================
# 2) Ensure required imports (minimal, idempotent)
# ============================
Info "Ensuring required imports..."
$text = Get-Content -Raw -Encoding UTF8 $main

function Ensure-Import([string]$needle, [string]$line){
  param([string]$needle, [string]$line)
  if ($script:text -match [regex]::Escape($needle)) { return }
  # Insert after the last existing import line at the top of the file
  $m = [regex]::Matches($script:text, "(?m)^\s*import\s+['""][^'""]+['""]\s*;\s*$")
  if ($m.Count -gt 0) {
    $last = $m[$m.Count-1]
    $pos = $last.Index + $last.Length
    $script:text = $script:text.Insert($pos, "`r`n$line")
  } else {
    $script:text = "$line`r`n`r`n" + $script:text
  }
}

Ensure-Import "import 'dart:io';"       "import 'dart:io';"
Ensure-Import "import 'dart:convert';"  "import 'dart:convert';"
Ensure-Import "import 'dart:typed_data';" "import 'dart:typed_data';"
Ensure-Import "import 'package:flutter/foundation.dart';" "import 'package:flutter/foundation.dart';"

Set-Content -Encoding UTF8 -Path $main -Value $text
Ok "Imports OK."

# reload after import edits
$text = Get-Content -Raw -Encoding UTF8 $main

# ============================
# 3) PATCH CONFIG STORE block
#    Replace between:
#      "CONFIG STORE (HIDDEN)" section header ... before "AUTH UI"
# ============================
Info "Patching CONFIG STORE block..."
$cfgMarker = $text.IndexOf("CONFIG STORE (HIDDEN)")
if ($cfgMarker -lt 0) { throw "Marker not found: CONFIG STORE (HIDDEN)" }

$cfgStart = $text.LastIndexOf("/* =========================", $cfgMarker)
if ($cfgStart -lt 0) { throw "CONFIG STORE section header not found" }

$authMarker = $text.IndexOf("AUTH UI", $cfgMarker)
if ($authMarker -lt 0) { throw "Marker not found: AUTH UI" }

$authStart = $text.LastIndexOf("/* =========================", $authMarker)
if ($authStart -lt 0 -or $authStart -le $cfgStart) { throw "AUTH UI section header not found" }

$newConfigStore = @'
/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  // Where we store the managed config file that BlueVPN uses for WireGuard service.
  // We keep it in ProgramData so the service (LocalSystem) can read it.
  String get managedConfigPath {
    if (kIsWeb) return '';
    if (!Platform.isWindows) return '';
    return r'C:\ProgramData\BlueVPN\BlueVPN.conf';
  }

  Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    final p = managedConfigPath;
    if (p.isEmpty) return false;
    return File(p).existsSync();
  }

  Future<void> writeManagedConfig(String content) async {
    if (kIsWeb) return;
    final p = managedConfigPath;
    if (p.isEmpty) return;
    final f = File(p);
    if (!f.parent.existsSync()) {
      f.parent.createSync(recursive: true);
    }
    await f.writeAsString(content);
  }

  Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;
    final p = managedConfigPath;
    if (p.isEmpty) return;
    final f = File(p);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}
'@

$text = $text.Substring(0, $cfgStart) + $newConfigStore + $text.Substring($authStart)
Set-Content -Encoding UTF8 -Path $main -Value $text
Ok "CONFIG STORE patched."

# reload after config store patch
$text = Get-Content -Raw -Encoding UTF8 $main

# ============================
# 4) PATCH BACKEND (WireGuard Windows)
#    Replace from BACKEND section header to end of file
# ============================
Info "Patching BACKEND block..."
$beKeyPos = $text.IndexOf("BACKEND (WIREGUARD FOR WINDOWS)")
if ($beKeyPos -lt 0) { throw "Marker not found: BACKEND (WIREGUARD FOR WINDOWS)" }

$beStart = $text.LastIndexOf("/* =========================", $beKeyPos)
if ($beStart -lt 0) { throw "BACKEND section header not found" }

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
        reason: 'Web-mode: real VPN is not available. Run as Windows app.',
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

  // remember last configPath for route cleanup on disconnect
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

  String get _serviceName => 'WireGuardTunnel\$${tunnelName}';

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  Future<bool> _isAdmin() async {
    // BUILTIN\Administrators SID: S-1-5-32-544
    try {
      final res = await _run('whoami', ['/groups']);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('S-1-5-32-544');
    } catch (_) {
      return false;
    }
  }

  List<int> _utf16le(String s) {
    final units = s.codeUnits;
    final bytes = BytesBuilder(copy: false);
    for (final u in units) {
      bytes.addByte(u & 0xFF);
      bytes.addByte((u >> 8) & 0xFF);
    }
    return bytes.toBytes();
  }

  Future<ProcessResult> _runElevatedPowerShell(String innerScript) async {
    // run innerScript with UAC using -EncodedCommand (UTF-16LE Base64)
    final encoded = base64.encode(_utf16le(innerScript));

    final outer = r'''
$ErrorActionPreference="Stop"
$encoded = "ENC"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-EncodedCommand",$encoded
)
exit $p.ExitCode
'''.replaceAll('ENC', encoded);

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
        message: 'WireGuard not found:\n$_exe\nInstall WireGuard for Windows.',
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
    // add route to endpoint via current default gateway (prevents handshake going into tunnel)
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

      await _run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        ps,
      ]);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _removeEndpointBypassRouteFromConfig(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return;
      await _run('route', ['delete', ep]);
    } catch (_) {
      // ignore
    }
  }

  Future<bool> _serviceExists() async {
    final res = await _run('sc', ['query', _serviceName]);
    final out = ('${res.stdout}\n${res.stderr}').toLowerCase();
    if (out.contains('1060')) return false;
    if (out.contains('не установ')) return false;
    return res.exitCode == 0;
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

  Future<VpnBackendResult> _ensureServiceInstalled(String configPath) async {
    final exists = await _serviceExists();
    if (!exists) {
      final res = await _run(_exe, ['/installtunnelservice', configPath]);
      if (res.exitCode != 0) {
        final out = ('${res.stdout}\n${res.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: out.isEmpty
              ? 'Failed to install tunnel service.'
              : 'Failed to install tunnel service:\n$out',
        );
      }
      return const VpnBackendResult(ok: true);
    }

    // If exists - still re-install to current configPath (idempotent & fixes wrong path)
    await _run('sc', ['stop', _serviceName]);
    await Future.delayed(const Duration(milliseconds: 200));
    await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
    await _run(_exe, ['/installtunnelservice', configPath]);

    return const VpnBackendResult(ok: true);
  }

  Future<String?> _configPathForCleanup() async {
    if (_lastConfigPath != null && _lastConfigPath!.trim().isNotEmpty) {
      return _lastConfigPath;
    }
    return null;
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    _lastConfigPath = configPath;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(ok: false, message: 'Config not found:\n$configPath');
    }

    try {
      await _ensureEndpointBypassRoute(configPath);

      final admin = await _isAdmin();
      if (admin) {
        final svcOk = await _ensureServiceInstalled(configPath);
        if (!svcOk.ok) return svcOk;

        await _run('sc', ['stop', _serviceName]);
        await Future.delayed(const Duration(milliseconds: 250));
        await _run('sc', ['start', _serviceName]);

        final running = await _waitForState('RUNNING', const Duration(seconds: 8));
        if (!running) {
          return const VpnBackendResult(
            ok: false,
            message: 'Service did not reach RUNNING. Check config/Endpoint/AllowedIPs/DNS.',
          );
        }
        return const VpnBackendResult(ok: true);
      }

      // no admin -> UAC once
      final inner = r'''
$ErrorActionPreference="Stop"
$exe="__EXE__"
$cfg="__CFG__"
$tn="__TN__"
$svc="__SVC__"

sc.exe stop $svc | Out-Null
& $exe /uninstalltunnelservice $tn | Out-Null
& $exe /installtunnelservice $cfg | Out-Null
sc.exe start $svc | Out-Null
'''
          .replaceAll('__EXE__', _exe)
          .replaceAll('__CFG__', configPath)
          .replaceAll('__TN__', tunnelName)
          .replaceAll('__SVC__', _serviceName);

      final pr = await _runElevatedPowerShell(inner);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: msg.isEmpty ? 'UAC/PowerShell connect failed.' : msg,
        );
      }

      final running2 = await _waitForState('RUNNING', const Duration(seconds: 8));
      if (!running2) {
        return const VpnBackendResult(ok: false, message: 'Service not RUNNING after UAC.');
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'WireGuard error: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    try {
      final admin = await _isAdmin();
      if (admin) {
        if (await _serviceExists()) {
          await _run('sc', ['stop', _serviceName]);
          await _waitForState('STOPPED', const Duration(seconds: 8));
        }
      } else {
        // no admin -> UAC
        final inner = r'''
$ErrorActionPreference="Stop"
$svc="__SVC__"
sc.exe stop $svc | Out-Null
'''.replaceAll('__SVC__', _serviceName);

        final pr = await _runElevatedPowerShell(inner);
        if (pr.exitCode != 0) {
          final msg = ('${pr.stdout}\n${pr.stderr}').trim();
          return VpnBackendResult(
            ok: false,
            message: msg.isEmpty ? 'UAC/PowerShell disconnect failed.' : msg,
          );
        }
      }

      // cleanup route best-effort
      final p = await _configPathForCleanup();
      if (p != null && p.trim().isNotEmpty && File(p).existsSync()) {
        await _removeEndpointBypassRouteFromConfig(p);
      }

      final on = await isConnected();
      if (on) {
        return const VpnBackendResult(ok: false, message: 'Service still RUNNING after stop.');
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Disconnect error: $e');
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

$text2 = $text.Substring(0, $beStart) + $newBackend
Set-Content -Encoding UTF8 -Path $main -Value $text2
Ok "BACKEND patched."

# ============================
# 5) BUILD + DEPLOY (optional)
# ============================
if ($SkipBuild) {
  Warn "SkipBuild is set. Patch done."
  exit 0
}

Info "flutter pub get..."
flutter pub get | Out-Host

Info "flutter clean..."
flutter clean | Out-Host

Info "flutter build windows --release..."
flutter build windows --release -t .\lib\main.dart | Out-Host

$release = Join-Path $proj "build\windows\x64\runner\Release"
if (!(Test-Path $release)) { throw "Release folder not found. Build failed. Expected: $release" }

if ($SkipDeploy) {
  Ok "Build OK: $release"
  exit 0
}

# deploy to non-OneDrive path to avoid file locks
Info "Deploying release to: $BuildRoot"
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

$dst = Join-Path $BuildRoot ("BlueVPN_" + $stamp)
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $release "*") -Destination $dst -Recurse -Force

$exe = Join-Path $dst "bluevpn.exe"
if (!(Test-Path $exe)) { throw "bluevpn.exe not found after deploy: $exe" }

# Desktop shortcut
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop "BlueVPN.lnk"
if (Test-Path $lnk) { Remove-Item $lnk -Force }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Ok "OK: Release deployed to: $dst"
Ok "OK: Shortcut updated:   $lnk"
Warn "Note: If ON/OFF asks for UAC, accept it (WireGuard service needs admin)."
