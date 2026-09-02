import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int maxWindowsVpnApplications = 64;
const int maxWindowsVpnSites = 32;
const int maxWindowsVpnDestinationCidrs = 512;

final RegExp _windowsExecutablePathPattern = RegExp(r'^[A-Za-z]:\\');
final RegExp _dnsLabelPattern = RegExp(
  r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
);

bool isValidWindowsApplicationPath(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean.length > 1024) return false;
  if (!_windowsExecutablePathPattern.hasMatch(clean)) return false;
  if (!clean.toLowerCase().endsWith('.exe')) return false;
  if (clean.contains(',') || clean.contains(';')) return false;
  return !clean.codeUnits.any((unit) => unit < 0x20);
}

String windowsApplicationLabel(String path) {
  final parts = path.trim().split(RegExp(r'[\\/]'));
  final fileName = parts.isEmpty ? path.trim() : parts.last.trim();
  if (fileName.toLowerCase().endsWith('.exe') && fileName.length > 4) {
    return fileName.substring(0, fileName.length - 4);
  }
  return fileName.isEmpty ? path.trim() : fileName;
}

bool isValidWindowsVpnDestinationCidr(String value) {
  final clean = value.trim();
  final parts = clean.split('/');
  if (parts.length != 2) return false;
  final prefix = int.tryParse(parts[1]);
  if (prefix == null || prefix < 8 || prefix > 32) return false;
  final address = InternetAddress.tryParse(parts[0]);
  return address != null && _isPublicIpv4(address);
}

String? normalizeWindowsVpnSite(String value) {
  var clean = value.trim();
  if (clean.isEmpty || clean.length > 2048) return null;
  if (!clean.contains('://')) clean = 'https://$clean';

  final uri = Uri.tryParse(clean);
  if (uri == null || uri.host.isEmpty) return null;
  var host = uri.host.trim().toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.startsWith('www.')) host = host.substring(4);
  if (host.isEmpty || host.length > 253) return null;

  final parsedIp = InternetAddress.tryParse(host);
  if (parsedIp != null) {
    return _isPublicIpv4(parsedIp) ? host : null;
  }
  final labels = host.split('.');
  if (labels.length < 2 ||
      labels.any((label) => !_dnsLabelPattern.hasMatch(label))) {
    return null;
  }
  return host;
}

class WindowsLaunchableApp {
  final String path;
  final String label;

  const WindowsLaunchableApp({required this.path, required this.label});

  static WindowsLaunchableApp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = (raw['path'] ?? '').toString().trim();
    if (!isValidWindowsApplicationPath(path)) return null;
    final rawLabel = (raw['label'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
        .trim();
    final safeLabel = rawLabel.length > 120
        ? rawLabel.substring(0, 120).trim()
        : rawLabel;
    return WindowsLaunchableApp(
      path: path,
      label: safeLabel.isEmpty ? windowsApplicationLabel(path) : safeLabel,
    );
  }
}

bool windowsLaunchableAppMatchesQuery(WindowsLaunchableApp app, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  return app.label.toLowerCase().contains(normalizedQuery) ||
      app.path.toLowerCase().contains(normalizedQuery);
}

class WindowsSiteResolution {
  final List<String> sites;
  final List<String> ipv4Cidrs;
  final List<String> unresolvedSites;

