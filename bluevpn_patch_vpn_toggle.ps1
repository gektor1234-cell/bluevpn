#requires -version 5.1
<#
BlueVPN patcher:
- Fix BACKEND (WireGuard for Windows): real connect/disconnect via WireGuard tunnel service + endpoint bypass route
- Write safe Runner.exe.manifest (asInvoker) to avoid mt.exe/LNK1327 issues
- Build Windows Release and deploy to %LOCALAPPDATA%\BlueVPN\Builds\BlueVPN_<timestamp>
- Create Desktop shortcut BlueVPN.lnk to the latest build

Run:
  cd "$env:USERPROFILE\projects\bluevpn"
  powershell -ExecutionPolicy Bypass -File .\bluevpn_patch_vpn_toggle.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Info($s) { Write-Host $s -ForegroundColor Cyan }
function Ok($s)   { Write-Host $s -ForegroundColor Green }
function Warn($s) { Write-Host $s -ForegroundColor Yellow }
function Err($s)  { Write-Host $s -ForegroundColor Red }

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

Info "== BlueVPN patcher =="

# --- project root (script must be inside project root) ---
$proj = (Get-Location).Path
if (!(Test-Path (Join-Path $proj "pubspec.yaml"))) {
  # fallback: if script executed from another dir, try its folder
  $proj = Split-Path -Parent $MyInvocation.MyCommand.Path
  Set-Location $proj
}

$main     = Join-Path $proj "lib\main.dart"
$manifest = Join-Path $proj "windows\runner\Runner.exe.manifest"

if (!(Test-Path $main)) {
  throw "main.dart not found: $main (run script from project root)"
}

# --- stop running app to avoid file locks ---
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# --- backup ---
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $proj ("_patch_backups\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Copy-Item $main (Join-Path $backupDir "main.dart") -Force
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $backupDir "Runner.exe.manifest") -Force }

Ok "Backup saved: $backupDir"

# =========================
# 1) Safe manifest (asInvoker) to avoid mt.exe/LNK1327 issues
# =========================
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

# Ensure folder exists
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifest) | Out-Null
Write-Utf8NoBom -Path $manifest -Text $manifestXml
Ok "Manifest updated: $manifest"

# =========================
# 2) Patch BACKEND section in lib/main.dart (replace from BACKEND header to EOF)
# =========================
Info "Patching BACKEND block in lib/main.dart ..."
$text = Get-Content -Raw -Encoding UTF8 $main

$beKey = $text.IndexOf("BACKEND (WIREGUARD FOR WINDOWS)")
if ($beKey -lt 0) { throw "BACKEND marker not found in main.dart" }

$beStart = $text.LastIndexOf("/* =========================", $beKey)
if ($beStart -lt 0) { throw "BACKEND section header not found (/* =========================)" }

