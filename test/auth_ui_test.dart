import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

String _fixtureAccessToken(String flow) =>
    <String>['fixture', flow, 'token'].join('-');

class _FakeAuthApi extends BlueVpnApi {
  _FakeAuthApi() : super(baseUrl: 'https://auth.example.test');

  final List<String> startedMethods = <String>[];
  final List<String> verifiedMethods = <String>[];
  String? checkoutEmail;
  String? accessEmail;

  @override
  Future<ApiResult<Map<String, dynamic>>> startAuthChallenge({
    required String method,
    String? email,
  }) async {
    startedMethods.add(method);
    return ApiResult<Map<String, dynamic>>.ok(<String, dynamic>{
      'method': method,
      'email': ?email,
      'deliveryStatus': 'sent',
      'deliveryReady': true,
    });
  }

  @override
  Future<ApiResult<Session>> verifyAuthChallenge({
    required String method,
    required String code,
    String? email,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    verifiedMethods.add(method);
    return ApiResult<Session>.ok(
      Session(
        accessToken: _fixtureAccessToken('auth'),
        email: email ?? 'owner@example.test',
        emailVerified: true,
      ),
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> startCheckoutEmail({
    required String accessToken,
    required String email,
  }) async {
    checkoutEmail = email;
    return ApiResult<Map<String, dynamic>>.ok(<String, dynamic>{
      'email': email,
      'deliveryStatus': 'sent',
      'deliveryReady': true,
    });
  }

  @override
  Future<ApiResult<Session>> verifyCheckoutEmail({
    required String accessToken,
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return ApiResult<Session>.ok(
      Session(
        accessToken: _fixtureAccessToken('checkout'),
        email: email,
        emailVerified: true,
      ),
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> startAccessEmail({
    required String accessToken,
    required String email,
  }) async {
    accessEmail = email;
    return ApiResult<Map<String, dynamic>>.ok(<String, dynamic>{
      'email': email,
      'deliveryStatus': 'sent',
      'deliveryReady': true,
      'flow': 'access_restore',
    });
  }

  @override
  Future<ApiResult<Session>> verifyAccessEmail({
    required String accessToken,
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return ApiResult<Session>.ok(
      Session(
        accessToken: _fixtureAccessToken('restore'),
        email: email,
        emailVerified: true,
      ),
    );
  }
}

class _ExpiredGuestAuthApi extends _FakeAuthApi {
  final List<String> accessTokens = <String>[];

  @override
  Future<ApiResult<Map<String, dynamic>>> startAccessEmail({
    required String accessToken,
    required String email,
  }) async {
    accessTokens.add(accessToken);
    if (accessTokens.length == 1) {
      return const ApiResult<Map<String, dynamic>>.err(
        '401 Unauthorized: invalid token',
      );
    }
    return super.startAccessEmail(accessToken: accessToken, email: email);
  }
}

Widget _authApp({
  required BlueVpnApi api,
  required Future<void> Function(Session session) onAuthSuccess,
}) {
  return MaterialApp(
    home: AuthPage(
      api: api,
      probeWireGuardOnStart: false,
      prepareWindowsNetworkForAuth: false,
      authLoggingEnabled: false,
      authDeviceIdOverride: 'auth-widget-test-device',
      onAuthSuccess: onAuthSuccess,
    ),
  );
}

void main() {
  testWidgets('recovery exposes email and password without phone or beta', (
    tester,
  ) async {
    await tester.pumpWidget(
      _authApp(api: _FakeAuthApi(), onAuthSuccess: (_) async {}),
    );

    expect(find.text('Email'), findsWidgets);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Телефон'), findsNothing);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.textContaining('Beta'), findsNothing);
    expect(find.textContaining('Бета'), findsNothing);
  });

  testWidgets('email challenge remains a complete recovery path', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    Session? completed;
    await tester.pumpWidget(
      _authApp(
        api: api,
        onAuthSuccess: (session) async {
          completed = session;
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth_email_contact')),
      'owner@example.test',
    );
    final emailStart = find.widgetWithText(ElevatedButton, 'Получить код');
    await tester.ensureVisible(emailStart);
    tester.widget<ElevatedButton>(emailStart).onPressed!();
    await tester.pumpAndSettle();

    expect(api.startedMethods, <String>['email_code']);
    expect(find.text('Код отправлен на email.'), findsWidgets);
    expect(find.text('Код из письма'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('auth_email_code')), '1234');
    final emailVerify = find.widgetWithText(ElevatedButton, 'Войти по коду');
    await tester.ensureVisible(emailVerify);
    tester.widget<ElevatedButton>(emailVerify).onPressed!();
    await tester.pumpAndSettle();

    expect(api.verifiedMethods, <String>['email_code']);
    expect(completed, isNotNull);
    expect(completed!.emailVerified, isTrue);
  });

  testWidgets('delivery status does not leak into password recovery tab', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    await tester.pumpWidget(_authApp(api: api, onAuthSuccess: (_) async {}));

    await tester.enterText(
      find.byKey(const Key('auth_email_contact')),
      'owner@example.test',
    );
    final emailStart = find.widgetWithText(ElevatedButton, 'Получить код');
    tester.widget<ElevatedButton>(emailStart).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Код отправлен на email.'), findsWidgets);

    await tester.tap(find.text('Пароль'));
    await tester.pumpAndSettle();

    expect(find.text('Код отправлен на email.'), findsNothing);
    expect(find.text('Войти по паролю'), findsOneWidget);
  });

  testWidgets('checkout verifies email before returning a payment session', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    Session? completed;
    final guest = Session(
      accessToken: _fixtureAccessToken('guest'),
      email: '',
      isGuest: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                completed = await showDialog<Session>(
                  context: context,
                  builder: (_) => CheckoutEmailDialog(
                    api: api,
                    session: guest,
                    deviceUidOverride: 'checkout-dialog-test-device',
                  ),
                );
              },
              child: const Text('Оплатить'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Оплатить'));
    await tester.pumpAndSettle();
    expect(find.text('Email для оплаты'), findsOneWidget);
    expect(find.textContaining('подтверждение оплаты'), findsOneWidget);
    expect(find.textContaining('чек'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('checkout_email')),
      'buyer@example.test',
    );
    await tester.tap(find.text('Получить код'));
    await tester.pumpAndSettle();
    expect(api.checkoutEmail, 'buyer@example.test');

    await tester.enterText(
      find.byKey(const Key('checkout_email_code')),
      '1234',
    );
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();

    expect(completed, isNotNull);
    expect(completed!.isGuest, isFalse);
    expect(completed!.emailVerified, isTrue);
    expect(completed!.accessToken, _fixtureAccessToken('checkout'));
  });

  testWidgets('existing access is restored outside the payment flow', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    Session? completed;
    final guest = Session(
      accessToken: _fixtureAccessToken('guest'),
      email: '',
      isGuest: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                completed = await showDialog<Session>(
                  context: context,
                  builder: (_) => RestoreAccessDialog(
                    api: api,
                    session: guest,
                    deviceUidOverride: 'restore-dialog-test-device',
                  ),
                );
              },
              child: const Text('Войти'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Войти в аккаунт'), findsOneWidget);
    expect(find.textContaining('оплат'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('restore_access_email')),
      'subscriber@example.test',
    );
    await tester.tap(find.text('Получить код'));
    await tester.pumpAndSettle();
    expect(api.accessEmail, 'subscriber@example.test');
    expect(api.checkoutEmail, isNull);

    await tester.enterText(
      find.byKey(const Key('restore_access_code')),
      '1234',
    );
    final restoreDialog = find.byType(AlertDialog);
    final restoreButton = find.descendant(
      of: restoreDialog,
      matching: find.widgetWithText(FilledButton, 'Войти'),
    );
    await tester.tap(restoreButton);
    await tester.pumpAndSettle();

    expect(completed, isNotNull);
    expect(completed!.isGuest, isFalse);
    expect(completed!.emailVerified, isTrue);
    expect(completed!.accessToken, _fixtureAccessToken('restore'));
    expect(api.checkoutEmail, isNull);
  });

  testWidgets(
    'expired guest access refreshes inside the visible login dialog',
    (tester) async {
      final api = _ExpiredGuestAuthApi();
      var renewCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<Session>(
                  context: context,
                  builder: (_) => RestoreAccessDialog(
                    api: api,
                    session: Session(
                      accessToken: ['expired', 'guest', 'token'].join('-'),
                      email: '',
                      isGuest: true,
                    ),
                    renewGuestSession: () async {
                      renewCalls += 1;
                      return Session(
                        accessToken: ['renewed', 'guest', 'token'].join('-'),
                        email: '',
                        isGuest: true,
                      );
                    },
                  ),
                ),
                child: const Text('Войти'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(find.text('Войти в аккаунт'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('restore_access_email')),
        'subscriber@example.test',
      );
      await tester.tap(find.text('Получить код'));
      await tester.pumpAndSettle();

      expect(renewCalls, 1);
      expect(api.accessTokens, <String>[
        'expired-guest-token',
        'renewed-guest-token',
      ]);
      expect(find.byKey(const Key('restore_access_code')), findsOneWidget);
      expect(find.text('Код отправлен на email.'), findsOneWidget);
    },
  );
}
