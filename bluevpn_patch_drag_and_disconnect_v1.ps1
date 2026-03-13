<# 
BlueVPN patch: backend disconnect hard-fix + toggle swipe support (best-effort)
Usage (from project root):
  powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_drag_and_disconnect_v1.ps1
Optional:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_drag_and_disconnect_v1.ps1 -SkipBuild

What it does:
  1) Backup lib\main.dart and windows\runner\Runner.exe.manifest
  2) Replace BACKEND (WIREGUARD FOR WINDOWS) block (to EOF) with a safer implementation:
       - disconnect() will STOP + UNINSTALL tunnel service (more reliable than stop-only)
       - endpoint bypass route delete/add is made more robust (deletes duplicates)
  3) Best-effort UI patch: adds onHorizontalDragEnd to the big toggle GestureDetector (swipe-to-toggle).
     If it can't patch safely, it prints a warning and continues.
  4) Runs .\bluevpn_build_release.ps1 unless -SkipBuild is set.
#>

param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Info($s){ Write-Host $s -ForegroundColor Cyan }
function Ok($s){ Write-Host $s -ForegroundColor Green }
function Warn($s){ Write-Host $s -ForegroundColor Yellow }
function Err($s){ Write-Host $s -ForegroundColor Red }

$proj = Join-Path $env:USERPROFILE "projects\bluevpn"
if (!(Test-Path $proj)) { throw "Project folder not found: $proj" }
Set-Location $proj

$main = Join-Path $proj "lib\main.dart"
$manifest = Join-Path $proj "windows\runner\Runner.exe.manifest"

if (!(Test-Path $main)) { throw "main.dart not found: $main" }

