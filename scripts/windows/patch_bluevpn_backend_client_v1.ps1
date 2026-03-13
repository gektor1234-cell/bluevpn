param(
    [string]$ProjectRoot = "$env:USERPROFILE\projects\bluevpn"
)

$ErrorActionPreference = 'Stop'

$mainPath = Join-Path $ProjectRoot 'lib\main.dart'
if (!(Test-Path $mainPath)) {
    throw "main.dart not found: $mainPath"
}

$backupDir = Join-Path $ProjectRoot ('_chatgpt_backup\backend_client_v1_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item $mainPath (Join-Path $backupDir 'main.dart') -Force

$content = Get-Content $mainPath -Raw -Encoding UTF8

function Replace-OrFail {
    param(
        [string]$Pattern,
        [string]$Replacement,
        [string]$Name
    )

    $updated = [regex]::Replace($content, $Pattern, $Replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($updated -eq $content) {
        throw "Patch failed: $Name"
    }
    $script:content = $updated
}

# 1) Простые path replacements
$content = $content.Replace("'/v1/auth/register'", "'/api/v1/auth/register'")
$content = $content.Replace("'/v1/auth/login'", "'/api/v1/auth/login'")

# 2) Replace fetchPlanName + add bootstrapClient + replace fetchWireGuardConfig
$apiBlock = @'
  Future<ApiResult<String>> fetchPlanName({
    required String accessToken,
    String? deviceId,
  }) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(_u('/api/v1/subscription/me'));
      req.headers.set('Authorization', 'Bearer $accessToken');
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        final p = (jsonMap['planName'] ?? jsonMap['planCode'] ?? 'Base')
            .toString();
        return ApiResult.ok(p.isEmpty ? 'Base' : p);
      }
      return ApiResult.err('Ошибка сервера (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Ошибка сети: $e');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> bootstrapClient({
    required String accessToken,
    required String deviceId,
    required String deviceName,
    String platform = 'windows',
    String appVersion = '0.1.0',
  }) async {
    try {
      final client = HttpClient();
      final req = await client.postUrl(_u('/api/v1/client/bootstrap'));
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $accessToken');
      req.write(
        jsonEncode({
          'deviceUid': deviceId,
          'deviceName': deviceName,
          'platform': platform,
          'appVersion': appVersion,
        }),
      );

      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        return ApiResult.ok(jsonMap);
      }
      return ApiResult.err('Ошибка bootstrap (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Ошибка bootstrap: $e');
    }
  }

  Future<ApiResult<String>> fetchWireGuardConfig({
    required String accessToken,
    String? deviceId,
    String? serverId,
  }) async {
    try {
      if (deviceId == null || deviceId.trim().isEmpty) {
        return const ApiResult.err('Отсутствует device id.');
      }

      final client = HttpClient();
      final req = await client.postUrl(_u('/api/v1/client/config'));
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $accessToken');
      req.write(
        jsonEncode({
          'deviceUid': deviceId,
          'mode': 'full',
        }),
      );

      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final trimmed = body.trim();
        if (trimmed.isEmpty) {
          return const ApiResult.err('Сервер вернул пустой конфиг.');
        }

        final jsonMap = Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
        final cfg = (jsonMap['configText'] ?? jsonMap['config'] ?? '').toString();
        if (cfg.trim().isEmpty) {
          return const ApiResult.err('Сервер вернул пустой configText.');
        }
        return ApiResult.ok(cfg);
      }

      return ApiResult.err('Ошибка сервера (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Не удалось получить конфиг: $e');
    }
  }
'@

Replace-OrFail -Pattern "Future<ApiResult<String>> fetchPlanName\(\{[\s\S]*?Future<ApiResult<String>> fetchWireGuardConfig\(\{[\s\S]*?\n  }\n\n  Future<ApiResult<Session>> _postSession" -Replacement ($apiBlock + "`r`n`r`n  Future<ApiResult<Session>> _postSession") -Name 'BlueVpnApi methods'

