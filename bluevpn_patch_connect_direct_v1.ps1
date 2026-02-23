[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = "Stop"

$project = (Resolve-Path ".").Path
$main = Join-Path $project "lib\main.dart"
if (-not (Test-Path -LiteralPath $main)) { throw "Not found: $main" }

# backup
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$backupDir = Join-Path $project ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $main -Destination (Join-Path $backupDir "main.dart") -Force
Write-Host "Backup: $backupDir" -ForegroundColor Cyan

$content = Get-Content -LiteralPath $main -Raw -Encoding UTF8

# --- New connect() method (DIRECT, NO UAC, WITH LOG + WAIT RUNNING) ---
$newConnectMethod = @'
  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final logFile = File(r'C:\ProgramData\BlueVPN\backend.log');

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString('[' + ts + '] ' + s + '\n', mode: FileMode.append);
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString()).trim();

    bool isRunningText(String out) => out.contains('RUNNING');
    bool isStoppedText(String out) => out.contains('STOPPED');

    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitRunning({int loops = 60}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log('queryex(connect)[$i] ec=${q.exitCode} :: ' +
            o.replaceAll('\r', ' ').replaceAll('\n', ' | '));
        if (q.exitCode == 0 && isRunningText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    try {
      await log('=== CONNECT requested ===');
      await log('service=' + _serviceName);
      await log('exe=' + _exe);
      await log('cfg=' + configPath);

      if (!File(configPath).existsSync()) {
        await log('ERROR: configPath does not exist');
        return VpnBackendResult(ok: false, message: 'Config not found: $configPath');
      }

      // 1) ensure service exists: if query fails -> install
      final q0 = await scQueryEx();
      final o0 = outOf(q0);
      await log('queryex(initial) ec=${q0.exitCode} :: ' +
          o0.replaceAll('\r', ' ').replaceAll('\n', ' | '));

      if (q0.exitCode != 0) {
        final ins = await _run(_exe, ['/installtunnelservice', configPath]);
        await log('wireguard install ec=${ins.exitCode} :: ' +
            outOf(ins).replaceAll('\r', ' ').replaceAll('\n', ' | '));
      }

      // 2) start
      final st = await _run('sc', ['start', _serviceName]);
      await log('sc start ec=${st.exitCode} :: ' +
          outOf(st).replaceAll('\r', ' ').replaceAll('\n', ' | '));

      // 3) wait RUNNING (up to ~15s)
      final ok = await waitRunning(loops: 60);
      if (!ok) {
        await log('=== CONNECT FAIL: not RUNNING after wait ===');
        return const VpnBackendResult(
          ok: false,
          message: 'VPN did not start (service not RUNNING). See backend.log',
        );
      }

      // 4) final verify via isConnected()
      for (var i = 0; i < 40; i++) {
        final on = await isConnected();
        await log('verify(connect)[$i] isConnected=' + on.toString());
        if (on) {
          await log('=== CONNECT OK ===');
          return const VpnBackendResult(ok: true);
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }

      await log('=== CONNECT FAIL: verify isConnected still false ===');
      return const VpnBackendResult(
        ok: false,
        message: 'Service RUNNING but isConnected() false. See backend.log',
      );
    } catch (e) {
      await log('EXCEPTION(connect): ' + e.toString());
      return VpnBackendResult(ok: false, message: 'Connect error: $e (see backend.log)');
    }
  }

'@

# Replace connect() block up to disconnect()
$pattern = '(?s)@override\s+Future<VpnBackendResult>\s+connect\([^)]*\)\s+async\s*\{.*?(\r?\n\s*@override\s+Future<VpnBackendResult>\s+disconnect\(\)\s+async\s*\{)'
$rx = [regex]::new($pattern)

if (-not $rx.IsMatch($content)) {
  throw "connect() block not found for replacement (pattern mismatch)."
}

$content2 = $rx.Replace($content, { param($m) $newConnectMethod + $m.Groups[1].Value }, 1)

Set-Content -LiteralPath $main -Value $content2 -Encoding UTF8
Write-Host "OK: connect() replaced with direct+logging+waitRUNNING version" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}