class BackendSession {
  final String apiBaseUrl;
  final String email;
  final String token;
  final String deviceUid;

  const BackendSession({
    required this.apiBaseUrl,
    required this.email,
    required this.token,
    required this.deviceUid,
  });

  factory BackendSession.fromJson(Map<String, dynamic> json) {
    return BackendSession(
      apiBaseUrl: (json['apiBaseUrl'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      deviceUid: (json['deviceUid'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'email': email,
      'token': token,
      'deviceUid': deviceUid,
    };
  }

  BackendSession copyWith({
    String? apiBaseUrl,
    String? email,
    String? token,
    String? deviceUid,
  }) {
    return BackendSession(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      email: email ?? this.email,
      token: token ?? this.token,
      deviceUid: deviceUid ?? this.deviceUid,
    );
  }
}

class LoginResponse {
  final String accessToken;
  final String email;

  const LoginResponse({
    required this.accessToken,
    required this.email,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: (json['accessToken'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class BootstrapResponse {
  final bool ok;
  final bool canConnect;
  final String? reason;
  final Map<String, dynamic> raw;

  const BootstrapResponse({
    required this.ok,
    required this.canConnect,
    required this.reason,
    required this.raw,
  });

  factory BootstrapResponse.fromJson(Map<String, dynamic> json) {
    return BootstrapResponse(
      ok: json['ok'] == true,
      canConnect: json['canConnect'] == true,
      reason: json['reason']?.toString(),
      raw: json,
    );
  }
}

class ClientConfigResponse {
  final bool ok;
  final String configText;
  final String deviceUid;
  final String assignedIp;
  final String endpoint;

  const ClientConfigResponse({
    required this.ok,
    required this.configText,
    required this.deviceUid,
    required this.assignedIp,
    required this.endpoint,
  });

  factory ClientConfigResponse.fromJson(Map<String, dynamic> json) {
    return ClientConfigResponse(
      ok: json['ok'] == true,
      configText: (json['configText'] ?? '').toString(),
      deviceUid: (json['deviceUid'] ?? '').toString(),
      assignedIp: (json['assignedIp'] ?? '').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
    );
  }
}
