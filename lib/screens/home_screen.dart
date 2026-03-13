import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/config_service.dart';
import '../services/wireguard_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _serviceState = '...';
  String _configText = '';
  String _logTail = '';
  String? _error;

  bool get _hasConfig => _configText.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _error = null);
    try {
      final state = await WireGuardService.getServiceState();
      String cfg = '';
      if (await ConfigService.exists()) {
        cfg = await ConfigService.readConfig();
      }
      setState(() {
        _serviceState = state;
        _configText = cfg.trim();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    final res = await WireGuardService.connect();
    await _refreshAll();
    if (!res.ok) setState(() => _error = '${res.stdout}\n${res.stderr}'.trim());
  }

  Future<void> _disconnect() async {
    setState(() => _error = null);
    final res = await WireGuardService.disconnect();
    await _refreshAll();
    if (!res.ok) setState(() => _error = '${res.stdout}\n${res.stderr}'.trim());
  }

  Future<void> _importConf() async {
    setState(() => _error = null);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['conf'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) return;

      await ConfigService.replaceConfigFromPath(path);

      // Перезапуск сервиса под новый конфиг
      await WireGuardService.disconnect();
      await WireGuardService.connect();

      await _refreshAll();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadLogTail() async {
    setState(() => _error = null);
    final res = await WireGuardService.dumpLogTail(lines: 200);
    if (!mounted) return;
    setState(() {
      _logTail = res.stdout.trim();
      if (!res.ok && _logTail.isEmpty) _error = 'dumplog failed: ${res.exitCode}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final stateColor = switch (_serviceState) {
      'RUNNING' => Colors.green,
      'STOPPED' => Colors.orange,
      'MISSING' => Colors.red,
      _ => Colors.blueGrey,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueVPN'),
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            _Card(
              title: 'Ошибка',
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 12),
          ],
          _Card(
            title: 'Service',
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: stateColor, size: 12),
                      const SizedBox(width: 8),
                      Text(r'WireGuardTunnel$BlueVPN: ' + _serviceState),
                    ],
                  ),
                ),
                FilledButton(onPressed: _connect, child: const Text('Connect')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Config (ProgramData)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(r'C:\ProgramData\BlueVPN\BlueVPN.conf'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _importConf,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import .conf'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _refreshAll,
                      icon: const Icon(Icons.sync),
                      label: const Text('Reload'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'QR',
            child: Center(
              child: _hasConfig
                  ? QrImageView(
                      data: _configText,
                      version: QrVersions.auto,
                      size: 280,
                    )
                  : const Text('Config not loaded'),
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Log tail',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _loadLogTail,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Load /dumplog /tail'),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _logTail.isEmpty ? '—' : _logTail,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
