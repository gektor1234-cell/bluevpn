import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../runtime_config.dart';

const int windowsSupportLogMaxLines = 120;
const int windowsSupportLogMaxBytes = 128 * 1024;
const int windowsSupportLogLineMaxLength = 700;

final RegExp _sensitiveLinePattern = RegExp(
  r'\b(private\s*key|privatekey|preshared\s*key|presharedkey|authorization|password|secret|token|cookie)\b\s*[:=]',
  caseSensitive: false,
);
final RegExp _bearerPattern = RegExp(
  r'\bbearer\s+[A-Za-z0-9._~+/=-]{10,}',
  caseSensitive: false,
);
final RegExp _emailPattern = RegExp(
  r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
  caseSensitive: false,
);
final RegExp _windowsUserPathPattern = RegExp(
  r'\b[A-Z]:\\Users\\[^\\\s]+',
  caseSensitive: false,
);

String sanitizeWindowsSupportText(
  String value, {
  int maxLength = windowsSupportLogLineMaxLength,
}) {
  var clean = value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ')
      .trim();
  if (_sensitiveLinePattern.hasMatch(clean)) {
    return '<redacted sensitive line>';
  }
  clean = clean
      .replaceAll(_bearerPattern, 'Bearer <redacted>')
      .replaceAll(_emailPattern, '<redacted email>')
      .replaceAll(_windowsUserPathPattern, r'C:\Users\<redacted>');
  if (clean.length > maxLength) {
    clean = '${clean.substring(0, maxLength)}<truncated>';
  }
  return clean;
}

Object? sanitizeWindowsSupportValue(Object? value, {int depth = 0}) {
  if (depth > 8) return '<truncated>';
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(120)) {
      final key = sanitizeWindowsSupportText('${entry.key}', maxLength: 120);
      if (_sensitiveLinePattern.hasMatch('$key=')) {
        result[key] = '<redacted>';
      } else {
        result[key] = sanitizeWindowsSupportValue(
          entry.value,
          depth: depth + 1,
        );
      }
    }
    return result;
  }
  if (value is Iterable) {
    return value
        .take(100)
        .map((item) => sanitizeWindowsSupportValue(item, depth: depth + 1))
        .toList();
  }
  if (value is String) {
    return sanitizeWindowsSupportText(value, maxLength: 2000);
  }
  if (value is bool || value is num || value == null) return value;
  return sanitizeWindowsSupportText('$value', maxLength: 500);
}

List<String> sanitizeWindowsSupportLogLines(
  Iterable<String> lines, {
  int maxLines = windowsSupportLogMaxLines,
}) {
  final nonEmpty = lines.where((line) => line.trim().isNotEmpty).toList();
  final start = nonEmpty.length > maxLines ? nonEmpty.length - maxLines : 0;
  return nonEmpty
      .skip(start)
      .map(sanitizeWindowsSupportText)
      .where((line) => line.isNotEmpty)
      .toList();
}

class WindowsSupportDiagnosticsCollector {
  const WindowsSupportDiagnosticsCollector._();

