enum GreenVpnWindowsManagedTunnelState { connected, disconnected, unknown }

enum GreenVpnWindowsRoutingMode { full, applications, unknown }

enum GreenVpnWindowsDiagnosticsConnectionState {
  active,
  inactive,
  checking,
  unknown,
}

const List<String> _greenVpnWindowsSingleProcessStateKeys = <String>[
  'wireGuardState',
  'amneziaWgState',
];

const List<List<String>> _greenVpnWindowsPairedProcessStateKeys =
    <List<String>>[
      <String>['hysteriaClientState', 'hysteriaTunState'],
      <String>['vlessClientState', 'vlessTunState'],
      <String>['naiveClientState', 'naiveTunState'],
      <String>['dnsttClientState', 'dnsttTunState'],
    ];

const Set<String> _greenVpnWindowsStoppedStates = <String>{
  'missing',
  'stopped',
};

String _greenVpnWindowsStatusValue(Object? value) =>
    (value ?? '').toString().trim().toLowerCase();

bool _greenVpnWindowsRuntimeStateIsConsistent(Map<String, dynamic> data) {
  final generation = data['runtimeStateGeneration'];
  return data['runtimeStateGenerationKnown'] == true &&
      data['runtimeStateConsistent'] == true &&
      generation is num &&
      generation.toInt().isEven;
}

GreenVpnWindowsManagedTunnelState greenVpnClassifyWindowsManagedTunnelStatus({
  required bool requestOk,
  required Map<String, dynamic> data,
}) {
  if (!requestOk || data['ok'] != true) {
    return GreenVpnWindowsManagedTunnelState.unknown;
  }

  if (_greenVpnWindowsStatusValue(data['tunnelState']) == 'running') {
    return GreenVpnWindowsManagedTunnelState.connected;
  }
  for (final key in _greenVpnWindowsSingleProcessStateKeys) {
    if (_greenVpnWindowsStatusValue(data[key]) == 'running') {
      return GreenVpnWindowsManagedTunnelState.connected;
    }
  }
  for (final pair in _greenVpnWindowsPairedProcessStateKeys) {
    if (pair.every(
      (key) => _greenVpnWindowsStatusValue(data[key]) == 'running',
    )) {
      return GreenVpnWindowsManagedTunnelState.connected;
    }
  }

  final componentKeys = <String>{
    'tunnelState',
    ..._greenVpnWindowsSingleProcessStateKeys,
    for (final pair in _greenVpnWindowsPairedProcessStateKeys) ...pair,
  };
  final componentStates = componentKeys
      .where(data.containsKey)
      .map((key) => _greenVpnWindowsStatusValue(data[key]))
      .where((state) => state.isNotEmpty)
      .toList(growable: false);
  if (componentStates.isEmpty) {
    return GreenVpnWindowsManagedTunnelState.unknown;
  }
  if (componentStates.every(_greenVpnWindowsStoppedStates.contains)) {
    return GreenVpnWindowsManagedTunnelState.disconnected;
  }
  return GreenVpnWindowsManagedTunnelState.unknown;
}

GreenVpnWindowsRoutingMode greenVpnClassifyWindowsRoutingMode({
  required bool requestOk,
  required Map<String, dynamic> data,
}) {
  if (!requestOk || data['ok'] != true) {
    return GreenVpnWindowsRoutingMode.unknown;
  }
  if (!_greenVpnWindowsRuntimeStateIsConsistent(data)) {
    return GreenVpnWindowsRoutingMode.unknown;
  }
  return switch (_greenVpnWindowsStatusValue(data['routingMode'])) {
    'full' => GreenVpnWindowsRoutingMode.full,
    'applications' => GreenVpnWindowsRoutingMode.applications,
    _ => GreenVpnWindowsRoutingMode.unknown,
  };
}

bool greenVpnWindowsRoutingModeIsConfirmed({
  required bool requestOk,
  required Map<String, dynamic> data,
  required bool applicationsOnly,
  required bool processRouterRequired,
}) {
  if (!_greenVpnWindowsRuntimeStateIsConsistent(data) ||
      data['externalVpnStateKnown'] != true ||
      data['externalVpnActive'] == true ||
      data['processRouterRequirementKnown'] != true) {
    return false;
  }
  final privilegedProcessRouterRequired = data['processRouterRequired'] == true;
  if (privilegedProcessRouterRequired != processRouterRequired) {
    return false;
  }
  final processRouterRunning =
      _greenVpnWindowsStatusValue(data['processRouterState']) == 'running';
  if (processRouterRunning != processRouterRequired) {
    return false;
  }
  if (greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: requestOk,
        data: data,
      ) !=
      GreenVpnWindowsManagedTunnelState.connected) {
    return false;
  }

  final routingMode = greenVpnClassifyWindowsRoutingMode(
    requestOk: requestOk,
    data: data,
  );
  if (!applicationsOnly) {
    return routingMode == GreenVpnWindowsRoutingMode.full &&
        !processRouterRequired;
  }
  if (routingMode != GreenVpnWindowsRoutingMode.applications) {
    return false;
  }
  return !processRouterRequired ||
      _greenVpnWindowsStatusValue(data['processRouterState']) == 'running';
}

