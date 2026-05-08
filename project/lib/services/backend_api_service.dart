import 'dart:convert';
import 'dart:io';

import '../models/backend_models.dart';

class BackendApiService {
  final String apiBaseUrl;
  final String? token;

  const BackendApiService({
    required this.apiBaseUrl,
    this.token,
  });

  Uri _buildUri(String path) {
    final normalizedBase = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;

    return Uri.parse('$normalizedBase$path');
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();

    try {
      final request = await client.openUrl(method, _buildUri(path));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (token != null && token!.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();

      Map<String, dynamic> jsonBody = {};
      if (responseText.trim().isNotEmpty) {
        final decoded = jsonDecode(responseText);
        if (decoded is Map) {
          jsonBody = Map<String, dynamic>.from(decoded);
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = jsonBody['detail']?.toString();
        throw Exception(
          detail ??
              'HTTP ${response.statusCode} on $path${responseText.isNotEmpty ? ': $responseText' : ''}',
        );
      }

      return jsonBody;
    } on SocketException catch (e) {
      throw Exception('Backend is unreachable: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> healthz() async {
    return _requestJson(method: 'GET', path: '/healthz');
  }

  Future<Map<String, dynamic>> meta() async {
    return _requestJson(method: 'GET', path: '/api/v1/meta');
  }

  Future<LoginResponse> register({
    required String email,
    required String password,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/v1/auth/register',
      body: {
        'email': email,
        'password': password,
      },
    );

    return LoginResponse.fromJson(json);
  }

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/v1/auth/login',
      body: {
        'email': email,
        'password': password,
      },
    );

    return LoginResponse.fromJson(json);
  }

  Future<Map<String, dynamic>> me() async {
    return _requestJson(method: 'GET', path: '/api/v1/me');
  }

  Future<Map<String, dynamic>> subscriptionMe() async {
    return _requestJson(method: 'GET', path: '/api/v1/subscription/me');
  }

  Future<BootstrapResponse> bootstrap({
    required String deviceUid,
    required String deviceName,
    required String platform,
    required String appVersion,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/v1/client/bootstrap',
      body: {
        'deviceUid': deviceUid,
        'deviceName': deviceName,
        'platform': platform,
        'appVersion': appVersion,
      },
    );

    return BootstrapResponse.fromJson(json);
  }

  Future<ClientConfigResponse> clientConfig({
    required String deviceUid,
    String mode = 'full',
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/v1/client/config',
      body: {
        'deviceUid': deviceUid,
        'mode': mode,
      },
    );

    return ClientConfigResponse.fromJson(json);
  }
}