# Stop running app to avoid locks (ignore errors)
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# Backup
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $proj ("_patch_backup\\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Copy-Item $main (Join-Path $backupDir "main.dart") -Force
if (Test-Path $manifest) {
  Copy-Item $manifest (Join-Path $backupDir "Runner.exe.manifest") -Force
}
Ok "Backup created: $backupDir"

# Ensure safe manifest (asInvoker) - avoids mt.exe/LNK issues and keeps UAC only for admin actions.
Info "Writing safe Runner.exe.manifest (asInvoker)..."
$manifestText = @'
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

Set-Content -Encoding UTF8 -Path $manifest -Value $manifestText
Ok "Manifest updated."

# Ensure required imports (best-effort; only adds if missing)
Info "Ensuring required imports..."
$text = Get-Content -Raw -Encoding UTF8 $main

function Add-ImportIfMissing([string]$content, [string]$importLine) {
  if ($content -notmatch [regex]::Escape($importLine)) {
    # insert after the last dart: import
    $lines = $content -split "(`r`n|`n)"
    $lastDart = -1
    for ($i=0; $i -lt $lines.Length; $i++) {
      if ($lines[$i] -match "^\s*import\s+'dart:") { $lastDart = $i }
    }
    if ($lastDart -ge 0) {
      $before = $lines[0..$lastDart]
      $after = @()
      if ($lastDart + 1 -le $lines.Length - 1) { $after = $lines[($lastDart+1)..($lines.Length-1)] }
      $lines = @($before + @($importLine) + $after)
      return ($lines -join "`n")
    } else {
      return ($importLine + "`n" + $content)
    }
  }
  return $content
}

$text = Add-ImportIfMissing $text "import 'dart:convert';"
$text = Add-ImportIfMissing $text "import 'dart:typed_data';"
$text = Add-ImportIfMissing $text "import 'dart:io';"
Ok "Imports OK (ensured)."

# Replace BACKEND section (from marker to EOF)
Info "Patching BACKEND block (disconnect hard-fix)..."
$marker = "BACKEND (WIREGUARD FOR WINDOWS)"
$idx = $text.IndexOf($marker)
if ($idx -lt 0) { throw "BACKEND marker not found: $marker" }

# Find section header start ("/* =========================") before marker
$hdr = "/* ========================="
$beforeMarker = $text.Substring(0, $idx)
$start = $beforeMarker.LastIndexOf($hdr)
if ($start -lt 0) { throw "BACKEND header not found before marker." }

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
        reason: 'Web-режим: реальное подключение недоступно. Запусти как Windows-приложение.',
      );
    }
    if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason: 'Платформа не поддерживается (пока сделано под Windows).',
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

    candidates.add(r'C:\\Program Files\\WireGuard\\wireguard.exe');
    candidates.add(r'C:\\Program Files (x86)\\WireGuard\\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return 'wireguard.exe';
  }

  String get _serviceName => 'WireGuardTunnel\\$${tunnelName}';

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
    // Run innerScript with UAC using -EncodedCommand (UTF-16LE Base64)
    final encoded = base64.encode(_utf16le(innerScript));

    final outer = r'''
$ErrorActionPreference="Stop"
$enc="__ENC__"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-EncodedCommand",$enc
)
exit $p.ExitCode
'''.replaceAll('__ENC__', encoded);

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
        message: 'WireGuard не найден:\n$_exe\n\nУстанови WireGuard for Windows.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  static String? _extractEndpointIPv4(String cfg) {
    final re = RegExp(
      r'^\\s*Endpoint\\s*=\\s*([0-9]{1,3}(?:\\.[0-9]{1,3}){3})\\s*:\\s*\\d+\\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<void> _ensureEndpointBypassRoute(String configPath) async {
    // Add route to endpoint via current default gateway (prevents handshake going into tunnel)
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

# remove duplicates (route.exe deletes one at a time)
for ($i=0; $i -lt 10; $i++) {
  route.exe delete $ep | Out-Null
}

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

      final ps = r'''
$ErrorActionPreference="SilentlyContinue"
$ep="__EP__"
for ($i=0; $i -lt 10; $i++) {
  route.exe delete $ep | Out-Null
}
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

  Future<bool> _serviceExists() async {
    final res = await _run('sc', ['query', _serviceName]);
    final out = ('${res.stdout}\n${res.stderr}').toLowerCase();
    if (out.contains('1060')) return false;
    if (out.contains('не установ')) return false;
    return res.exitCode == 0;
  }

  static String? _extractConfPathFromScQc(String text) {
    final re = RegExp(r'([A-Za-z]:\\[^"\\r\\n]+\\.conf)', caseSensitive: false);
    final m = re.firstMatch(text);
    return m?.group(1);
  }

  static String _normPath(String p) =>
      p.trim().replaceAll('"', '').replaceAll('/', '\\').toLowerCase();

  Future<String?> _currentServiceConfigPath() async {
    final res = await _run('sc', ['qc', _serviceName]);
    if (res.exitCode != 0) return null;
    final out = ('${res.stdout}\n${res.stderr}').toString();
    return _extractConfPathFromScQc(out);
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
              ? 'Не удалось установить tunnel service.'
              : 'Не удалось установить tunnel service:\n$out',
        );
      }
      return const VpnBackendResult(ok: true);
    }

    final current = await _currentServiceConfigPath();
    if (current != null && _normPath(current) != _normPath(configPath)) {
      // service points to another .conf -> reinstall to our configPath
      await _run('sc', ['stop', _serviceName]);
      await _run(_exe, ['/uninstalltunnelservice', tunnelName]);

      final res = await _run(_exe, ['/installtunnelservice', configPath]);
      if (res.exitCode != 0) {
        final out = ('${res.stdout}\n${res.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: out.isEmpty
              ? 'Не удалось переустановить tunnel service.'
              : 'Не удалось переустановить tunnel service:\n$out',
        );
      }
    }

    return const VpnBackendResult(ok: true);
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
    return await _currentServiceConfigPath();
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

      final admin = await _isAdmin();
      if (admin) {
        final svcOk = await _ensureServiceInstalled(configPath);
        if (!svcOk.ok) return svcOk;

        await _run('sc', ['stop', _serviceName]);
        await Future.delayed(const Duration(milliseconds: 250));
        await _run('sc', ['start', _serviceName]);

        final running = await _waitForState('RUNNING', const Duration(seconds: 10));
        if (!running) {
          return const VpnBackendResult(
            ok: false,
            message: 'Сервис не вышел в RUNNING (проверь конфиг/Endpoint/AllowedIPs).',
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
'''.replaceAll('__EXE__', _exe)
  .replaceAll('__CFG__', configPath)
  .replaceAll('__TN__', tunnelName)
  .replaceAll('__SVC__', _serviceName);

      final pr = await _runElevatedPowerShell(inner);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: msg.isEmpty ? 'UAC/PowerShell ошибка подключения.' : msg,
        );
      }

      final running2 = await _waitForState('RUNNING', const Duration(seconds: 10));
      if (!running2) {
        return const VpnBackendResult(ok: false, message: 'Сервис не вышел в RUNNING после UAC.');
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Ошибка WireGuard: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    try {
      final p = await _configPathForCleanup();

      final admin = await _isAdmin();
      if (admin) {
        // Strong stop: uninstall tunnel service (stops it reliably)
        await _run('sc', ['stop', _serviceName]);
        await Future.delayed(const Duration(milliseconds: 300));
        await _run(_exe, ['/uninstalltunnelservice', tunnelName]);

        // wait until STOPPED OR service disappears
        await _waitForState('STOPPED', const Duration(seconds: 12));

        if (p != null && p.trim().isNotEmpty && File(p).existsSync()) {
          await _removeEndpointBypassRouteFromConfig(p);
        }

        final on = await isConnected();
        if (on) {
          return const VpnBackendResult(ok: false, message: 'Сервис всё ещё RUNNING после stop/uninstall.');
        }
        return const VpnBackendResult(ok: true);
      }

      // no admin -> UAC once (stop + uninstall)
      final inner = r'''
$ErrorActionPreference="Stop"
$exe="__EXE__"
$tn="__TN__"
$svc="__SVC__"

sc.exe stop $svc | Out-Null
Start-Sleep -Milliseconds 300
& $exe /uninstalltunnelservice $tn | Out-Null
'''.replaceAll('__EXE__', _exe)
  .replaceAll('__TN__', tunnelName)
  .replaceAll('__SVC__', _serviceName);

      final pr = await _runElevatedPowerShell(inner);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(ok: false, message: msg.isEmpty ? 'UAC/PowerShell ошибка отключения.' : msg);
      }

      // cleanup route best-effort (needs admin, so do it via UAC too)
      if (p != null && p.trim().isNotEmpty && File(p).existsSync()) {
        final rm = r'''
$ErrorActionPreference="SilentlyContinue"
$cfg="__CFG__"
if (!(Test-Path $cfg)) { exit 0 }
$txt = Get-Content -Raw -Encoding UTF8 $cfg
$ep = $null
if ($txt -match '^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') { $ep = $matches[1] }
if (-not $ep) { exit 0 }
for ($i=0; $i -lt 10; $i++) { route.exe delete $ep | Out-Null }
'''.replaceAll('__CFG__', p);

        await _runElevatedPowerShell(rm);
      }

      final on2 = await isConnected();
      if (on2) {
        return const VpnBackendResult(ok: false, message: 'Сервис всё ещё RUNNING после UAC stop/uninstall.');
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Ошибка отключения WireGuard: $e');
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

$text = $text.Substring(0, $start) + $newBackend
Ok "BACKEND patched."

# Best-effort: add swipe-to-toggle by injecting onHorizontalDragEnd next to onTap on the big toggle GestureDetector.
# It only patches if onTap uses a simple identifier (e.g., onTap: _toggleVpn,)
function Try-PatchToggleSwipe([string]$content) {
  if ($content -match "onHorizontalDragEnd\s*:") {
    return @{ Content = $content; Patched = $false; Note = "Swipe handler already exists (skipped)." }
  }

  $iconIdx = $content.IndexOf("Icons.pause")
  if ($iconIdx -lt 0) { $iconIdx = $content.IndexOf("Icons.play_arrow") }
  if ($iconIdx -lt 0) {
    return @{ Content = $content; Patched = $false; Note = "Toggle icons not found; can't auto-patch swipe." }
  }

  $windowStart = [Math]::Max(0, $iconIdx - 3000)
  $window = $content.Substring($windowStart, $iconIdx - $windowStart)

  $gdRel = $window.LastIndexOf("GestureDetector(")
  if ($gdRel -lt 0) {
    return @{ Content = $content; Patched = $false; Note = "GestureDetector near toggle not found; can't auto-patch swipe." }
  }
  $gdIdx = $windowStart + $gdRel

  # Search for onTap: IDENTIFIER, within the next 900 chars
  $aheadLen = [Math]::Min(900, $content.Length - $gdIdx)
  $ahead = $content.Substring($gdIdx, $aheadLen)

  $m = [regex]::Match($ahead, "onTap\s*:\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*,")
  if (-not $m.Success) {
    return @{ Content = $content; Patched = $false; Note = "onTap is not a simple identifier (probably inline closure); skip swipe patch." }
  }

  $tapExpr = $m.Groups[1].Value
  $insert = "onTap: $tapExpr,`n        onHorizontalDragEnd: (_) => $tapExpr(),"

  $patchedAhead = $ahead.Substring(0, $m.Index) + $insert + $ahead.Substring($m.Index + $m.Length)

  $newContent = $content.Substring(0, $gdIdx) + $patchedAhead + $content.Substring($gdIdx + $aheadLen)
  return @{ Content = $newContent; Patched = $true; Note = "Added onHorizontalDragEnd to toggle GestureDetector (swipe-to-toggle)." }
}

Info "Trying to enable swipe on the big toggle (best-effort)..."
$res = Try-PatchToggleSwipe $text
$text = $res.Content
if ($res.Patched) { Ok $res.Note } else { Warn $res.Note }

# Write patched main.dart
Set-Content -Path $main -Value $text -Encoding UTF8
Ok "Patched: lib\main.dart"

if ($SkipBuild) {
  Warn "SkipBuild set: patch done, build skipped."
  exit 0
}

# Build using existing build script (recommended; already proven working)
$buildScript = Join-Path $proj "bluevpn_build_release.ps1"
if (!(Test-Path $buildScript)) { throw "Build script not found: $buildScript" }

Info "Running build script: $buildScript"
powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript
Ok "DONE. Launch via Desktop shortcut: BlueVPN.lnk"