  static Future<Map<String, Object?>> collect({
    required String appBuildNumber,
    required bool localServiceOk,
    required int localServiceHttpStatus,
    required int? localServiceExitCode,
    required String? localServiceMessage,
    required Map<String, dynamic> localServiceData,
  }) async {
    if (!Platform.isWindows) return const <String, Object?>{};

    final root = greenVpnProgramDataRootSync();
    final configPath = greenVpnManagedConfigPathSync();
    final backendLog = greenVpnBackendLogPathSync();
    final transportLog = '$root\\state\\transport-task.log';
    final connectFailureDiagnostics =
        '$root\\state\\connect-failure-diagnostics.json';
    final authLog = greenVpnAuthLogPathSync();
    final processRouterStdout = '$root\\process-router.stdout.log';
    final processRouterStderr = '$root\\process-router.stderr.log';
    final standbyResult = greenVpnStandbyProbeResultPathSync();
    final stateDir = Directory('$root\\state');

    final result = <String, Object?>{
      'schema': 1,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'appBuildNumber': appBuildNumber,
      'runtimeScope': greenVpnWindowsRuntimeScope,
      'tunnelName': greenVpnTunnelName,
      'controllerServiceName': greenVpnWindowsServiceName,
      'operatingSystemVersion': sanitizeWindowsSupportText(
        Platform.operatingSystemVersion,
        maxLength: 300,
      ),
      'processorCount': Platform.numberOfProcessors,
      'localController': sanitizeWindowsSupportValue(<String, Object?>{
        'ok': localServiceOk,
        'httpStatus': localServiceHttpStatus,
        'exitCode': localServiceExitCode,
        'message': localServiceMessage ?? '',
        'status': localServiceData,
      }),
      'runtimeFiles': <String, Object?>{
        'config': await _fileMetadata(configPath),
        'protocol': await _fileMetadata('$configPath.protocol'),
        'routingMode': await _fileMetadata(
          greenVpnWindowsRoutingModePathSync(),
        ),
        'routingApps': await _routingAppsMetadata(
          greenVpnWindowsRoutingAppsPathSync(),
        ),
        'standbyRequest': await _fileMetadata(
          greenVpnStandbyProbeRequestPathSync(),
        ),
        'standbyResult': await _fileMetadata(standbyResult),
        'backendLog': await _fileMetadata(backendLog),
        'transportLog': await _fileMetadata(transportLog),
        'connectFailureDiagnostics': await _fileMetadata(
          connectFailureDiagnostics,
        ),
        'authLog': await _fileMetadata(authLog),
        'processRouterStdout': await _fileMetadata(processRouterStdout),
        'processRouterStderr': await _fileMetadata(processRouterStderr),
      },
      'standbyProbeResult': await _readJsonFile(standbyResult),
      'connectFailureDiagnostics': await _readJsonFile(
        connectFailureDiagnostics,
      ),
      'stateFiles': await _stateFileInventory(stateDir),
      'logs': <String, Object?>{
        'backendTail': await _readLogTail(backendLog),
        'transportTaskTail': await _readLogTail(transportLog),
        'authTail': await _readLogTail(authLog),
        'processRouterStdoutTail': await _readLogTail(processRouterStdout),
        'processRouterStderrTail': await _readLogTail(processRouterStderr),
      },
      'systemSnapshot': await _collectPowerShellSnapshot(),
    };
    return sanitizeWindowsSupportValue(result) as Map<String, Object?>;
  }

