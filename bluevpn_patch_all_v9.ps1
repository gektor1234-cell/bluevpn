# BlueVPN PATCH ALL v9
# - Safe Runner.exe.manifest (asInvoker)
# - Ensure required Dart imports
# - Patch CONFIG STORE (HIDDEN)
# - Patch BACKEND (WIREGUARD FOR WINDOWS)
# - Fix managedConfigPath() call sites -> managedConfigPath
# - Optional: build & deploy release + desktop shortcut
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v9.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v9.ps1 -SkipDeploy
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_all_v9.ps1 -SkipBuild
#
param(
  [string]$ProjectPath = "$env:USERPROFILE\projects\bluevpn",
  [string]$TunnelName = "BlueVPN",
  [switch]$SkipBuild,
  [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"

function Info { param([string]$s) Write-Host $s -ForegroundColor Cyan }
function Ok   { param([string]$s) Write-Host $s -ForegroundColor Green }
function Warn { param([string]$s) Write-Host $s -ForegroundColor Yellow }
function Err  { param([string]$s) Write-Host $s -ForegroundColor Red }

function Ensure-Dir {
  param([string]$Path)
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function Replace-Section {
  param(
    [string]$Text,
    [string]$Marker,
    [string]$NextMarker,
    [string]$NewBlock
  )

  $m = $Text.IndexOf($Marker)
  if ($m -lt 0) { throw "Marker not found: $Marker" }

  $start = $Text.LastIndexOf("/* =========================", $m)
  if ($start -lt 0) { throw "Section header not found before marker: $Marker" }

  if ([string]::IsNullOrWhiteSpace($NextMarker)) {
    # Replace to EOF
    return $Text.Substring(0, $start) + $NewBlock
  }

  $m2 = $Text.IndexOf($NextMarker, $m)
  if ($m2 -lt 0) { throw "Next marker not found: $NextMarker" }

  $start2 = $Text.LastIndexOf("/* =========================", $m2)
  if ($start2 -lt 0 -or $start2 -le $start) { throw "Next section header not found: $NextMarker" }

  return $Text.Substring(0, $start) + $NewBlock + $Text.Substring($start2)
}

function Ensure-Import {
  param(
    [string]$Text,
    [string]$ImportLine
  )
  if ($Text.Contains($ImportLine)) { return $Text }

  $firstImport = $Text.IndexOf("import '")
  if ($firstImport -lt 0) {
    return $ImportLine + "`r`n" + $Text
  }

  return $Text.Substring(0, $firstImport) + $ImportLine + "`r`n" + $Text.Substring($firstImport)
}

function Run-Step {
  param([string]$Title, [string]$Exe, [string[]]$ArgList)

  Info $Title
  $out = & $Exe @ArgList 2>&1 | Out-String
  if ($out.Trim().Length -gt 0) { $out.TrimEnd() | Out-Host }

  $code = $LASTEXITCODE
  if ($code -ne 0) {
    throw ("Command failed (exit {0}): {1} {2}" -f $code, $Exe, ($ArgList -join ' '))
  }

  # Extra safety: if Flutter prints global help, treat it as failure (usually means args weren't passed correctly).
  if ($Title -like "flutter *" -and $out -match "Usage:\s+flutter\s+<command>\s+\[arguments\]") {
    throw ("Flutter printed help instead of running a command. Check argument passing. Tried: flutter {0}" -f ($ArgList -join ' '))
  }
}



function Find-ReleaseFolder {
  param([string]$Proj)
  $c1 = Join-Path $Proj "build\windows\x64\runner\Release"
  if (Test-Path $c1) { return $c1 }

  $c2 = Join-Path $Proj "build\windows\runner\Release"
  if (Test-Path $c2) { return $c2 }

  # fallback: search for bluevpn.exe under build\windows
  $root = Join-Path $Proj "build\windows"
  if (Test-Path $root) {
    $exe = Get-ChildItem -Path $root -Recurse -Filter "bluevpn.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe -and $exe.Directory -and (Test-Path $exe.Directory.FullName)) {
      return $exe.Directory.FullName
    }
  }

  return $null
}

function Create-Shortcut {
  param(
    [string]$ShortcutPath,
    [string]$TargetPath,
    [string]$WorkingDirectory
  )
  $wsh = New-Object -ComObject WScript.Shell
  $sc = $wsh.CreateShortcut($ShortcutPath)
  $sc.TargetPath = $TargetPath
  $sc.WorkingDirectory = $WorkingDirectory
  $sc.IconLocation = "$TargetPath,0"
  $sc.Save()
}

# ============================
# MAIN
# ============================
Info "== BlueVPN PATCH ALL v9 =="
Info ("Project: " + $ProjectPath)

if (!(Test-Path $ProjectPath)) { throw "ProjectPath not found: $ProjectPath" }
Set-Location $ProjectPath

$main = Join-Path $ProjectPath "lib\main.dart"
$manifest = Join-Path $ProjectPath "windows\runner\Runner.exe.manifest"

if (!(Test-Path $main)) { throw "main.dart not found: $main" }

# Stop running app to avoid locks (ignore errors)
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# Backup
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $ProjectPath ("_patch_backup\" + $stamp)
Ensure-Dir $backupDir

Copy-Item $main (Join-Path $backupDir "main.dart") -Force
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $backupDir "Runner.exe.manifest") -Force }

Ok ("Backup created: " + $backupDir)

# 1) Safe manifest (asInvoker) to avoid mt.exe / LNK1327 issues
Info "Writing safe Runner.exe.manifest (asInvoker)..."
Ensure-Dir (Split-Path -Parent $manifest)

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

# Load main.dart
$text = Get-Content -Raw -Encoding UTF8 $main

# 2) Ensure imports required by backend + UAC helper
Info "Ensuring required imports..."
$text = Ensure-Import -Text $text -ImportLine "import 'dart:convert';"
$text = Ensure-Import -Text $text -ImportLine "import 'dart:typed_data';"
$text = Ensure-Import -Text $text -ImportLine "import 'dart:io';"
Set-Content -Encoding UTF8 -Path $main -Value $text
Ok "Imports OK."

# Reload after import edits
$text = Get-Content -Raw -Encoding UTF8 $main

# 3) Patch CONFIG STORE block
Info "Patching CONFIG STORE block..."

$newConfigStore = @'
/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  // Managed config path. Stored in ProgramData so the WireGuard service (LocalSystem) can read it.
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

$text = Replace-Section -Text $text -Marker "CONFIG STORE (HIDDEN)" -NextMarker "AUTH UI" -NewBlock $newConfigStore
Set-Content -Encoding UTF8 -Path $main -Value $text
Ok "CONFIG STORE patched."

# Reload after config store patch
$text = Get-Content -Raw -Encoding UTF8 $main

# 4) Patch BACKEND block (replace to EOF)
Info "Patching BACKEND block..."

# Backend uses TunnelName constant from your app. We keep it as-is inside Dart (it comes from UI code).
# IMPORTANT: This block expects a string tunnelName passed to VpnBackend.createDefault(...)

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

  String get _serviceName => 'WireGuardTunnel\$$tunnelName';

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
    // Use -EncodedCommand (UTF-16LE Base64) to avoid quote escaping issues.
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

    return _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', outer]);
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
    // Add route to Endpoint via current default gateway to prevent handshake going into tunnel.
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

      await _run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps]);
    } catch (_) {}
  }

  Future<void> _removeEndpointBypassRouteFromConfig(String configPath) async {
    try {
      final cfg = await File(configPath).readAsString();
      final ep = _extractEndpointIPv4(cfg);
      if (ep == null || ep.trim().isEmpty) return;
      await _run('route', ['delete', ep]);
    } catch (_) {}
  }

  Future<bool> _serviceExists() async {
    final res = await _run('sc', ['query', _serviceName]);
    final out = ('${res.stdout}\n${res.stderr}').toLowerCase();
    if (out.contains('1060')) return false;
    if (out.contains('не установ')) return false;
    return res.exitCode == 0;
  }

  static String? _extractConfPathFromScQc(String text) {
    final re = RegExp(r'([A-Za-z]:\\[^"\r\n]+\.conf)', caseSensitive: false);
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
              ? 'Failed to install tunnel service.'
              : 'Failed to install tunnel service:\n$out',
        );
      }
      return const VpnBackendResult(ok: true);
    }

    final current = await _currentServiceConfigPath();
    if (current != null && _normPath(current) != _normPath(configPath)) {
      await _run('sc', ['stop', _serviceName]);
      await _run(_exe, ['/uninstalltunnelservice', tunnelName]);

      final res = await _run(_exe, ['/installtunnelservice', configPath]);
      if (res.exitCode != 0) {
        final out = ('${res.stdout}\n${res.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: out.isEmpty
              ? 'Failed to reinstall tunnel service.'
              : 'Failed to reinstall tunnel service:\n$out',
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

        final running = await _waitForState('RUNNING', const Duration(seconds: 6));
        if (!running) {
          return const VpnBackendResult(
            ok: false,
            message: 'Service did not reach RUNNING. Check config/Endpoint/AllowedIPs.',
          );
        }
        return const VpnBackendResult(ok: true);
      }

      // No admin -> elevate once (UAC)
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
'''
          .replaceAll('__EXE__', _exe.replaceAll('"', ''))
          .replaceAll('__CFG__', configPath.replaceAll('"', ''))
          .replaceAll('__TN__', tunnelName.replaceAll('"', ''))
          .replaceAll('__SVC__', _serviceName.replaceAll('"', ''));

      final pr = await _runElevatedPowerShell(ps);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(
          ok: false,
          message: msg.isEmpty ? 'UAC/PowerShell connect failed.' : msg,
        );
      }

      final running2 = await _waitForState('RUNNING', const Duration(seconds: 6));
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
          await _waitForState('STOPPED', const Duration(seconds: 6));
        }
      } else {
        final ps = r'''
$ErrorActionPreference="Stop"
$svc="__SVC__"
sc.exe stop $svc | Out-Null
'''.replaceAll('__SVC__', _serviceName.replaceAll('"', ''));

        final pr = await _runElevatedPowerShell(ps);
        if (pr.exitCode != 0) {
          final msg = ('${pr.stdout}\n${pr.stderr}').trim();
          return VpnBackendResult(
            ok: false,
            message: msg.isEmpty ? 'UAC/PowerShell disconnect failed.' : msg,
          );
        }
      }

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

$text = Replace-Section -Text $text -Marker "BACKEND (WIREGUARD FOR WINDOWS)" -NextMarker "" -NewBlock $newBackend

# 5) Fix call sites: managedConfigPath() -> managedConfigPath (property)
# (This is safe even if there are no matches.)
$replaced = ([regex]::Matches($text, "managedConfigPath\(\)")).Count
$text = [regex]::Replace($text, "managedConfigPath\(\)", "managedConfigPath")
Set-Content -Encoding UTF8 -Path $main -Value $text
Ok ("BACKEND patched. managedConfigPath() fixed: " + $replaced)

# ============================
# BUILD + DEPLOY (optional)
# ============================
if ($SkipBuild) {
  Warn "SkipBuild set: patch done, build skipped."
  exit 0
}

Run-Step -Title "flutter pub get..." -Exe "flutter" -Args @("pub","get")
Run-Step -Title "flutter clean..." -Exe "flutter" -Args @("clean")
Run-Step -Title "flutter build windows --release..." -Exe "flutter" -Args @("build","windows","--release","-t",".\lib\main.dart")

$release = Find-ReleaseFolder -Proj $ProjectPath
if (-not $release) {
  throw "Release folder not found. Build failed."
}
Ok ("Build OK: " + $release)

if ($SkipDeploy) {
  Warn "SkipDeploy set: build done, deploy skipped."
  exit 0
}

Info "Deploying..."
$dstRoot = "C:\BlueVPN_Builds"
Ensure-Dir $dstRoot
$dst = Join-Path $dstRoot ("BlueVPN_" + $stamp)
Ensure-Dir $dst

Copy-Item -Path (Join-Path $release "*") -Destination $dst -Recurse -Force

$exePath = Join-Path $dst "bluevpn.exe"
if (!(Test-Path $exePath)) { throw "bluevpn.exe not found after deploy: $exePath" }

$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop "BlueVPN.lnk"
if (Test-Path $lnk) { Remove-Item $lnk -Force }

Create-Shortcut -ShortcutPath $lnk -TargetPath $exePath -WorkingDirectory $dst

Ok ("OK: Release deployed to: " + $dst)
Ok ("OK: Shortcut updated:   " + $lnk)
Warn "Note: If ON/OFF asks for UAC, accept it (WireGuard service needs admin)."