GreenVpnWindowsRoutingMode? greenVpnAuthoritativeActiveRoutingMode({
  required bool requestOk,
  required Map<String, dynamic> data,
  required bool processRouterRequired,
}) {
  if (!_greenVpnWindowsRuntimeStateIsConsistent(data) ||
      data['externalVpnStateKnown'] != true ||
      data['externalVpnActive'] == true ||
      data['processRouterRequirementKnown'] != true) {
    return null;
  }
  if (greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: requestOk,
        data: data,
      ) !=
      GreenVpnWindowsManagedTunnelState.connected) {
    return null;
  }
  final routingMode = greenVpnClassifyWindowsRoutingMode(
    requestOk: requestOk,
    data: data,
  );
  final privilegedProcessRouterRequired = data['processRouterRequired'] == true;
  if (privilegedProcessRouterRequired != processRouterRequired) return null;
  final processRouterRunning =
      _greenVpnWindowsStatusValue(data['processRouterState']) == 'running';
  if (processRouterRunning != privilegedProcessRouterRequired) return null;
  if (routingMode == GreenVpnWindowsRoutingMode.full &&
      !privilegedProcessRouterRequired) {
    return routingMode;
  }
  if (routingMode == GreenVpnWindowsRoutingMode.applications &&
      (!privilegedProcessRouterRequired ||
          _greenVpnWindowsStatusValue(data['processRouterState']) ==
              'running')) {
    return routingMode;
  }
  return null;
}

bool greenVpnWindowsUiProtectionIsConfirmed({
  required bool systemStateConfirmed,
  required GreenVpnWindowsRoutingMode routingMode,
  required bool fullTunnelDataPlaneConfirmed,
}) {
  if (!systemStateConfirmed) return false;
  return switch (routingMode) {
    GreenVpnWindowsRoutingMode.full => fullTunnelDataPlaneConfirmed,
    GreenVpnWindowsRoutingMode.applications => true,
    GreenVpnWindowsRoutingMode.unknown => false,
  };
}

GreenVpnWindowsDiagnosticsConnectionState
greenVpnWindowsDiagnosticsConnectionState({
  required bool requestOk,
  required Map<String, dynamic> data,
  required bool fullTunnelDataPlaneConfirmed,
  required bool legacyConnected,
  required bool legacyActivity,
}) {
  if (requestOk && data['ok'] == true) {
    final tunnelState = greenVpnClassifyWindowsManagedTunnelStatus(
      requestOk: requestOk,
      data: data,
    );
    if (tunnelState == GreenVpnWindowsManagedTunnelState.disconnected) {
      return GreenVpnWindowsDiagnosticsConnectionState.inactive;
    }
    if (tunnelState == GreenVpnWindowsManagedTunnelState.unknown) {
      return GreenVpnWindowsDiagnosticsConnectionState.checking;
    }

    final processRouterRequired = data['processRouterRequired'] == true;
    final routingMode = greenVpnAuthoritativeActiveRoutingMode(
      requestOk: requestOk,
      data: data,
      processRouterRequired: processRouterRequired,
    );
    if (routingMode == null) {
      return GreenVpnWindowsDiagnosticsConnectionState.checking;
    }
    return greenVpnWindowsUiProtectionIsConfirmed(
          systemStateConfirmed: true,
          routingMode: routingMode,
          fullTunnelDataPlaneConfirmed: fullTunnelDataPlaneConfirmed,
        )
        ? GreenVpnWindowsDiagnosticsConnectionState.active
        : GreenVpnWindowsDiagnosticsConnectionState.checking;
  }

  if (legacyConnected) {
    return GreenVpnWindowsDiagnosticsConnectionState.active;
  }
  if (legacyActivity) {
    return GreenVpnWindowsDiagnosticsConnectionState.checking;
  }
  return GreenVpnWindowsDiagnosticsConnectionState.unknown;
}
