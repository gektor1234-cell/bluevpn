import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_selective_routing_service.dart';

void main() {
  test(
    'discovers launchable Windows programs by user-facing names',
    () async {
      final apps = await listWindowsLaunchableApps();

      expect(apps, isNotEmpty);
      expect(
        apps.map((app) => app.path.toLowerCase()).toSet(),
        hasLength(apps.length),
      );
      expect(apps.every((app) => app.label.trim().isNotEmpty), isTrue);
      expect(apps.every((app) => File(app.path).existsSync()), isTrue);

      final packagedPaths = await _listPackagedLaunchableAppPaths();
      if (packagedPaths.isNotEmpty) {
        expect(
          apps.map((app) => app.path.toLowerCase()),
          containsAll(packagedPaths.map((path) => path.toLowerCase())),
        );
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<List<String>> _listPackagedLaunchableAppPaths() async {
  const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$packages = @{}
foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
    if ($package.PackageFamilyName -and $package.InstallLocation) {
        $packages[[string]$package.PackageFamilyName] = $package
    }
}
$manifests = @{}
$paths = [Collections.Generic.List[string]]::new()
foreach ($startApp in @(Get-StartApps -ErrorAction SilentlyContinue)) {
    $aumid = ([string]$startApp.AppID).Trim()
    $separator = $aumid.LastIndexOf('!')
    if ($separator -lt 1 -or $separator -ge ($aumid.Length - 1)) { continue }
    $package = $packages[$aumid.Substring(0, $separator)]
    if ($null -eq $package) { continue }
    $packageFullName = [string]$package.PackageFullName
    if (-not $manifests.ContainsKey($packageFullName)) {
        $manifests[$packageFullName] = Get-AppxPackageManifest `
            -Package $packageFullName -ErrorAction SilentlyContinue
    }
    $applicationId = $aumid.Substring($separator + 1)
    foreach ($application in @($manifests[$packageFullName].Package.Applications.Application)) {
        if (-not ([string]$application.Id).Equals($applicationId, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $relative = ([string]$application.Executable).Trim().Replace('/', '\').TrimStart('\')
        if (-not $relative.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $path = Join-Path ([string]$package.InstallLocation) $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $fullPath = [IO.Path]::GetFullPath($path)
            if (-not $paths.Contains($fullPath)) { $paths.Add($fullPath) }
        }
    }
}
ConvertTo-Json -InputObject @($paths) -Compress
''';
  final result = await Process.run('powershell.exe', [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);
  if (result.exitCode != 0) return const <String>[];
  final output = result.stdout.toString().trim();
  if (output.isEmpty) return const <String>[];
  final decoded = jsonDecode(output);
  return (decoded is List ? decoded : <Object?>[decoded])
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
