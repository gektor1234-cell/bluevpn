<# 
fix_vpn_toggle.ps1
BlueVPN: делает кнопку ВКЛ/ВЫКЛ реально рабочей на Windows (WireGuard service),
и переводит managed-конфиг в C:\ProgramData\BlueVPN\BlueVPN.conf.

Что делает:
- Бэкапит lib\main.dart и windows\runner\Runner.exe.manifest
- Переопределяет блок CONFIG STORE (HIDDEN) -> ProgramData
- Переопределяет блок BACKEND (WIREGUARD FOR WINDOWS) (start/stop service + route bypass)
- Ставит requireAdministrator в manifest (заменой level)
- Собирает Release и раскладывает на Desktop\BlueVPN + обновляет ярлык

Запуск:
cd "$env:USERPROFILE\projects\bluevpn"
powershell -ExecutionPolicy Bypass -File .\fix_vpn_toggle.ps1
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function _Stop-BlueVPN {
  Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
}

function _Replace-Once([string]$text, [string]$pattern, [string]$replacement, [string]$errMsg) {
  $re = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $re.IsMatch($text)) { throw $errMsg }
  return $re.Replace($text, $replacement, 1)
}

$proj = Join-Path $env:USERPROFILE "projects\bluevpn"
if (-not (Test-Path $proj)) { throw "Проект не найден: $proj" }
Set-Location $proj

_Stop-BlueVPN