# 3) Replace _ensureProvisionedConfigSilently
$silentBlock = @'
  Future<void> _ensureProvisionedConfigSilently() async {
    if (kIsWeb) return;
    try {
      if (widget.session.accessToken == 'dev-token') {
        await _repairProvisionedConfigFromPreferredDevSource(showToast: false);
      }

      final has = await _cfg.hasManagedConfig();
      if (has) {
        await _cfg.ensureBaseSeededFromManagedIfMissing();
        final base = await _cfg.readBaseConfig();
        if (base != null && base.trim().isNotEmpty) {
          await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
        }
        return;
      }

      if (widget.session.accessToken == 'dev-token') {
        await _trySeedDevConfig(showToast: false);
        return;
      }

      final did = await _ensureDeviceId();
      if (did == null || did.isEmpty) return;

      final boot = await _api.bootstrapClient(
        accessToken: widget.session.accessToken,
        deviceId: did,
        deviceName: Platform.localHostname,
        platform: 'windows',
        appVersion: '0.2.0-auth-gate',
      );
      if (!boot.ok || boot.data == null) return;

      final canConnect = boot.data!['canConnect'] == true;
      if (!canConnect) return;

      final sub = boot.data!['subscription'];
      if (sub is Map) {
        final p = (sub['planName'] ?? sub['planCode'] ?? '').toString().trim();
        if (p.isNotEmpty && mounted) {
          setState(() => planName = p);
        }
      }

      final res = await _api.fetchWireGuardConfig(
        accessToken: widget.session.accessToken,
        deviceId: did,
        serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
      );
      if (res.ok && res.data != null) {
        await _writeProvisionedConfig(res.data!);
      }
    } catch (_) {}
  }
'@
Replace-OrFail -Pattern "Future<void> _ensureProvisionedConfigSilently\(\) async \{[\s\S]*?\n  }\n\n  Future<bool> _ensureProvisionedConfigInteractive" -Replacement ($silentBlock + "`r`n`r`n  Future<bool> _ensureProvisionedConfigInteractive") -Name '_ensureProvisionedConfigSilently'

# 4) Replace _ensureProvisionedConfigInteractive
$interactiveBlock = @'
  Future<bool> _ensureProvisionedConfigInteractive() async {
    if (kIsWeb) return false;

    if (widget.session.accessToken == 'dev-token') {
      final ok = await _trySeedDevConfig(showToast: true);
      if (ok) return true;
      _toast(
        context,
        'DEV: не найден локальный конфиг. Положи $kTunnelName.conf на Desktop/Downloads или подними сервер.',
      );
      return false;
    }

    final did = await _ensureDeviceId();
    if (did == null || did.isEmpty) {
      _toast(context, 'Не удалось получить device id.');
      return false;
    }

    final boot = await _api.bootstrapClient(
      accessToken: widget.session.accessToken,
      deviceId: did,
      deviceName: Platform.localHostname,
      platform: 'windows',
      appVersion: '0.2.0-auth-gate',
    );

    if (!boot.ok || boot.data == null) {
      _toast(context, boot.message ?? 'Не удалось пройти bootstrap.');
      return false;
    }

    final bootMap = boot.data!;
    final canConnect = bootMap['canConnect'] == true;
    if (!canConnect) {
      final reason = (bootMap['reason'] ?? 'connect_not_allowed').toString();
      _toast(context, 'Подключение запрещено: $reason');
      return false;
    }

    final sub = bootMap['subscription'];
    if (sub is Map) {
      final p = (sub['planName'] ?? sub['planCode'] ?? '').toString().trim();
      if (p.isNotEmpty && mounted) {
        setState(() => planName = p);
      }
    }

    final res = await _api.fetchWireGuardConfig(
      accessToken: widget.session.accessToken,
      deviceId: did,
      serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
    );
    if (!res.ok || res.data == null) {
      _toast(context, res.message ?? 'Не удалось получить конфиг с сервера.');
      return false;
    }

    await _writeProvisionedConfig(res.data!);
    return true;
  }
'@
Replace-OrFail -Pattern "Future<bool> _ensureProvisionedConfigInteractive\(\) async \{[\s\S]*?\n  }\n\n  Future<void> _toggleVpnReal" -Replacement ($interactiveBlock + "`r`n`r`n  Future<void> _toggleVpnReal") -Name '_ensureProvisionedConfigInteractive'

# 5) Optional comment replacement
$content = $content.Replace("defaultValue: 'https://api.example.com',", "defaultValue: 'http://127.0.0.1:8000',")

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mainPath, $content, $utf8NoBom)

Write-Host "DONE: $mainPath" -ForegroundColor Green
Write-Host "Backup: $backupDir" -ForegroundColor Yellow
Write-Host "Next run command:" -ForegroundColor Cyan
Write-Host 'flutter run -d windows --dart-define=BLUEVPN_API_BASE_URL=http://127.0.0.1:8000'
