import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  test('public product catalog uses the protected transport channel', () {
    expect(
      greenVpnCatalogChannelForBuild(
        publicProductBuild: true,
        paidBetaBuild: false,
        updateChannel: 'stable',
      ),
      'public-product',
    );
  });

  test('paid beta and ordinary builds keep their own channels', () {
    expect(
      greenVpnCatalogChannelForBuild(
        publicProductBuild: false,
        paidBetaBuild: true,
        updateChannel: 'stable',
      ),
      'paid-beta',
    );
    expect(
      greenVpnCatalogChannelForBuild(
        publicProductBuild: false,
        paidBetaBuild: false,
        updateChannel: 'preview',
      ),
      'preview',
    );
  });
}