$main = ".\lib\main.dart"
if (-not (Test-Path $main)) { throw "Не найден файл: $main" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item $main "$main.bak_$stamp" -Force

$text = Get-Content -Raw -Encoding UTF8 $main

# -----------------------------
# PATCH 1: CONFIG STORE -> ProgramData
# -----------------------------
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

  Future<String> managedConfigPath() async {
    // Храним конфиг так, чтобы его мог читать service под LocalSystem
    final dir = Directory('${_programData()}\\BlueVPN');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}\\$kTunnelName.conf';
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

# Вырезаем старый блок CONFIG STORE до маркера AUTH UI (маркер оставляем)
$cfgPattern = '(?s)/\* =========================\s*CONFIG STORE \(HIDDEN\)\s*========================= \*/.*?/\* =========================\s*AUTH UI\s*========================= \*/'
$authMarker = "/* =========================`r`n   AUTH UI`r`n   ========================= */"
$text = _Replace-Once $text $cfgPattern ($newCfgBlock + $authMarker) "Не найдено место для замены блока CONFIG STORE (HIDDEN) -> AUTH UI"

# -----------------------------
# PATCH 2: BACKEND (реальный start/stop WG-сервиса + bypass route)
# -----------------------------
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
        reason: 'Web-режим: реальное подключение недоступно. Запусти как Windows.',
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

  // Чтобы убирать endpoint-route при disconnect(), запоминаем последний конфиг
  String? _lastConfigPath;

  WireGuardWindowsBackend({required this.tunnelName})
      : _exe = _resolveWireGuardExe();

  /// Иногда UI/диагностика обращаются к этому геттеру (поэтому он есть).
  String? get configPath => _lastConfigPath;

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
    // BUILTIN\Administrators SID = S-1-5-32-544
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
    final re = RegExp(
      r'^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<void> _ensureEndpointBypassRoute(String configPath) async {
    // Критично для full-tunnel: Endpoint не должен пойти через сам VPN.
    // Добавляем временный маршрут на Endpoint через текущий default gateway.
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

  Future<void> _removeEndpointBypassRoute(String configPath) async {
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
    if (res.exitCode != 0) return false;
    if (out.contains('1060')) return false;
    if (out.contains('не установлен') || out.contains('не установлена')) return false;
    return true;
  }

  static String? _extractConfPathFromScQc(String text) {
    final re = RegExp(r'([A-Za-z]:\\[^"\r\n]+\.conf)', caseSensitive: false);
    final m = re.firstMatch(text);
    return m?.group(1);
  }

  static String _normPath(String p) {
    return p.trim().replaceAll('"', '').replaceAll('/', '\\').toLowerCase();
  }

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
          message: out.isEmpty ? 'Не удалось установить tunnel service.' : out,
        );
      }
      return const VpnBackendResult(ok: true);
    }

    // Если сервис есть, но смотрит на другой .conf — переустановим.
    final current = await _currentServiceConfigPath();
    if (current != null && _normPath(current) != _normPath(configPath)) {
      await _run('sc', ['stop', _serviceName]);
      await _run(_exe, ['/uninstalltunnelservice', tunnelName]);

      final res = await _run(_exe, ['/installtunnelservice', configPath]);
      if (res.exitCode != 0) {
        final out = ('${res.stdout}\n${res.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: out.isEmpty ? 'Не удалось переустановить tunnel service.' : out,
        );
      }
    }

    return const VpnBackendResult(ok: true);
  }

  Future<void> _stopServiceQuiet() async {
    await _run('sc', ['stop', _serviceName]);
  }

  Future<void> _startServiceQuiet() async {
    await _run('sc', ['start', _serviceName]);
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
    return _currentServiceConfigPath();
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    _lastConfigPath = configPath;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(ok: false, message: 'Конфиг не найден:\n$configPath');
    }

    final admin = await _isAdmin();
    if (!admin) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Нужны права администратора.\nЗакрой приложение и запусти BlueVPN от имени администратора.',
      );
    }

    try {
      await _ensureEndpointBypassRoute(configPath);

      final svcOk = await _ensureServiceInstalled(configPath);
      if (!svcOk.ok) return svcOk;

      // stop/start, чтобы гарантированно перечитать конфиг
      await _stopServiceQuiet();
      await Future.delayed(const Duration(milliseconds: 250));
      await _startServiceQuiet();

      final running = await _waitForState('RUNNING', const Duration(seconds: 8));
      if (!running) {
        return const VpnBackendResult(
          ok: false,
          message:
              'Сервис не вышел в RUNNING.\nПроверь Endpoint/AllowedIPs/DNS в конфиге и доступность сервера.',
        );
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

    final admin = await _isAdmin();
    if (!admin) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Нужны права администратора.\nЗакрой приложение и запусти BlueVPN от имени администратора.',
      );
    }

    try {
      if (await _serviceExists()) {
        await _stopServiceQuiet();
        await _waitForState('STOPPED', const Duration(seconds: 8));
      }

      final p = await _configPathForCleanup();
      if (p != null && p.trim().isNotEmpty && File(p).existsSync()) {
        await _removeEndpointBypassRoute(p);
      }

      final on = await isConnected();
      if (on) {
        return const VpnBackendResult(
          ok: false,
          message: 'Сервис всё ещё RUNNING после stop.',
        );
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

$backendPattern = '(?s)/\* =========================\s*BACKEND \(WIREGUARD FOR WINDOWS\)\s*========================= \*/.*\z'
$text = _Replace-Once $text $backendPattern $newBackend "Не найден блок BACKEND (WIREGUARD FOR WINDOWS) для замены (должен быть внизу main.dart)"

Set-Content -Path $main -Value $text -Encoding UTF8

# -----------------------------
# PATCH 3: manifest -> requireAdministrator (без полного перезаписывания файла)
# -----------------------------
$manifest = ".\windows\runner\Runner.exe.manifest"
if (Test-Path $manifest) {
  Copy-Item $manifest "$manifest.bak_$stamp" -Force
  $m = Get-Content -Raw -Encoding UTF8 $manifest
  if ($m -match "requestedExecutionLevel") {
    $m2 = [regex]::Replace($m, 'requestedExecutionLevel\s+level="[^"]+"', 'requestedExecutionLevel level="requireAdministrator"', 1)
    Set-Content -Path $manifest -Encoding UTF8 -Value $m2
  } else {
    Write-Warning "В manifest не найден requestedExecutionLevel — пропускаю."
  }
} else {
  Write-Warning "Manifest не найден: $manifest (пропускаю)"
}

# -----------------------------
# BUILD
# -----------------------------
flutter clean
flutter pub get
flutter build windows --release -t .\lib\main.dart

$src = Join-Path (Get-Location) "build\windows\x64\runner\Release"
if (-not (Test-Path $src)) { throw "Release папка не найдена: $src" }

# -----------------------------
# DEPLOY to Desktop
# -----------------------------
_Stop-BlueVPN

$desktop = [Environment]::GetFolderPath('Desktop')
$dst = Join-Path $desktop "BlueVPN"

# иногда OneDrive/процесс держит файлы — сделаем несколько попыток удаления
if (Test-Path $dst) {
  for ($i=0; $i -lt 5; $i++) {
    try {
      Remove-Item $dst -Recurse -Force -ErrorAction Stop
      break
    } catch {
      Start-Sleep -Milliseconds 700
    }
  }
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $src "*") -Destination $dst -Recurse -Force

$exe = Join-Path $dst "bluevpn.exe"
if (-not (Test-Path $exe)) { throw "Не найден exe после копирования: $exe" }

$lnk = Join-Path $desktop "BlueVPN.lnk"
if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Write-Host ""
Write-Host "✅ Готово!" -ForegroundColor Green
Write-Host "Папка: $dst" -ForegroundColor Green
Write-Host "Ярлык: $lnk" -ForegroundColor Green
Write-Host "Managed конфиг: C:\ProgramData\BlueVPN\BlueVPN.conf" -ForegroundColor Green
