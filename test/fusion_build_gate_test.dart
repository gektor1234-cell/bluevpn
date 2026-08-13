import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  const expected = bool.fromEnvironment(
    'GREENVPN_EXPECT_FUSION_UI_ENABLED',
    defaultValue: false,
  );

  test('Fusion UI compile-time gate matches the requested release contour', () {
    expect(kFusionUiEnabled, expected);
  });
}
