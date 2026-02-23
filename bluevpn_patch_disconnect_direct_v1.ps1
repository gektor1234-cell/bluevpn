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

# New disconnect() method (DIRECT, NO UAC, WITH LOG)
$newMethod = @'
  @override
  Future<VpnBackendResult> disconnect() async {
    final logFile = File(r'C:\ProgramData\BlueVPN\backend.log');

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString('[' + ts + '] ' + s + '\n', mode: FileMode.append);
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString()).trim();

    int? pidFrom(String out) {
      final m1 = RegExp(r'(?m)^\s*PID\s*:\s*(\d+)\s*$').firstMatch(out);
      if (m1 != null) return int.tryParse(m1.group(1)!);
      final m2 = RegExp(r'(?m)^\s*ID_процесса\s*:\s*(\d+)\s*$').firstMatch(out);
      if (m2 != null) return int.tryParse(m2.group(1)!);
      return null;
    }

    bool isStoppedText(String out) => out.contains('STOPPED');
    bool isRunningText(String out) => out.contains('RUNNING');

    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitStopped({int loops = 40}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log('queryex[$i] ec=${q.exitCode} :: ' + o.replaceAll('\r', ' ').replaceAll('\n', ' | '));
        if (q.exitCode != 0) return true; // service missing => treated as off
        if (isStoppedText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    try {
      await log('=== DISCONNECT requested ===');
      await log('service=' + _serviceName);

      // 1) sc stop
      final stop = await _run('sc', ['stop', _serviceName]);
      await log('sc stop ec=${stop.exitCode} :: ' + outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | '));

      // 2) wait STOPPED
      var stopped = await waitStopped(loops: 24); // ~6s

      // 3) if still running -> get PID and taskkill
      if (!stopped) {
        final q = await scQueryEx();
        final o = outOf(q);
        final pid = pidFrom(o);

        await log('still not stopped. pid=' + (pid?.toString() ?? 'null') + ' running=' + isRunningText(o).toString());

        if (pid != null && pid > 0) {
          final tk = await _run('taskkill', ['/PID', '$pid', '/F', '/T']);
          await log('taskkill pid=$pid ec=${tk.exitCode} :: ' + outOf(tk).replaceAll('\r', ' ').replaceAll('\n', ' | '));
        } else {
          await log('WARN: PID not parsed from queryex. No taskkill performed.');
        }

        await Future.delayed(const Duration(milliseconds: 400));
        stopped = await waitStopped(loops: 20); // ~5s
      }

      // 4) last resort: uninstall service
      if (!stopped) {
        await log('LAST RESORT: uninstall tunnel service via wireguard.exe');
        final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        await log('wireguard uninstall ec=${un.exitCode} :: ' + outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | '));

        await Future.delayed(const Duration(milliseconds: 600));
        stopped = await waitStopped(loops: 24);
      }

      // 5) final verify (wait a bit)
      for (var i = 0; i < 40; i++) {
        final on = await isConnected();
        await log('verify[$i] isConnected=' + on.toString());
        if (!on) {
          await log('=== DISCONNECT OK ===');
          return const VpnBackendResult(ok: true);
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }

      await log('=== DISCONNECT FAIL: still RUNNING ===');
      return const VpnBackendResult(
        ok: false,
        message: 'Service still RUNNING after stop/kill/uninstall. See log: C:\\ProgramData\\BlueVPN\\backend.log',
      );
    } catch (e) {
      await log('EXCEPTION: ' + e.toString());
      return VpnBackendResult(ok: false, message: 'Disconnect error: $e (see backend.log)');
    }
  }

'@

# Replace disconnect() block up to isConnected()
$pattern = '(?s)@override\s+Future<VpnBackendResult>\s+disconnect\(\)\s+async\s*\{.*?(\r?\n\s*@override\s+Future<bool>\s+isConnected\(\)\s+async\s*\{)'
$rx = [regex]::new($pattern)

if (-not $rx.IsMatch($content)) {
  throw "disconnect() block not found for replacement (pattern mismatch)."
}

$content2 = $rx.Replace($content, { param($m) $newMethod + $m.Groups[1].Value }, 1)

Set-Content -LiteralPath $main -Value $content2 -Encoding UTF8
Write-Host "OK: disconnect() replaced with direct+logging version" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}