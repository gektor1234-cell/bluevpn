import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  test('public Fusion keeps required connection controls locally enabled', () {
    const disabledByBootstrap = <String, bool>{
      kFusionConnectionActionsFlag: false,
      kFusionConnectionDetailsFlag: false,
      kFusionLocationMemoryFlag: false,
    };

    for (final feature in kFusionRequiredPublicProductFeatures) {
      expect(
        fusionClientFeatureEnabled(
          key: feature,
          serverFeatures: disabledByBootstrap,
          fusionUiEnabled: true,
          publicProductBuild: true,
          productionPromotionCandidate: true,
          developerSession: false,
        ),
        isTrue,
        reason: '$feature is part of the approved public Fusion UI',
      );
    }

    expect(
      fusionClientFeatureEnabled(
        key: kFusionLocationMemoryFlag,
        serverFeatures: disabledByBootstrap,
        fusionUiEnabled: true,
        publicProductBuild: true,
        productionPromotionCandidate: true,
        developerSession: false,
      ),
      isFalse,
      reason: 'non-required features remain controlled by bootstrap',
    );
  });

  test('required controls stay gated outside the public Fusion contour', () {
    for (final feature in kFusionRequiredPublicProductFeatures) {
      expect(
        fusionClientFeatureEnabled(
          key: feature,
          serverFeatures: const <String, bool>{},
          fusionUiEnabled: true,
          publicProductBuild: false,
          productionPromotionCandidate: false,
          developerSession: false,
        ),
        isFalse,
      );
      expect(
        fusionClientFeatureEnabled(
          key: feature,
          serverFeatures: const <String, bool>{},
          fusionUiEnabled: false,
          publicProductBuild: true,
          productionPromotionCandidate: true,
          developerSession: false,
        ),
        isFalse,
      );
    }
  });
}