  const WindowsSiteResolution({
    required this.sites,
    required this.ipv4Cidrs,
    required this.unresolvedSites,
  });
}

Future<List<WindowsLaunchableApp>> listWindowsLaunchableApps() async {
  if (!Platform.isWindows) return const <WindowsLaunchableApp>[];

  final encodedScript = base64Encode(_utf16LeBytes(_windowsAppDiscoveryScript));
  final result = await Process.run('powershell.exe', [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-EncodedCommand',
    encodedScript,
  ]).timeout(const Duration(seconds: 20));
  if (result.exitCode != 0) {
    throw StateError('Windows не вернул список установленных программ.');
  }

  final output = result.stdout.toString().trim();
  if (output.isEmpty) return const <WindowsLaunchableApp>[];
  final decoded = jsonDecode(output);
  final rawItems = decoded is List ? decoded : <Object?>[decoded];
  final byPath = <String, WindowsLaunchableApp>{};
  for (final raw in rawItems) {
    final app = WindowsLaunchableApp.fromJson(raw);
    if (app == null || !File(app.path).existsSync()) continue;
    byPath[app.path.toLowerCase()] = app;
  }
  final apps = byPath.values.toList()
    ..sort((a, b) {
      final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return byLabel == 0
          ? a.path.toLowerCase().compareTo(b.path.toLowerCase())
          : byLabel;
    });
  return apps;
}

Future<WindowsSiteResolution> resolveWindowsVpnSites(
  Iterable<String> values, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final sites =
      values.map(normalizeWindowsVpnSite).whereType<String>().toSet().toList()
        ..sort();
  if (sites.length > maxWindowsVpnSites) {
    throw StateError('Можно добавить не более $maxWindowsVpnSites сайтов.');
  }

  final resolved = await Future.wait(
    sites.map((site) async {
      final addresses = <String>{};
      final hosts = <String>{site};
      if (InternetAddress.tryParse(site) == null) hosts.add('www.$site');
      for (final host in hosts) {
        try {
          final lookup = await InternetAddress.lookup(
            host,
            type: InternetAddressType.IPv4,
          ).timeout(timeout);
          addresses.addAll(
            lookup
                .where(_isPublicIpv4)
                .map((address) => '${address.address}/32'),
          );
        } catch (_) {
          // A site can legitimately have no www record; the base host may still work.
        }
      }
      return MapEntry(site, addresses);
    }),
  );

  final cidrs = <String>{};
  final unresolved = <String>[];
  for (final entry in resolved) {
    if (entry.value.isEmpty) {
      unresolved.add(entry.key);
    } else {
      cidrs.addAll(entry.value);
    }
  }
  final sortedCidrs = cidrs.toList()..sort(_compareIpv4Cidrs);
  return WindowsSiteResolution(
    sites: sites,
    ipv4Cidrs: sortedCidrs,
    unresolvedSites: unresolved,
  );
}

int _compareIpv4Cidrs(String left, String right) {
  List<int> parts(String value) => value
      .split('/')
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
  final a = parts(left);
  final b = parts(right);
  for (var index = 0; index < 4; index++) {
    final compared = a[index].compareTo(b[index]);
    if (compared != 0) return compared;
  }
  return left.compareTo(right);
}

bool _isPublicIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final parts = address.address
      .split('.')
      .map(int.tryParse)
      .toList(growable: false);
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  final c = parts[2]!;
  if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
  if (a == 100 && b >= 64 && b <= 127) return false;
  if (a == 169 && b == 254) return false;
  if (a == 172 && b >= 16 && b <= 31) return false;
  if (a == 192 && b == 168) return false;
  if (a == 192 && b == 0 && c == 0) return false;
  if (a == 192 && b == 0 && c == 2) return false;
  if (a == 198 && (b == 18 || b == 19)) return false;
  if (a == 198 && b == 51 && c == 100) return false;
  if (a == 203 && b == 0 && c == 113) return false;
  return true;
}

List<int> _utf16LeBytes(String value) {
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add((unit >> 8) & 0xff);
  }
  return bytes;
}

const String _windowsAppDiscoveryScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$apps = @{}

function Add-GreenVpnApp {
    param([string]$Label, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $candidate = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not $candidate.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return }
    try { $candidate = [IO.Path]::GetFullPath($candidate) } catch { return }
    $name = $Label.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [IO.Path]::GetFileNameWithoutExtension($candidate)
    }
    $key = $candidate.ToLowerInvariant()
    if (-not $apps.ContainsKey($key) -or $apps[$key].label -match '(?i)\.exe$') {
        $apps[$key] = [ordered]@{ label = $name; path = $candidate }
    }
}

