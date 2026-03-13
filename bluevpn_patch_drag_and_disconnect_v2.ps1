# BlueVPN patch: fix BACKEND service name ($), stronger disconnect, enable swipe-to-toggle (best-effort)
# Works in: PowerShell 5+ on Windows
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_drag_and_disconnect_v2.ps1
# Optional:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_patch_drag_and_disconnect_v2.ps1 -SkipBuild
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Info($s){ Write-Host $s -ForegroundColor Cyan }
function Ok($s){ Write-Host $s -ForegroundColor Green }
function Warn($s){ Write-Host $s -ForegroundColor Yellow }

Info "== BlueVPN PATCH drag+disconnect v2 =="

$proj = Join-Path $env:USERPROFILE "projects\bluevpn"
if (!(Test-Path $proj)) { throw "Project folder not found: $proj" }
Set-Location $proj
Info "Project: $proj"

$main = Join-Path $proj "lib\main.dart"
if (!(Test-Path $main)) { throw "main.dart not found: $main" }

# --- backup ---
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $proj ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item $main (Join-Path $backupDir "main.dart") -Force

$manifest = Join-Path $proj "windows\runner\Runner.exe.manifest"
if (Test-Path $manifest) { Copy-Item $manifest (Join-Path $backupDir "Runner.exe.manifest") -Force }

Ok "Backup created: $backupDir"

# --- safe manifest (asInvoker) ---
Info "Writing safe Runner.exe.manifest (asInvoker)..."
New-Item -ItemType Directory -Force -Path (Split-Path $manifest -Parent) | Out-Null
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

# --- read main.dart ---
$text = Get-Content -Raw -Encoding UTF8 $main

# --- ensure imports ---
Info "Ensuring required imports..."
$need = @(
  "import 'dart:convert';",
  "import 'dart:io';",
  "import 'dart:typed_data';"
)

$missing = @()
foreach ($i in $need) {
  if ($text -notmatch [regex]::Escape($i)) { $missing += $i }
}

if ($missing.Count -gt 0) {
  # insert before first non-comment, non-empty line that is not an import (or at top)
  $lines = $text -split "`r?`n", 0, "RegexMatch"
  $insertAt = 0

  for ($k=0; $k -lt $lines.Length; $k++) {
    $ln = $lines[$k].Trim()
    if ($ln -eq "") { continue }
    if ($ln.StartsWith("//")) { continue }
    if ($ln.StartsWith("/*")) { continue }
    if ($ln.StartsWith("*")) { continue }
    if ($ln.StartsWith("*/")) { continue }
    $insertAt = $k
    break
  }

  $newLines = @()
  for ($k=0; $k -lt $insertAt; $k++) { $newLines += $lines[$k] }
  foreach ($m in $missing) { $newLines += $m }
  for ($k=$insertAt; $k -lt $lines.Length; $k++) { $newLines += $lines[$k] }

  $text = ($newLines -join "`r`n")
  Ok ("Added missing imports: " + ($missing -join ", "))
} else {
  Ok "Imports OK."
}

# --- patch BACKEND block (replace from section header before marker to EOF) ---
Info "Patching BACKEND block..."

$marker = "BACKEND (WIREGUARD FOR WINDOWS)"
$beKey = $text.IndexOf($marker)
if ($beKey -lt 0) { throw "BACKEND marker not found: $marker" }

$beStart = $text.LastIndexOf("/* =========================", $beKey)
if ($beStart -lt 0) { throw "BACKEND section header not found before marker." }

