import 'dart:io';

const String greenVpnWindowsRuntimeScope = String.fromEnvironment(
  'GREENVPN_WINDOWS_RUNTIME_SCOPE',
  defaultValue: 'stable',
);
const String greenVpnTunnelName = String.fromEnvironment(
  'GREENVPN_WINDOWS_TUNNEL_NAME',
  defaultValue: 'BlueVPNDev1',
);
const String greenVpnWindowsServiceName = String.fromEnvironment(
  'GREENVPN_WINDOWS_SERVICE_NAME',
  defaultValue: 'GreenVPNService',
);
const String greenVpnProgramDataSubdir = String.fromEnvironment(
  'GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR',
  defaultValue: 'BlueVPN',
);
const String greenVpnUserDataSubdir = String.fromEnvironment(
  'GREENVPN_WINDOWS_USER_DATA_SUBDIR',
  defaultValue: 'GreenVPN',
);
const int greenVpnLocalServicePort = int.fromEnvironment(
  'GREENVPN_WINDOWS_LOCAL_SERVICE_PORT',
  defaultValue: 48737,
);
const String greenVpnProductName = String.fromEnvironment(
  'GREENVPN_PRODUCT_NAME',
  defaultValue: 'Green VPN',
);

const bool greenVpnWindowsRuntimeIsIsolated =
    greenVpnWindowsRuntimeScope != 'stable';

String get greenVpnTunnelServiceName =>
    r'WireGuardTunnel$' + greenVpnTunnelName;

String greenVpnProgramDataRootSync() {
  final base = Platform.environment['ProgramData'];
  if (base != null && base.trim().isNotEmpty) {
    return '$base\\$greenVpnProgramDataSubdir';
  }
  return 'C:\\ProgramData\\$greenVpnProgramDataSubdir';
}

String greenVpnUserDataRootSync() {
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.trim().isNotEmpty) {
    return '$appData\\$greenVpnUserDataSubdir';
  }
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    return '$userProfile\\AppData\\Roaming\\$greenVpnUserDataSubdir';
  }
  return '${Directory.systemTemp.path}\\$greenVpnUserDataSubdir';
}

String greenVpnManagedConfigPathSync() =>
    '${greenVpnProgramDataRootSync()}\\$greenVpnTunnelName.conf';

String greenVpnBaseConfigPathSync() =>
    '${greenVpnProgramDataRootSync()}\\$greenVpnTunnelName.base.conf';

String greenVpnServiceTokenPathSync() =>
    '${greenVpnProgramDataRootSync()}\\service_token';

String greenVpnWindowsRoutingModePathSync() =>
    '${greenVpnProgramDataRootSync()}\\routing_mode';

String greenVpnWindowsRoutingAppsPathSync() =>
    '${greenVpnProgramDataRootSync()}\\routing_apps.json';

String greenVpnBackendLogPathSync() =>
    '${greenVpnProgramDataRootSync()}\\backend.log';

String greenVpnStandbyProbeRequestPathSync() =>
    '${greenVpnProgramDataRootSync()}\\standby-probe-request.json';

String greenVpnStandbyProbeResultPathSync() =>
    '${greenVpnProgramDataRootSync()}\\standby-probe-result.json';

String greenVpnAuthLogPathSync() =>
    '${greenVpnProgramDataRootSync()}\\auth.log';
