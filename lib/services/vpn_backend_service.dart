import 'dart:convert';
import 'dart:io';

import 'config_service.dart';
import '../runtime_config.dart';

class BackendApplyResult {
  final bool ok;
  final String message;

  const BackendApplyResult({required this.ok, required this.message});
}

class VpnBackendService {
  static final Uri _localServiceBase = Uri.parse(
    'http://127.0.0.1:$greenVpnLocalServicePort',
  );
  static const String _localTokenHeader = 'X-GreenVPN-Local-Token';

  Future<BackendApplyResult> applyManagedConfig({
    required String managedConfigPath,
    required bool restartIfConnected,
  }) async {
    try {
      if (!Platform.isWindows) {
        return const BackendApplyResult(
          ok: false,
          message:
              'Green VPN сейчас поддерживает применение VPN-конфига только в Windows.',
        );
      }

      final source = File(managedConfigPath);
      if (!source.existsSync()) {
        return const BackendApplyResult(
          ok: false,
          message: 'Файл VPN-конфига не найден.',
        );
      }

      final wasConnected = await isVpnConnected();
      if (wasConnected && restartIfConnected) {
        final disconnect = await _localServiceRequest(
          'POST',
          '/disconnect',
          responseTimeout: const Duration(seconds: 130),
        );
        if (!disconnect.ok) {
          return BackendApplyResult(
            ok: false,
            message:
                disconnect.message ??
                'Не удалось временно отключить VPN для применения нового конфига.',
          );
        }
      }

      if (source.path.toLowerCase() != ConfigService.configPath.toLowerCase()) {
        await ConfigService.replaceConfigFromPath(source.path);
      }

      if (wasConnected && restartIfConnected) {
        final connect = await _localServiceRequest(
          'POST',
          '/connect',
          responseTimeout: const Duration(seconds: 130),
        );
        return BackendApplyResult(
          ok: connect.ok,
          message: connect.ok
              ? 'VPN-конфиг применён, подключение перезапущено.'
              : (connect.message ??
                    'Конфиг применён, но VPN не удалось запустить заново.'),
        );
      }

      return const BackendApplyResult(
        ok: true,
        message: 'VPN-конфиг подготовлен.',
      );
    } catch (e) {
      return BackendApplyResult(
        ok: false,
        message: 'Не удалось применить VPN-конфиг: $e',
      );
    }
  }

  Future<bool> isVpnConnected() async {
    try {
      if (!Platform.isWindows) return false;
      final response = await _localServiceRequest(
        'GET',
        '/status',
        responseTimeout: const Duration(seconds: 5),
      );
      return response.ok && response.data['tunnelState'] == 'running';
    } catch (_) {
      return false;
    }
  }

  Future<String> getDiagnosticsSummary() async {
    try {
      final connected = await isVpnConnected();
      return connected ? 'VPN подключён' : 'VPN отключён';
    } catch (e) {
      return 'Ошибка диагностики: $e';
    }
  }

  Future<_LocalServiceResponse> _localServiceRequest(
    String method,
    String path, {
    Duration connectTimeout = const Duration(seconds: 2),
    required Duration responseTimeout,
  }) async {
    final token = await _readLocalToken();
    if (_requiresLocalToken(path) && token == null) {
      return const _LocalServiceResponse(
        ok: false,
        statusCode: 0,
        message:
            'Системный компонент Green VPN установлен без защитного токена. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
      );
    }

    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final uri = _localServiceBase.resolve(path);
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(connectTimeout)
          : await client.getUrl(uri).timeout(connectTimeout);

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(_localTokenHeader, token);
      }
      if (method == 'POST') {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.add(utf8.encode('{}'));
      }

      final response = await request.close().timeout(responseTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final data = _decodeJsonObject(body);
      return _LocalServiceResponse(
        ok:
            response.statusCode >= 200 &&
            response.statusCode < 300 &&
            data['ok'] == true,
        statusCode: response.statusCode,
        message: data['message']?.toString(),
        data: data,
      );
    } catch (e) {
      return _LocalServiceResponse(
        ok: false,
        statusCode: 0,
        message: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  static bool _requiresLocalToken(String path) {
    final lower = path.toLowerCase();
    return lower == '/status' || lower == '/connect' || lower == '/disconnect';
  }

  static Future<String?> _readLocalToken() async {
    try {
      final file = File(greenVpnServiceTokenPathSync());
      if (!file.existsSync()) return null;
      final token = (await file.readAsString()).trim();
      if (token.length < 24) return null;
      return token;
    } catch (_) {
      return null;
    }
  }
}

class _LocalServiceResponse {
  final bool ok;
  final int statusCode;
  final String? message;
  final Map<String, dynamic> data;

  const _LocalServiceResponse({
    required this.ok,
    required this.statusCode,
    this.message,
    this.data = const <String, dynamic>{},
  });
}
