import 'dart:io';

import 'package:flutter/material.dart';

import '../core/bluevpn_paths.dart';
import '../models/backend_models.dart';
import '../services/backend_api_service.dart';
import '../services/backend_session_service.dart';
import '../services/windows_wireguard_service.dart';

const String kDefaultApiBaseUrl = 'http://37.220.85.211:8000';
const String kAppVersion = '0.1.0';

class BlueVpnBackendMvpApp extends StatefulWidget {
  const BlueVpnBackendMvpApp({super.key});

  @override
  State<BlueVpnBackendMvpApp> createState() => _BlueVpnBackendMvpAppState();
}

class _BlueVpnBackendMvpAppState extends State<BlueVpnBackendMvpApp> {
  BackendSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await BackendSessionService.load();
    if (!mounted) return;

    setState(() {
      _session = session;
      _loading = false;
    });
  }

  Future<void> _handleAuthenticated(BackendSession session) async {
    await BackendSessionService.save(session);
    if (!mounted) return;

    setState(() {
      _session = session;
    });
  }

  Future<void> _handleLogout() async {
    await BackendSessionService.clear();
    if (!mounted) return;

    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueVPN Backend MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: _loading
          ? const _SplashPage()
          : (_session == null
              ? LoginPage(onAuthenticated: _handleAuthenticated)
              : HomePage(
                  session: _session!,
                  onAuthenticated: _handleAuthenticated,
                  onLogout: _handleLogout,
                )),
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Future<void> Function(BackendSession session) onAuthenticated;

  const LoginPage({
    super.key,
    required this.onAuthenticated,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _apiController = TextEditingController(text: kDefaultApiBaseUrl);
  final _emailController = TextEditingController(text: 'test1@bluevpn.local');
  final _passwordController = TextEditingController(text: 'test123456');

  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _apiController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBackend() async {
    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      final api = BackendApiService(apiBaseUrl: _apiController.text.trim());
      final health = await api.healthz();
      final meta = await api.meta();

      if (!mounted) return;
      setState(() {
        _message =
            'Backend OK\nhealthz: ${health['ok']}\nendpoint: ${meta['defaultServer']?['endpoint']}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Ошибка проверки backend: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _submit({required bool registerMode}) async {
    final apiBaseUrl = _apiController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (apiBaseUrl.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Заполни API URL, email и пароль.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      final api = BackendApiService(apiBaseUrl: apiBaseUrl);

      final response = registerMode
          ? await api.register(email: email, password: password)
          : await api.login(email: email, password: password);

      final previous = await BackendSessionService.load();
      final deviceUid =
          previous?.deviceUid ?? BackendSessionService.generateDeviceUid();

      final session = BackendSession(
        apiBaseUrl: apiBaseUrl,
        email: response.email,
        token: response.accessToken,
        deviceUid: deviceUid,
      );

      await widget.onAuthenticated(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Ошибка авторизации: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueVPN • Backend login'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _apiController,
                      enabled: !disabled,
                      decoration: const InputDecoration(
                        labelText: 'Backend API URL',
                        hintText: 'http://37.220.85.211:8000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      enabled: !disabled,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      enabled: !disabled,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: disabled
                              ? null
                              : () => _submit(registerMode: false),
                          child: const Text('Войти'),
                        ),
                        OutlinedButton(
                          onPressed: disabled
                              ? null
                              : () => _submit(registerMode: true),
                          child: const Text('Регистрация'),
                        ),
                        TextButton(
                          onPressed: disabled ? null : _checkBackend,
                          child: const Text('Проверить backend'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_busy) const CircularProgressIndicator(),
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SelectableText(_message),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final BackendSession session;
  final Future<void> Function(BackendSession session) onAuthenticated;
  final Future<void> Function() onLogout;

  const HomePage({
    super.key,
    required this.session,
    required this.onAuthenticated,
    required this.onLogout,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WindowsWireGuardService _wgService = WindowsWireGuardService();

  bool _busy = false;
  String _message = '';
  String _configPreview = '';
  VpnRuntimeStatus _status = const VpnRuntimeStatus(
    serviceInstalled: false,
    serviceRunning: false,
    latestHandshake: '-',
    transferRx: '-',
    transferTx: '-',
    rawService: '',
    rawWg: '',
  );

  BackendApiService get _api => BackendApiService(
        apiBaseUrl: widget.session.apiBaseUrl,
        token: widget.session.token,
      );

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Ошибка: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    final status = await _wgService.getStatus();
    final configText = await _wgService.readManagedConfig();

    if (!mounted) return;
    setState(() {
      _status = status;
      _configPreview = _trimPreview(configText);
    });
  }

  String _trimPreview(String text) {
    if (text.trim().isEmpty) {
      return '(конфиг пока не записан)';
    }

    final lines = text.split(RegExp(r'\r?\n'));
    return lines.take(20).join('\n');
  }

  Future<void> _prepareConfigOnly() async {
    await _runBusy(() async {
      final bootstrap = await _api.bootstrap(
        deviceUid: widget.session.deviceUid,
        deviceName:
            Platform.environment['COMPUTERNAME'] ?? 'Windows device',
        platform: 'windows',
        appVersion: kAppVersion,
      );

      if (!bootstrap.canConnect) {
        throw Exception(
          bootstrap.reason ?? 'Bootstrap returned canConnect=false',
        );
      }

      final config = await _api.clientConfig(
        deviceUid: widget.session.deviceUid,
        mode: 'full',
      );

      await _wgService.writeManagedConfig(config.configText);
      await _refreshAll();

      if (!mounted) return;
      setState(() {
        _message =
            'Конфиг обновлён.\nIP: ${config.assignedIp}\nEndpoint: ${config.endpoint}';
      });
    });
  }

  Future<void> _connect() async {
    await _runBusy(() async {
      if (!await _wgService.managedConfigExists()) {
        await _prepareConfigOnly();
      }

      await _wgService.connect();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refreshAll();

      if (!mounted) return;
      setState(() {
        _message = 'VPN подключён.';
      });
    });
  }

  Future<void> _prepareAndConnect() async {
    await _runBusy(() async {
      final bootstrap = await _api.bootstrap(
        deviceUid: widget.session.deviceUid,
        deviceName:
            Platform.environment['COMPUTERNAME'] ?? 'Windows device',
        platform: 'windows',
        appVersion: kAppVersion,
      );

      if (!bootstrap.canConnect) {
        throw Exception(
          bootstrap.reason ?? 'Bootstrap returned canConnect=false',
        );
      }

      final config = await _api.clientConfig(
        deviceUid: widget.session.deviceUid,
        mode: 'full',
      );

      await _wgService.writeManagedConfig(config.configText);
      await _wgService.connect();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refreshAll();

      if (!mounted) return;
      setState(() {
        _message =
            'Конфиг обновлён и VPN подключён.\nIP: ${config.assignedIp}\nEndpoint: ${config.endpoint}';
      });
    });
  }

  Future<void> _disconnect() async {
    await _runBusy(() async {
      await _wgService.disconnect(ignoreMissing: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshAll();

      if (!mounted) return;
      setState(() {
        _message = 'VPN отключён.';
      });
    });
  }

  Future<void> _logout() async {
    await widget.onLogout();
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 165,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runningText = _status.serviceRunning ? 'RUNNING' : 'STOPPED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueVPN • Backend MVP'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _logout,
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow('Backend API', widget.session.apiBaseUrl),
                    _infoRow('Email', widget.session.email),
                    _infoRow('Device UID', widget.session.deviceUid),
                    _infoRow('Session file', BlueVpnPaths.backendSessionFile.path),
                    _infoRow('Managed config', BlueVpnPaths.managedConfigFile.path),
                    _infoRow('WireGuard service', BlueVpnPaths.serviceName),
                    _infoRow('Service state', runningText),
                    _infoRow('Latest handshake', _status.latestHandshake),
                    _infoRow('RX', _status.transferRx),
                    _infoRow('TX', _status.transferTx),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _prepareAndConnect,
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Обновить конфиг + подключить'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Подключить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _prepareConfigOnly,
                      icon: const Icon(Icons.sync),
                      label: const Text('Только обновить конфиг'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _disconnect,
                      icon: const Icon(Icons.stop),
                      label: const Text('Отключить'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _refreshAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить статус'),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_message),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                title: const Text('Preview managed config'),
                initiallyExpanded: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_configPreview),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                title: const Text('Raw service status'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _status.rawService.isEmpty
                          ? '(empty)'
                          : _status.rawService,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                title: const Text('Raw wg.exe show'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _status.rawWg.isEmpty ? '(empty)' : _status.rawWg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
