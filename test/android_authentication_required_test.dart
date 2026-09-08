import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:greenvpn/main.dart';
import 'package:greenvpn/services/android_connection_operation_policy.dart';

void main() {
  test('expired authentication is terminal and not an automatic recovery', () {
    final ui = greenVpnAndroidConnectionUiState({
      'state': 'authentication_required',
      'desired': false,
    });
    expect(ui.busy, isFalse);
    expect(ui.terminal, isTrue);
    expect(ui.stage, 'Войдите в аккаунт снова');
  });

  testWidgets(
    'reauthentication uses public email login, not the expired token',
    (tester) async {
      final api = _ReauthenticationApi();
      Session? restored;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    restored = await showDialog<Session>(
                      context: context,
                      builder: (_) => RestoreAccessDialog(
                        api: api,
                        session: const Session(
                          accessToken: 'expired-fixture',
                          email: 'owner@example.test',
                        ),
                        initialEmail: 'owner@example.test',
                        deviceUidOverride: 'synthetic-device',
                        reauthenticate: true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('restore_access_email')))
            .readOnly,
        isTrue,
      );
      await tester.tap(find.text('Получить код'));
      await tester.pumpAndSettle();
      expect(api.starts, 1);
      await tester.enterText(
        find.byKey(const Key('restore_access_code')),
        '1234',
      );
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(api.verifications, 1);
      expect(restored?.accessToken, 'fresh-fixture');
    },
  );
}

class _ReauthenticationApi extends BlueVpnApi {
  _ReauthenticationApi() : super(baseUrl: 'https://unused.invalid');
  int starts = 0;
  int verifications = 0;

  @override
  Future<ApiResult<Map<String, dynamic>>> startEmailCodeAuth({
    required String email,
  }) async {
    starts++;
    return ApiResult.ok({
      'deliveryReady': true,
      'deliveryStatus': 'sent',
      'resendCooldownSeconds': 60,
    });
  }

  @override
  Future<ApiResult<Session>> verifyEmailCodeAuth({
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    verifications++;
    return ApiResult.ok(
      Session(accessToken: 'fresh-fixture', email: email, emailVerified: true),
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> startAccessEmail({
    required String accessToken,
    required String email,
  }) async {
    throw StateError('Expired bearer must not be used for reauthentication');
  }
}