$shell = $null
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcutRoots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:PUBLIC 'Desktop')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique

    foreach ($root in $shortcutRoots) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue) {
            $shortcut = $shell.CreateShortcut($file.FullName)
            $target = [Environment]::ExpandEnvironmentVariables(([string]$shortcut.TargetPath).Trim())
            $arguments = [string]$shortcut.Arguments
            if (
                [IO.Path]::GetFileName($target).Equals('Update.exe', [StringComparison]::OrdinalIgnoreCase) -and
                $arguments -match '(?i)--processStart\s+(?:"([^"]+\.exe)"|([^\s]+\.exe))'
            ) {
                $processName = if ($matches[1]) { $matches[1] } else { $matches[2] }
                $resolved = Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($target)) -Filter $processName -File -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                if ($null -ne $resolved) { $target = $resolved.FullName }
            }
            Add-GreenVpnApp -Label $file.BaseName -Path $target
        }
    }
} finally {
    if ($null -ne $shell) {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}

# Microsoft Store/MSIX launchers use an application user model ID instead of a
# normal shortcut target. Resolve desktop executables from each package manifest
# so packaged Win32 apps can participate in the existing path-based router.
$packagesByFamily = @{}
foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
    $family = ([string]$package.PackageFamilyName).Trim()
    $location = ([string]$package.InstallLocation).Trim()
    if (
        -not [string]::IsNullOrWhiteSpace($family) -and
        -not [string]::IsNullOrWhiteSpace($location)
    ) {
        $packagesByFamily[$family] = $package
    }
}

$manifestByPackage = @{}
foreach ($startApp in @(Get-StartApps -ErrorAction SilentlyContinue)) {
    $appUserModelId = ([string]$startApp.AppID).Trim()
    $separator = $appUserModelId.LastIndexOf('!')
    if ($separator -lt 1 -or $separator -ge ($appUserModelId.Length - 1)) {
        continue
    }

    $family = $appUserModelId.Substring(0, $separator)
    $applicationId = $appUserModelId.Substring($separator + 1)
    $package = $packagesByFamily[$family]
    if ($null -eq $package) { continue }

    $packageFullName = ([string]$package.PackageFullName).Trim()
    if ([string]::IsNullOrWhiteSpace($packageFullName)) { continue }
    if (-not $manifestByPackage.ContainsKey($packageFullName)) {
        $manifestByPackage[$packageFullName] = Get-AppxPackageManifest `
            -Package $packageFullName -ErrorAction SilentlyContinue
    }
    $manifest = $manifestByPackage[$packageFullName]
    if ($null -eq $manifest) { continue }

    foreach ($application in @($manifest.Package.Applications.Application)) {
        if (-not ([string]$application.Id).Equals(
            $applicationId,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            continue
        }
        $relativeExecutable = ([string]$application.Executable).Trim()
        if ([string]::IsNullOrWhiteSpace($relativeExecutable)) { continue }
        $relativeExecutable = $relativeExecutable.Replace('/', '\').TrimStart('\')
        $target = Join-Path ([string]$package.InstallLocation) $relativeExecutable
        Add-GreenVpnApp -Label ([string]$startApp.Name) -Path $target
    }
}

$appPathRoots = @(
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths',
    'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
)
foreach ($root in $appPathRoots) {
    foreach ($child in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        try {
            $key = Get-Item -LiteralPath $child.PSPath
            Add-GreenVpnApp -Label $child.PSChildName -Path ([string]$key.GetValue(''))
        } catch {}
    }
}

$uninstallRoots = @(
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    foreach ($child in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        $entry = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction SilentlyContinue
        $label = [string]$entry.DisplayName
        $icon = [Environment]::ExpandEnvironmentVariables(([string]$entry.DisplayIcon).Trim())
        if ($icon -match '^"([^"]+\.exe)"') {
            $icon = $matches[1]
        } elseif ($icon -match '^(.*?\.exe)(?:,.*)?$') {
            $icon = $matches[1]
        }
        Add-GreenVpnApp -Label $label -Path $icon
    }
}

$result = @($apps.Values | Sort-Object @{Expression={$_.label.ToLowerInvariant()}}, @{Expression={$_.path.ToLowerInvariant()}})
ConvertTo-Json -InputObject $result -Compress -Depth 4
''';
