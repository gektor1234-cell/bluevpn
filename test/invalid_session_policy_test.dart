import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  test('sanitized expired-session messages still trigger logout', () {
    expect(greenVpnIsInvalidSessionMessage('Сессия истекла. Войдите снова.'), isTrue);
    expect(greenVpnIsInvalidSessionMessage('Session expired. Sign in again.'), isTrue);
    expect(greenVpnIsInvalidSessionMessage('401 Unauthorized: invalid token'), isTrue);
  });

  test('ordinary connectivity errors do not trigger logout', () {
    expect(greenVpnIsInvalidSessionMessage('Не удалось связаться с сервисом.'), isFalse);
    expect(greenVpnIsInvalidSessionMessage('VPN-конфиг временно недоступен.'), isFalse);
  });
}