# --- NEW BACKEND (Dart) ---
# NOTE: This block intentionally contains ONLY Dart code; no PowerShell.
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
        reason: 'Web-режим: реальное подключение VPN недоступно. Запусти как Windows-приложение.',
      );
    }
    if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason: 'Платформа не поддерживается (backend реализован только для Windows).',
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

  // Optional (some parts of UI/code may reference it)
  String get configPath => _lastConfigPath ?? '';

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
    // fallback if in PATH
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

  Future<VpnBackendResult> _ensureWireGuardPresent() async {
    final isAbs = _exe.contains(':\\') || _exe.startsWith(r'\\');
    if (isAbs && !File(_exe).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message:
            'WireGuard не найден по пути:\n$_exe\n\nУстанови WireGuard for Windows и попробуй снова.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  static String? _extractEndpointIPv4(String cfg) {
    // Endpoint = 1.2.3.4:51820
    final re = RegExp(
      r'^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<ProcessResult> _runElevatedPsScript(String psScript) async {
    // Write inner script to temp file, then Start-Process powershell -Verb RunAs -File <script>
    final tmp = await Directory.systemTemp.createTemp('bluevpn_');
    final scriptFile = File('${tmp.path}\\bluevpn_admin.ps1');
    await scriptFile.writeAsString(psScript, flush: true);

    final fp = scriptFile.path.replaceAll("'", "''"); // PS single-quote escape

    final outer = '''
$ErrorActionPreference="Stop"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-File",
  '$fp'
)
exit $p.ExitCode
''';

    final res = await _run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      outer,
    ]);

    // Best-effort cleanup
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}

    return res;
  }

  Future<VpnBackendResult> _ensureEndpointBypassRoute(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return const VpnBackendResult(ok: true);

      final ps = '''
$ErrorActionPreference="SilentlyContinue"
$cfg = '${configPath.replaceAll("'", "''")}'
if (!(Test-Path $cfg)) { exit 0 }

$txt = Get-Content -Raw -Encoding UTF8 $cfg

$ep = $null
if ($txt -match '^\\s*Endpoint\\s*=\\s*([0-9]{1,3}(?:\\.[0-9]{1,3}){3})\\s*:\\s*\\d+\\s*$') {
  $ep = $matches[1]
}
if (-not $ep) { exit 0 }

$rt = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
$gw = $rt.NextHop
if (-not $gw -or $gw -eq "0.0.0.0") { exit 0 }

route.exe delete $ep | Out-Null
route.exe add $ep mask 255.255.255.255 $gw metric 1 | Out-Null
''';

      final admin = await _isAdmin();
      if (admin) {
        // run directly (already admin)
        await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps]);
        return const VpnBackendResult(ok: true);
      }

      final r = await _runElevatedPsScript(ps);
      if (r.exitCode == 0) return const VpnBackendResult(ok: true);

      final combined = ('${r.stdout}\n${r.stderr}').trim();
      final msg = combined.isNotEmpty
          ? combined
          : (r.exitCode == 1223
              ? 'UAC отменён пользователем (код 1223).'
              : 'Не удалось добавить route на Endpoint (код ${r.exitCode}).');
      return VpnBackendResult(ok: false, message: msg);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Ошибка route/Endpoint: $e');
    }
  }

  Future<void> _removeEndpointBypassRoute(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return;

      final ps = '''
$ErrorActionPreference="SilentlyContinue"
$ep='${ep.replaceAll("'", "''")}'
route.exe delete $ep | Out-Null
''';

      final admin = await _isAdmin();
      if (admin) {
        await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps]);
      } else {
        await _runElevatedPsScript(ps);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<VpnBackendResult> _installAndStartService(String configPath) async {
    // Always (re)install to ensure service points to this configPath.
    final exe = _exe;
    final tn = tunnelName;
    final svc = _serviceName;

    final ps = '''
$ErrorActionPreference="Stop"
$exe='${exe.replaceAll("'", "''")}'
$cfg='${configPath.replaceAll("'", "''")}'
$tn='${tn.replaceAll("'", "''")}'
$svc='${svc.replaceAll("'", "''")}'

sc.exe stop $svc | Out-Null

# reinstall tunnel service (ignore uninstall errors)
& $exe /uninstalltunnelservice $tn | Out-Null
& $exe /installtunnelservice $cfg | Out-Null

sc.exe start $svc | Out-Null
''';

    final admin = await _isAdmin();
    if (admin) {
      final r = await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps]);
      if (r.exitCode == 0) return const VpnBackendResult(ok: true);

      final combined = ('${r.stdout}\n${r.stderr}').trim();
      return VpnBackendResult(ok: false, message: combined.isEmpty ? 'Ошибка установки/старта сервиса.' : combined);
    }

    final r2 = await _runElevatedPsScript(ps);
    if (r2.exitCode == 0) return const VpnBackendResult(ok: true);

    final combined2 = ('${r2.stdout}\n${r2.stderr}').trim();
    final msg2 = combined2.isNotEmpty
        ? combined2
        : (r2.exitCode == 1223
            ? 'UAC отменён пользователем (код 1223).'
            : 'Не удалось установить/запустить сервис WireGuard (код ${r2.exitCode}).');
    return VpnBackendResult(ok: false, message: msg2);
  }

  Future<VpnBackendResult> _stopService() async {
    final svc = _serviceName;
    final ps = '''
$ErrorActionPreference="Stop"
$svc='${svc.replaceAll("'", "''")}'
sc.exe stop $svc | Out-Null
''';

    final admin = await _isAdmin();
    if (admin) {
      final r = await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps]);
      if (r.exitCode == 0) return const VpnBackendResult(ok: true);

      final combined = ('${r.stdout}\n${r.stderr}').trim();
      return VpnBackendResult(ok: false, message: combined.isEmpty ? 'Ошибка остановки сервиса.' : combined);
    }

    final r2 = await _runElevatedPsScript(ps);
    if (r2.exitCode == 0) return const VpnBackendResult(ok: true);

    final combined2 = ('${r2.stdout}\n${r2.stderr}').trim();
    final msg2 = combined2.isNotEmpty
        ? combined2
        : (r2.exitCode == 1223
            ? 'UAC отменён пользователем (код 1223).'
            : 'Не удалось остановить сервис WireGuard (код ${r2.exitCode}).');
    return VpnBackendResult(ok: false, message: msg2);
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

  String? _configPathForCleanup() {
    final p = _lastConfigPath;
    if (p != null && p.trim().isNotEmpty) return p;
    return null;
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    _lastConfigPath = configPath;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(ok: false, message: 'Конфиг не найден:\n$configPath');
    }

    // 1) route to endpoint (prevents handshake going into the tunnel)
    final routeOk = await _ensureEndpointBypassRoute(configPath);
    if (!routeOk.ok) return routeOk;

    // 2) (re)install service + start
    final svcOk = await _installAndStartService(configPath);
    if (!svcOk.ok) return svcOk;

    // 3) wait RUNNING
    final running = await _waitForState('RUNNING', const Duration(seconds: 8));
    if (!running) {
      return const VpnBackendResult(
        ok: false,
        message: 'Сервис не вышел в RUNNING.\nПроверь Endpoint/AllowedIPs/DNS в конфиге.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    // 1) stop service
    final stopOk = await _stopService();
    if (!stopOk.ok) return stopOk;

    final stopped = await _waitForState('STOPPED', const Duration(seconds: 8));
    if (!stopped) {
      // not critical but tell user
      return const VpnBackendResult(ok: false, message: 'Пытался выключить, но сервис не вышел в STOPPED.');
    }

    // 2) remove endpoint route best-effort
    final p = _configPathForCleanup();
    if (p != null && File(p).existsSync()) {
      await _removeEndpointBypassRoute(p);
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

$text2 = $text.Substring(0, $beStart) + $newBackend
Write-Utf8NoBom -Path $main -Text $text2
Ok "BACKEND patched."

# =========================
# 3) Build Release
# =========================
Info "flutter pub get ..."
flutter pub get | Out-Host

Info "flutter clean ..."
flutter clean | Out-Host

Info "flutter build windows --release -t .\lib\main.dart ..."
flutter build windows --release -t .\lib\main.dart | Out-Host

$src = Join-Path $proj "build\windows\x64\runner\Release"
if (!(Test-Path $src)) { throw "Release folder not found: $src" }

# =========================
# 4) Deploy (NOT to Desktop/OneDrive to avoid locks). Use %LOCALAPPDATA%
# =========================
$dst = Join-Path $env:LOCALAPPDATA ("BlueVPN\Builds\BlueVPN_" + $stamp)
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $src "*") -Destination $dst -Recurse -Force

$exe = Join-Path $dst "bluevpn.exe"
if (!(Test-Path $exe)) { throw "bluevpn.exe not found in: $dst" }

# =========================
# 5) Desktop shortcut BlueVPN.lnk -> latest build
# =========================
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop "BlueVPN.lnk"

try {
  if (Test-Path $lnk) { Remove-Item $lnk -Force }
} catch {}

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Ok "DONE."
Ok "Build folder: $dst"
Ok "Shortcut: $lnk"
Warn "Если при нажатии ВКЛ/ВЫКЛ попросит UAC — это нормально (нужны права для WireGuard service и route)."
