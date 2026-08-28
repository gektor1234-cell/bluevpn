import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  test('public payment flow stays on the primary read-write API', () async {
    final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fallback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await primary.close(force: true);
      await fallback.close(force: true);
    });

    var primaryRequests = 0;
    var fallbackRequests = 0;

    primary.listen((request) async {
      primaryRequests += 1;
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/v1/catalog/tariffs':
          request.response.write(
            jsonEncode({
              'catalog': {
                'paidSalesEnabled': true,
                'paymentsProductionReady': true,
                'checkoutMessage': 'Оплата доступна.',
              },
            }),
          );
        case '/api/v1/auth/checkout/email/start':
          request.response.write(jsonEncode({'ok': true}));
        case '/api/v1/auth/checkout/email/verify':
          request.response.write(
            jsonEncode({
              'accessToken': 'primary-payment-token',
              'email': 'buyer@example.test',
              'isGuest': false,
              'emailVerified': true,
              'emailConfirmationRequired': false,
            }),
          );
        case '/api/v1/subscription/quote':
          request.response.write(
            jsonEncode({
              'quote': {'amountRub': 249},
            }),
          );
        case '/api/v1/billing/orders':
          if (request.method == 'POST') {
            request.response.write(
              jsonEncode({
                'order': {'orderId': 'local-order'},
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          }
        case '/api/v1/billing/orders/local-order':
          request.response.write(
            jsonEncode({
              'order': {'orderId': 'local-order'},
            }),
          );
        case '/api/v1/subscription/auto-renew/cancel':
          request.response.write(jsonEncode({'autoRenew': false}));
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'detail': 'not found'}));
      }
      await request.response.close();
    });

    fallback.listen((request) async {
      fallbackRequests += 1;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'catalog': {
            'paidSalesEnabled': false,
            'paymentsProductionReady': false,
            'checkoutMessage': 'Оплата временно недоступна.',
          },
        }),
      );
      await request.response.close();
    });

    final api = BlueVpnApi(
      baseUrl: 'http://${primary.address.address}:${primary.port}',
      fallbackBaseUrls: ['http://${fallback.address.address}:${fallback.port}'],
    );

    final catalog = await api.fetchTariffCatalog();
    expect(catalog.ok, isTrue);
    expect(catalog.data?['paidSalesEnabled'], isTrue);

    final emailStart = await api.startCheckoutEmail(
      accessToken: 'guest-token',
      email: 'buyer@example.test',
    );
    expect(emailStart.ok, isTrue);

    final emailVerify = await api.verifyCheckoutEmail(
      accessToken: 'guest-token',
      email: 'buyer@example.test',
      code: '123456',
    );
    expect(emailVerify.ok, isTrue);
    final token = emailVerify.data!.accessToken;

    final quote = await api.quoteTariff(
      accessToken: token,
      billingPlanCode: 'green_1m',
      trafficPack: 'standard',
      trafficGb: 0,
      unlimitedApps: const [],
      devices: 1,
      dedicatedIp: false,
    );
    expect(quote.ok, isTrue);

    final order = await api.createBillingOrder(
      accessToken: token,
      billingPlanCode: 'green_1m',
      trafficPack: 'standard',
      trafficGb: 0,
      unlimitedApps: const [],
      devices: 1,
      dedicatedIp: false,
      autoRenew: true,
    );
    expect(order.ok, isTrue);

    final status = await api.fetchBillingOrder(
      accessToken: token,
      orderId: 'local-order',
    );
    expect(status.ok, isTrue);

    final cancel = await api.cancelAutoRenew(accessToken: token);
    expect(cancel.ok, isTrue);

    expect(primaryRequests, 7);
    expect(fallbackRequests, 0);
  });
}
