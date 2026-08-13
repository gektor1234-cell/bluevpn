import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/fusion_connection_status_policy.dart';

void main() {
  test('full protection is green only after Windows confirmation', () {
    final unconfirmed = greenVpnFusionConnectionPresentation(
      vpnEnabled: true,
      windowsProtectionConfirmed: false,
      externalVpnActive: false,
      socialOnlyEnabled: false,
      vpnBusy: false,
      paused: false,
    );
    expect(unconfirmed.statusKey, 'checking');
    expect(unconfirmed.protectionActive, isFalse);
    expect(unconfirmed.connectedCheckVisible, isFalse);

    final confirmed = greenVpnFusionConnectionPresentation(
      vpnEnabled: true,
      windowsProtectionConfirmed: true,
      externalVpnActive: false,
      socialOnlyEnabled: false,
      vpnBusy: false,
      paused: false,
    );
    expect(confirmed.statusKey, 'protected_full');
    expect(confirmed.statusText, 'Защита активна');
    expect(confirmed.badgeText, 'ЗАЩИЩЕНО');
    expect(confirmed.connectedCheckVisible, isTrue);
  });

  test('selected mode has an explicit protected presentation', () {
    final presentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: true,
      windowsProtectionConfirmed: true,
      externalVpnActive: false,
      socialOnlyEnabled: true,
      vpnBusy: false,
      paused: false,
    );
    expect(presentation.statusKey, 'protected_selected');
    expect(presentation.statusText, 'Выбранное защищено');
    expect(presentation.badgeText, 'ВЫБРАННОЕ ЗАЩИЩЕНО');
    expect(presentation.protectionActive, isTrue);
    expect(presentation.connectedCheckVisible, isTrue);
  });

  test('a competing VPN never produces Green VPN protection', () {
    final presentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: true,
      windowsProtectionConfirmed: true,
      externalVpnActive: true,
      socialOnlyEnabled: false,
      vpnBusy: false,
      paused: false,
    );
    expect(presentation.statusKey, 'vpn_conflict');
    expect(presentation.statusText, 'Конфликт VPN');
    expect(presentation.badgeText, 'ДРУГОЙ VPN');
    expect(presentation.protectionActive, isFalse);
    expect(presentation.connectedCheckVisible, isFalse);
  });

  test('external VPN alone is represented without claiming protection', () {
    final presentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: false,
      windowsProtectionConfirmed: false,
      externalVpnActive: true,
      socialOnlyEnabled: true,
      vpnBusy: false,
      paused: false,
    );
    expect(presentation.statusKey, 'external_vpn');
    expect(presentation.statusText, 'Активен другой VPN');
    expect(presentation.protectionActive, isFalse);
  });

  test('busy state hides the connected check without changing truth', () {
    final presentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: true,
      windowsProtectionConfirmed: true,
      externalVpnActive: false,
      socialOnlyEnabled: false,
      vpnBusy: true,
      vpnBusyStage: 'Обновляем режим...',
      paused: false,
    );
    expect(presentation.statusKey, 'busy');
    expect(presentation.protectionActive, isTrue);
    expect(presentation.connectedCheckVisible, isFalse);
  });
}
