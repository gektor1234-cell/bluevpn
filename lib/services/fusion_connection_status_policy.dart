class GreenVpnFusionConnectionPresentation {
  final String statusKey;
  final String statusText;
  final String statusDetail;
  final String badgeText;
  final bool protectionActive;
  final bool connectedCheckVisible;

  const GreenVpnFusionConnectionPresentation({
    required this.statusKey,
    required this.statusText,
    required this.statusDetail,
    required this.badgeText,
    required this.protectionActive,
    required this.connectedCheckVisible,
  });
}

String _greenVpnFusionFormatClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

GreenVpnFusionConnectionPresentation greenVpnFusionConnectionPresentation({
  required bool vpnEnabled,
  required bool windowsProtectionConfirmed,
  required bool externalVpnActive,
  required bool socialOnlyEnabled,
  required bool vpnBusy,
  String? vpnBusyStage,
  String? vpnBusyHint,
  required bool paused,
  DateTime? pausedUntil,
  DateTime? now,
}) {
  final protectionActive =
      vpnEnabled && windowsProtectionConfirmed && !externalVpnActive;
  final vpnConflict = vpnEnabled && externalVpnActive;
  final effectiveNow = now ?? DateTime.now();

  final String statusKey;
  final String statusText;
  final String statusDetail;
  if (vpnBusy) {
    statusKey = 'busy';
    statusText =
        vpnBusyStage ?? (vpnEnabled ? 'Отключаем...' : 'Подключаем...');
    statusDetail = vpnBusyHint ?? 'Подождите, Green VPN завершает операцию.';
  } else if (paused) {
    statusKey = 'paused';
    statusText = 'Защита приостановлена';
    statusDetail = pausedUntil == null
        ? 'Нажмите кнопку, чтобы возобновить VPN.'
        : pausedUntil.isAfter(effectiveNow)
        ? 'Автоматически включится в ${_greenVpnFusionFormatClock(pausedUntil)}.'
        : 'Возобновляем защищённое подключение...';
  } else if (externalVpnActive) {
    statusKey = vpnConflict ? 'vpn_conflict' : 'external_vpn';
    statusText = vpnConflict ? 'Конфликт VPN' : 'Активен другой VPN';
    statusDetail = vpnConflict
        ? 'Green VPN и другой VPN запущены одновременно. Защита Green VPN не подтверждена.'
        : 'Нажмите кнопку, чтобы переключиться на Green VPN.';
  } else if (protectionActive) {
    statusKey = socialOnlyEnabled ? 'protected_selected' : 'protected_full';
    statusText = socialOnlyEnabled ? 'Выбранное защищено' : 'Защита активна';
    statusDetail = socialOnlyEnabled
        ? 'Через Green VPN проходят только выбранные приложения и сайты.'
        : 'Весь интернет проходит через Green VPN.';
  } else if (vpnEnabled) {
    statusKey = 'checking';
    statusText = 'Проверяем защиту';
    statusDetail = 'Green VPN запущен, подтверждаем фактический режим трафика.';
  } else {
    statusKey = 'ready';
    statusText = 'Готов к защите';
    statusDetail = 'Подключим первый доступный вариант.';
  }

  final badgeText = protectionActive
      ? (socialOnlyEnabled ? 'ВЫБРАННОЕ ЗАЩИЩЕНО' : 'ЗАЩИЩЕНО')
      : externalVpnActive
      ? 'ДРУГОЙ VPN'
      : vpnEnabled
      ? 'ПРОВЕРКА'
      : paused
      ? 'ПАУЗА'
      : 'НЕ ЗАЩИЩЕНО';

  return GreenVpnFusionConnectionPresentation(
    statusKey: statusKey,
    statusText: statusText,
    statusDetail: statusDetail,
    badgeText: badgeText,
    protectionActive: protectionActive,
    connectedCheckVisible: protectionActive && !vpnBusy,
  );
}