# New BACKEND (Dart) - includes:
# - correct serviceName (no $ interpolation issue)
# - connect: add endpoint bypass route + reinstall tunnel service + start + wait RUNNING (via UAC)
# - disconnect: stop + wait + uninstall + force-kill tunnelservice wireguard.exe if needed + cleanup endpoint route
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
        reason: 'Web mode: VPN backend is not available.',
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

  // remember last configPath for cleanup (route removal)
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

  // IMPORTANT: literal '$' must NOT be used with interpolation like $${tunnelName}
  // Use raw string + concat.
  String get _serviceName => r'WireGuardTunnel$' + tunnelName;

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
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

  static String? _extractEndpointIPv4(String cfg) {
    final re = RegExp(
      r'^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<String?> _configPathForCleanup() async {
    if (_lastConfigPath != null && _lastConfigPath!.trim().isNotEmpty) {
      return _lastConfigPath;
    }
    // best effort: try to parse from sc qc if service exists
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
    _lastConfigPath = configPath;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(ok: false, message: 'Config not found:\n$configPath');
    }

    try {
      final inner = r'''
$ErrorActionPreference="Stop"
$exe="__EXE__"
$cfg="__CFG__"
$tn="__TN__"
$svc="__SVC__"

# 1) add bypass route to Endpoint via current default gateway (prevents handshake going into tunnel)
if (Test-Path $cfg) {
  $txt = Get-Content -Raw -Encoding UTF8 $cfg
  $ep = $null
  if ($txt -match '^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') { $ep = $matches[1] }
  if ($ep) {
    $rt = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
    $gw = $rt.NextHop
    if ($gw -and $gw -ne "0.0.0.0") {
      for ($i=0; $i -lt 3; $i++) { route.exe delete $ep | Out-Null }
      route.exe add $ep mask 255.255.255.255 $gw metric 1 | Out-Null
    }
  }
}

# 2) reinstall tunnel service to point exactly to our cfg
sc.exe stop $svc | Out-Null
Start-Sleep -Milliseconds 300

& $exe /uninstalltunnelservice $tn | Out-Null
& $exe /installtunnelservice $cfg | Out-Null

# 3) start
sc.exe start $svc | Out-Null

# 4) wait RUNNING (up to ~8s)
for ($i=0; $i -lt 40; $i++) {
  $q = sc.exe query $svc
  if ($q -match 'STATE\s*:\s*\d+\s+RUNNING') { exit 0 }
  Start-Sleep -Milliseconds 200
}

# still not RUNNING
$q = sc.exe query $svc
Write-Host $q
exit 2
'''
          .replaceAll('__EXE__', _exe.replaceAll('"', ''))
          .replaceAll('__CFG__', configPath.replaceAll('"', ''))
          .replaceAll('__TN__', tunnelName.replaceAll('"', ''))
          .replaceAll('__SVC__', _serviceName.replaceAll('"', ''));

      final pr = await _runElevatedPowerShell(inner);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(ok: false, message: msg.isEmpty ? 'Connect failed (UAC/PowerShell).' : msg);
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'WireGuard error: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    try {
      final cfg = await _configPathForCleanup();

      final inner = r'''
$ErrorActionPreference="SilentlyContinue"
$exe="__EXE__"
$tn="__TN__"
$svc="__SVC__"
$cfg="__CFG__"

# stop (ignore) + wait STOPPED
sc.exe stop $svc | Out-Null
for ($i=0; $i -lt 60; $i++) {
  $q = sc.exe query $svc 2>$null
  if (!$q) { break }
  if ($q -match 'STATE\s*:\s*\d+\s+STOPPED') { break }
  Start-Sleep -Milliseconds 200
}

# uninstall tunnel service (safe even if absent)
& $exe /uninstalltunnelservice $tn | Out-Null

# if service still RUNNING -> kill tunnelservice wireguard.exe process (best-effort)
$q2 = sc.exe query $svc 2>$null
if ($q2 -and ($q2 -match 'STATE\s*:\s*\d+\s+RUNNING')) {
  try {
    Get-CimInstance Win32_Process -Filter "Name='wireguard.exe'" | ForEach-Object {
      $cl = $_.CommandLine
      if ($cl -match '/tunnelservice') {
        # if cfg is known - prefer matching it, else kill any tunnelservice process
        if ($cfg -and $cl -match [regex]::Escape($cfg)) { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        elseif (-not $cfg) { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      }
    }
  } catch {}
  sc.exe stop $svc | Out-Null
  Start-Sleep -Milliseconds 400
  & $exe /uninstalltunnelservice $tn | Out-Null
}

# cleanup endpoint bypass route (delete multiple times)
if ($cfg -and (Test-Path $cfg)) {
  $txt = Get-Content -Raw -Encoding UTF8 $cfg
  $ep = $null
  if ($txt -match '^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') { $ep = $matches[1] }
  if ($ep) { for ($i=0; $i -lt 10; $i++) { route.exe delete $ep | Out-Null } }
}

exit 0
'''
          .replaceAll('__EXE__', _exe.replaceAll('"', ''))
          .replaceAll('__TN__', tunnelName.replaceAll('"', ''))
          .replaceAll('__SVC__', _serviceName.replaceAll('"', ''))
          .replaceAll('__CFG__', (cfg ?? '').replaceAll('"', ''));

      final pr = await _runElevatedPowerShell(inner);
      if (pr.exitCode != 0) {
        final msg = ('${pr.stdout}\n${pr.stderr}').trim();
        return VpnBackendResult(ok: false, message: msg.isEmpty ? 'Disconnect failed (UAC/PowerShell).' : msg);
      }

      // verify
      final on = await isConnected();
      if (on) {
        return const VpnBackendResult(ok: false, message: 'Service still RUNNING after stop/uninstall.');
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

$text = $text.Substring(0, $beStart) + $newBackend
Ok "BACKEND patched."

# --- best-effort: swipe-to-toggle on big button ---
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

  $aheadLen = [Math]::Min(900, $content.Length - $gdIdx)
  $ahead = $content.Substring($gdIdx, $aheadLen)

  $m = [regex]::Match($ahead, "onTap\s*:\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*,")
  if (-not $m.Success) {
    return @{ Content = $content; Patched = $false; Note = "onTap is not a simple identifier; skip swipe patch." }
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

# write main.dart
Set-Content -Path $main -Value $text -Encoding UTF8
Ok "Patched: lib\main.dart"

if ($SkipBuild) {
  Warn "SkipBuild set: patch done, build skipped."
  exit 0
}

# build using proven script if present
$buildScript = Join-Path $proj "bluevpn_build_release.ps1"
if (Test-Path $buildScript) {
  Info "Running build script: $buildScript"
  powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript
  Ok "DONE. Launch via Desktop shortcut: BlueVPN.lnk"
  exit 0
}

# fallback build
Info "Build script not found; running flutter commands directly..."
flutter pub get | Out-Host
flutter clean | Out-Host
flutter build windows --release -t .\lib\main.dart | Out-Host
Ok "DONE."
