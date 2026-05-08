import 'dart:io';

import '../core/bluevpn_paths.dart';

class VpnRuntimeStatus {
  final bool serviceInstalled;
  final bool serviceRunning;
  final String latestHandshake;
  final String transferRx;
  final String transferTx;
  final String rawService;
  final String rawWg;

  const VpnRuntimeStatus({
    required this.serviceInstalled,
    required this.serviceRunning,
    required this.latestHandshake,
    required this.transferRx,
    required this.transferTx,
    required this.rawService,
    required this.rawWg,
  });
}

class WindowsWireGuardService {
  Future<void> writeManagedConfig(String configText) async {
    if (!Platform.isWindows) {
      throw Exception('This client service is Windows-only.');
    }

    await BlueVpnPaths.ensureDirs();

    final file = BlueVpnPaths.managedConfigFile;
    if (await file.exists()) {
      final backupPath = '${file.path}.bak_${_timestamp()}';
      await file.copy(backupPath);
    }

    await file.writeAsString(configText, flush: true);
  }

  Future<String> readManagedConfig() async {
    final file = BlueVpnPaths.managedConfigFile;
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<bool> managedConfigExists() async {
    return BlueVpnPaths.managedConfigFile.exists();
  }

  Future<void> connect() async {
    if (!Platform.isWindows) {
      throw Exception('This client service is Windows-only.');
    }

    final wireguardExe = File(BlueVpnPaths.wireguardExe);
    if (!wireguardExe.existsSync()) {
      throw Exception(
        'WireGuard is not installed: ${BlueVpnPaths.wireguardExe}',
      );
    }

    final configFile = BlueVpnPaths.managedConfigFile;
    if (!await configFile.exists()) {
      throw Exception(
        'Managed config not found: ${configFile.path}',
      );
    }

    await disconnect(ignoreMissing: true);

    final result = await Process.run(
      BlueVpnPaths.wireguardExe,
      ['/installtunnelservice', configFile.path],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Connect failed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}',
      );
    }
  }

  Future<void> disconnect({bool ignoreMissing = false}) async {
    if (!Platform.isWindows) {
      throw Exception('This client service is Windows-only.');
    }

    final wireguardExe = File(BlueVpnPaths.wireguardExe);
    if (!wireguardExe.existsSync()) {
      if (ignoreMissing) {
        return;
      }
      throw Exception(
        'WireGuard is not installed: ${BlueVpnPaths.wireguardExe}',
      );
    }

    final result = await Process.run(
      BlueVpnPaths.wireguardExe,
      ['/uninstalltunnelservice', BlueVpnPaths.tunnelName],
      runInShell: true,
    );

    if (result.exitCode != 0 && !ignoreMissing) {
      throw Exception(
        'Disconnect failed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}',
      );
    }
  }

  Future<VpnRuntimeStatus> getStatus() async {
    if (!Platform.isWindows) {
      return const VpnRuntimeStatus(
        serviceInstalled: false,
        serviceRunning: false,
        latestHandshake: '-',
        transferRx: '-',
        transferTx: '-',
        rawService: 'Non-Windows platform',
        rawWg: '',
      );
    }

    final scResult = await Process.run(
      'sc.exe',
      ['query', BlueVpnPaths.serviceName],
      runInShell: true,
    );

    final rawService = '${scResult.stdout}\n${scResult.stderr}'.trim();
    final serviceInstalled = scResult.exitCode == 0;
    final serviceRunning =
        serviceInstalled && rawService.toUpperCase().contains('RUNNING');

    String rawWg = '';
    final wgExe = File(BlueVpnPaths.wgExe);
    if (wgExe.existsSync()) {
      final wgResult = await Process.run(
        BlueVpnPaths.wgExe,
        ['show'],
        runInShell: true,
      );
      rawWg = '${wgResult.stdout}\n${wgResult.stderr}'.trim();
    }

    final latestHandshakeMatch =
        RegExp(r'latest handshake:\s*([^\r\n]+)').firstMatch(rawWg);
    final transferMatch =
        RegExp(r'transfer:\s*(.+?) received,\s*(.+?) sent').firstMatch(rawWg);

    return VpnRuntimeStatus(
      serviceInstalled: serviceInstalled,
      serviceRunning: serviceRunning,
      latestHandshake: latestHandshakeMatch?.group(1)?.trim() ?? '-',
      transferRx: transferMatch?.group(1)?.trim() ?? '-',
      transferTx: transferMatch?.group(2)?.trim() ?? '-',
      rawService: rawService,
      rawWg: rawWg,
    );
  }

  String _timestamp() {
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '${yyyy}${mm}${dd}_${hh}${mi}${ss}';
  }
}