  static Future<Map<String, Object?>> _fileMetadata(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const <String, Object?>{'exists': false};
      final stat = await file.stat();
      return <String, Object?>{
        'exists': true,
        'sizeBytes': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
      };
    } catch (error) {
      return <String, Object?>{
        'exists': false,
        'error': sanitizeWindowsSupportText('$error'),
      };
    }
  }

  static Future<Map<String, Object?>> _routingAppsMetadata(String path) async {
    final metadata = await _fileMetadata(path);
    if (metadata['exists'] != true) return metadata;
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      final items = decoded is List
          ? decoded
          : decoded is Map && decoded['applications'] is List
          ? decoded['applications'] as List
          : const <Object?>[];
      return <String, Object?>{...metadata, 'applicationCount': items.length};
    } catch (error) {
      return <String, Object?>{
        ...metadata,
        'parseError': sanitizeWindowsSupportText('$error'),
      };
    }
  }

  static Future<Object?> _readJsonFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const <String, Object?>{'exists': false};
      final decoded = jsonDecode(await file.readAsString());
      return sanitizeWindowsSupportValue(decoded);
    } catch (error) {
      return <String, Object?>{
        'exists': true,
        'parseError': sanitizeWindowsSupportText('$error'),
      };
    }
  }

  static Future<List<Map<String, Object?>>> _stateFileInventory(
    Directory directory,
  ) async {
    try {
      if (!await directory.exists()) return const <Map<String, Object?>>[];
      final files = await directory
          .list(followLinks: false)
          .where((entry) => entry is File)
          .cast<File>()
          .take(80)
          .toList();
      final result = <Map<String, Object?>>[];
      for (final file in files) {
        final stat = await file.stat();
        result.add(<String, Object?>{
          'name': sanitizeWindowsSupportText(
            file.uri.pathSegments.last,
            maxLength: 160,
          ),
          'sizeBytes': stat.size,
          'modifiedAt': stat.modified.toUtc().toIso8601String(),
        });
      }
      result.sort((left, right) {
        return '${right['modifiedAt']}'.compareTo('${left['modifiedAt']}');
      });
      return result;
    } catch (error) {
      return <Map<String, Object?>>[
        <String, Object?>{'error': sanitizeWindowsSupportText('$error')},
      ];
    }
  }

  static Future<List<String>> _readLogTail(String path) async {
    RandomAccessFile? handle;
    try {
      final file = File(path);
      if (!await file.exists()) return const <String>[];
      handle = await file.open(mode: FileMode.read);
      final length = await handle.length();
      final start = length > windowsSupportLogMaxBytes
          ? length - windowsSupportLogMaxBytes
          : 0;
      await handle.setPosition(start);
      final bytes = await handle.read(length - start);
      var text = utf8.decode(bytes, allowMalformed: true);
      if (start > 0) {
        final firstBreak = text.indexOf('\n');
        text = firstBreak >= 0 ? text.substring(firstBreak + 1) : '';
      }
      return sanitizeWindowsSupportLogLines(const LineSplitter().convert(text));
    } catch (error) {
      return <String>[
        '<log read failed: ${sanitizeWindowsSupportText('$error')}>',
      ];
    } finally {
      await handle?.close();
    }
  }

  static Future<Object?> _collectPowerShellSnapshot() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$serviceNames = @(
  'GreenVPNService',
  'WireGuardTunnel$BlueVPNDev1',
  'AmneziaWGTunnel$BlueVPNDev1',
  'WireGuardTunnel$BlueVPNDev1StandbyProbe',
  'AmneziaWGTunnel$BlueVPNDev1StandbyProbe'
)
$services = @(
  Get-CimInstance Win32_Service |
    Where-Object {
      $_.Name -in $serviceNames -or
      $_.Name -like 'WireGuardTunnel$*' -or
      $_.Name -like 'AmneziaWGTunnel$*' -or
      $_.Name -eq 'CloudflareWARP'
    } |
    Select-Object -First 40 |
    ForEach-Object {
      [ordered]@{
        name = [string]$_.Name
        state = [string]$_.State
        startMode = [string]$_.StartMode
        exitCode = [int]$_.ExitCode
        processId = [int]$_.ProcessId
      }
    }
)
$adapters = @(
  Get-NetAdapter |
    Where-Object {
      $_.Name -match '(?i)(BlueVPN|GreenVPN|WireGuard|Amnezia|WARP|device[0-9_]+)' -or
      $_.InterfaceDescription -match '(?i)(WireGuard|Amnezia|Wintun|WARP)'
    } |
    Select-Object -First 40 |
    ForEach-Object {
      [ordered]@{
        name = [string]$_.Name
        description = [string]$_.InterfaceDescription
        status = [string]$_.Status
        ifIndex = [int]$_.ifIndex
      }
    }
)
$routes = @(
  Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 20 |
    ForEach-Object {
      [ordered]@{
        interfaceAlias = [string]$_.InterfaceAlias
        ifIndex = [int]$_.ifIndex
        routeMetric = [int]$_.RouteMetric
        protocol = [string]$_.Protocol
        state = [string]$_.State
      }
    }
)
$metric42739Count = @(
  Get-NetRoute -AddressFamily IPv4 |
    Where-Object { [int]$_.RouteMetric -eq 42739 }
).Count
$os = Get-CimInstance Win32_OperatingSystem
[ordered]@{
  services = [object[]]$services
  adapters = [object[]]$adapters
  defaultRoutes = [object[]]$routes
  standbyMetricRouteCount = [int]$metric42739Count
  windows = [ordered]@{
    version = [string]$os.Version
    buildNumber = [string]$os.BuildNumber
    architecture = [string]$os.OSArchitecture
    lastBootUpTime = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToUniversalTime().ToString('o') } else { '' }
  }
} | ConvertTo-Json -Compress -Depth 6
''';

    Process? process;
    try {
      process = await Process.start('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          process?.kill();
          return 124;
        },
      );
      final stdout = await stdoutFuture.timeout(const Duration(seconds: 2));
      final stderr = await stderrFuture.timeout(const Duration(seconds: 2));
      if (exitCode != 0) {
        return <String, Object?>{
          'ok': false,
          'exitCode': exitCode,
          'error': sanitizeWindowsSupportText(stderr),
        };
      }
      String? jsonLine;
      for (final line in const LineSplitter().convert(stdout)) {
        if (line.trimLeft().startsWith('{')) jsonLine = line;
      }
      if (jsonLine == null) {
        return const <String, Object?>{
          'ok': false,
          'error': 'PowerShell snapshot returned no JSON.',
        };
      }
      return <String, Object?>{
        'ok': true,
        'data': sanitizeWindowsSupportValue(jsonDecode(jsonLine)),
      };
    } catch (error) {
      process?.kill();
      return <String, Object?>{
        'ok': false,
        'error': sanitizeWindowsSupportText('$error'),
      };
    }
  }
}
