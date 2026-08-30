class GreenVpnAndroidConnectionUiState {
  final String state;
  final bool desired;
  final bool busy;
  final bool terminal;
  final String? stage;
  final String? hint;

  const GreenVpnAndroidConnectionUiState({
    required this.state,
    required this.desired,
    required this.busy,
    required this.terminal,
    this.stage,
    this.hint,
  });
}

GreenVpnAndroidConnectionUiState greenVpnAndroidConnectionUiState(
  Map<String, dynamic> snapshot,
) {
  final state = (snapshot['state'] ?? 'idle').toString().trim().toLowerCase();
  final desired = snapshot['desired'] == true;
  final pendingConnect =
      desired &&
      const <String>{
        'queued',
        'permission_required',
        'waiting_for_network',
        'fetching_config',
        'connecting',
        'verifying',
        'recovering',
        'error',
      }.contains(state);
  final busy = pendingConnect || state == 'disconnecting';
  final terminal =
      (!desired && state == 'error') ||
      const <String>{
        'cancelled',
        'competing_vpn_active',
        'disconnected',
        'disarmed',
        'permission_denied',
      }.contains(state);

  final (stage, hint) = switch (state) {
    'permission_required' => (
      'Подтвердите подключение...',
      'Android ждёт системное разрешение на VPN.',
    ),
    'waiting_for_network' => (
      'Ожидаем сеть...',
      'Green VPN продолжит подключение сам, когда появится рабочая сеть.',
    ),
    'fetching_config' || 'queued' => (
      'Готовим подключение...',
      'Получаем актуальный маршрут и параметры подключения.',
    ),
    'connecting' => (
      'Запускаем VPN...',
      'Системный компонент устанавливает защищённое подключение.',
    ),
    'verifying' => (
      'Проверяем подключение...',
      'Туннель уже запущен, проверяем доступность сети.',
    ),
    'recovering' || 'error' => (
      'Восстанавливаем подключение...',
      'Green VPN автоматически повторяет безопасное подключение.',
    ),
    'disconnecting' => (
      'Отключаем VPN...',
      'Снимаем VPN-маршрут и освобождаем системное подключение.',
    ),
    _ => (null, null),
  };

  return GreenVpnAndroidConnectionUiState(
    state: state,
    desired: desired,
    busy: busy,
    terminal: terminal,
    stage: stage,
    hint: hint,
  );
}
