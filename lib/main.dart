import 'package:flutter/material.dart';

void main() {
  runApp(const BlueVPNApp());
}

class BlueVPNApp extends StatelessWidget {
  const BlueVPNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // blue
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      home: const RootShell(),
    );
  }
}

/* =========================
   ROOT SHELL (TABS)
   ========================= */

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // VPN state (fake for now)
  bool vpnEnabled = false;

  // VPN main screen state
  bool socialOnly = false;
  ServerOption selectedServer = const ServerOption(
    id: 'auto',
    title: 'Самая быстрая локация',
    subtitle: 'Авто-подбор',
    pingMs: null,
  );

  // Tariff constructor state (UI only)
  final Set<TariffApp> selectedApps = {};
  double speedMbps = 20; // 5..100
  int devices = 1; // 1..5

  bool optNoAds = true;
  bool optSmartRouting = true;
  bool optDedicatedIp = false;

  void goToTab(int i) => setState(() => _index = i);

  List<ServerOption> get servers => const [
        ServerOption(id: 'auto', title: 'Самая быстрая локация', subtitle: 'Авто-подбор', pingMs: null),
        ServerOption(id: 'nl', title: 'Нидерланды', subtitle: 'Амстердам', pingMs: 32),
        ServerOption(id: 'de', title: 'Германия', subtitle: 'Франкфурт', pingMs: 44),
        ServerOption(id: 'fi', title: 'Финляндия', subtitle: 'Хельсинки', pingMs: 48),
        ServerOption(id: 'uk', title: 'Великобритания', subtitle: 'Лондон', pingMs: 58),
        ServerOption(id: 'us_e', title: 'США', subtitle: 'Нью-Йорк', pingMs: 120),
        ServerOption(id: 'sg', title: 'Сингапур', subtitle: 'SG', pingMs: 210),
      ];

  Future<void> _openServerPicker() async {
    final picked = await showModalBottomSheet<ServerOption>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
                    SizedBox(width: 10),
                    Text(
                      'Выбор сервера',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: servers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = servers[i];
                      final isSelected = s.id == selectedServer.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFEFF6FF),
                          child: Icon(
                            s.id == 'auto' ? Icons.auto_awesome_rounded : Icons.public_rounded,
                            color: const Color(0xFF2563EB),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          s.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        subtitle: Text(
                          s.subtitle +
                              (s.pingMs == null ? '' : ' • ${s.pingMs} ms'),
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB))
                            : const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                        onTap: () => Navigator.pop(ctx, s),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => selectedServer = picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сервер: ${picked.title}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      VpnPage(
        vpnEnabled: vpnEnabled,
        onToggle: () => setState(() => vpnEnabled = !vpnEnabled),
        onOpenTariff: () => goToTab(1),
        socialOnly: socialOnly,
        onSocialOnlyChanged: (v) => setState(() => socialOnly = v),
        server: selectedServer,
        onPickServer: _openServerPicker,
      ),
      TariffPage(
        selectedApps: selectedApps,
        speedMbps: speedMbps,
        devices: devices,
        optNoAds: optNoAds,
        optSmartRouting: optSmartRouting,
        optDedicatedIp: optDedicatedIp,
        onToggleApp: (app) {
          setState(() {
            if (selectedApps.contains(app)) {
              selectedApps.remove(app);
            } else {
              selectedApps.add(app);
            }
          });
        },
        onSpeedChanged: (v) => setState(() => speedMbps = v),
        onDevicesChanged: (v) => setState(() => devices = v.clamp(1, 5).toInt()),
        onOptNoAds: (v) => setState(() => optNoAds = v),
        onOptSmartRouting: (v) => setState(() => optSmartRouting = v),
        onOptDedicatedIp: (v) => setState(() => optDedicatedIp = v),
      ),
      const TasksPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.vpn_key_rounded), label: 'VPN'),
          BottomNavigationBarItem(icon: Icon(Icons.star_rounded), label: 'Тариф'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Задания'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Настройки'),
        ],
      ),
    );
  }
}

/* =========================
   VPN PAGE
   ========================= */

class VpnPage extends StatelessWidget {
  final bool vpnEnabled;
  final VoidCallback onToggle;
  final VoidCallback onOpenTariff;

  final bool socialOnly;
  final ValueChanged<bool> onSocialOnlyChanged;

  final ServerOption server;
  final VoidCallback onPickServer;

  const VpnPage({
    super.key,
    required this.vpnEnabled,
    required this.onToggle,
    required this.onOpenTariff,
    required this.socialOnly,
    required this.onSocialOnlyChanged,
    required this.server,
    required this.onPickServer,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = vpnEnabled ? 'Включено' : 'Отключено';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _TariffBanner(onTap: onOpenTariff),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BigToggle(enabled: vpnEnabled, onTap: onToggle),
                  const SizedBox(height: 14),
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Card(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Только для соц. сетей',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                Switch(
                  value: socialOnly,
                  onChanged: onSocialOnlyChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPickServer,
            child: _Card(
              tint: const Color(0xFFEFF6FF),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Сервер', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          server.title,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          server.subtitle + (server.pingMs == null ? '' : ' • ${server.pingMs} ms'),
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TariffBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _TariffBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A), // deep blue
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(blurRadius: 12, offset: Offset(0, 6), color: Color(0x22000000)),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Тариф', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  SizedBox(height: 2),
                  Text(
                    'Текущий: Base • настрой подписку',
                    style: TextStyle(color: Color(0xFFBFDBFE), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Color(0xFFBFDBFE)),
          ],
        ),
      ),
    );
  }
}

class _BigToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _BigToggle({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? const Color(0xFF2563EB) : const Color(0xFF334155);
    final knob = enabled ? const Color(0xFFEFF6FF) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 210,
        height: 72,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            BoxShadow(blurRadius: 18, offset: Offset(0, 10), color: Color(0x22000000)),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: knob,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  enabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: enabled ? const Color(0xFF2563EB) : const Color(0xFF334155),
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   SERVER MODEL
   ========================= */

class ServerOption {
  final String id;
  final String title;
  final String subtitle;
  final int? pingMs;

  const ServerOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.pingMs,
  });
}

/* =========================
   TARIFF PAGE
   ========================= */

enum TariffApp {
  youtube('YouTube', Icons.play_circle_fill_rounded),
  telegram('Telegram', Icons.send_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  instagram('Instagram', Icons.photo_camera_rounded),
  discord('Discord', Icons.forum_rounded),
  steam('Steam', Icons.sports_esports_rounded),
  netflix('Netflix', Icons.movie_rounded);

  const TariffApp(this.title, this.icon);
  final String title;
  final IconData icon;
}

class TariffPage extends StatelessWidget {
  final Set<TariffApp> selectedApps;
  final double speedMbps;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;

  final void Function(TariffApp) onToggleApp;
  final void Function(double) onSpeedChanged;
  final void Function(int) onDevicesChanged;

  final void Function(bool) onOptNoAds;
  final void Function(bool) onOptSmartRouting;
  final void Function(bool) onOptDedicatedIp;

  const TariffPage({
    super.key,
    required this.selectedApps,
    required this.speedMbps,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
    required this.onToggleApp,
    required this.onSpeedChanged,
    required this.onDevicesChanged,
    required this.onOptNoAds,
    required this.onOptSmartRouting,
    required this.onOptDedicatedIp,
  });

  int _calcPriceRub() {
    // Fake formula (replace later)
    final base = 99;
    final apps = selectedApps.length * 29;
    final speed = ((speedMbps - 5) / 5).round() * 8;
    final dev = (devices - 1) * 49;

    final extras = (optNoAds ? 49 : 0) + (optSmartRouting ? 29 : 0) + (optDedicatedIp ? 149 : 0);

    final total = base + apps + speed + dev + extras;
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    final price = _calcPriceRub();

    final appsText = selectedApps.isEmpty ? 'Ничего не выбрано' : selectedApps.map((e) => e.title).join(', ');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const _PageTitle('Тариф', subtitle: 'Собери подписку под себя (пока только UI)'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Выбери сервисы'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: TariffApp.values.map((app) {
                          final on = selectedApps.contains(app);
                          return _ChipButton(
                            icon: app.icon,
                            text: app.title,
                            selected: on,
                            onTap: () => onToggleApp(app),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Скорость'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('5', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                          Expanded(
                            child: Slider(
                              min: 5,
                              max: 100,
                              divisions: 19,
                              value: speedMbps,
                              onChanged: onSpeedChanged,
                            ),
                          ),
                          Text(
                            '${speedMbps.round()} Мбит/с',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Устройства'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => onDevicesChanged(devices - 1),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$devices',
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                            ),
                          ),
                          IconButton(
                            onPressed: () => onDevicesChanged(devices + 1),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Сколько девайсов одновременно',
                              style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Опции'),
                      const SizedBox(height: 6),
                      _SwitchRow(
                        title: 'Без рекламы',
                        subtitle: 'Чистый интерфейс в приложении',
                        value: optNoAds,
                        onChanged: onOptNoAds,
                      ),
                      const Divider(height: 18),
                      _SwitchRow(
                        title: 'Умная маршрутизация',
                        subtitle: 'Только нужные сайты через VPN',
                        value: optSmartRouting,
                        onChanged: onOptSmartRouting,
                      ),
                      const Divider(height: 18),
                      _SwitchRow(
                        title: 'Выделенный IP',
                        subtitle: 'Для своих сервисов/доступов',
                        value: optDedicatedIp,
                        onChanged: onOptDedicatedIp,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 110),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(blurRadius: 18, offset: Offset(0, 10), color: Color(0x1A000000)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Итого', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '$price ₽ / мес',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appsText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Пока UI 🙂 Позже подключим оплату/активацию.')),
                    );
                  },
                  child: const Text('Оформить', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PageTitle(this.title, {required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.star_rounded, color: Color(0xFF2563EB)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ChipButton({
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF2563EB) : const Color(0xFFEFF6FF);
    final fg = selected ? Colors.white : const Color(0xFF1E3A8A);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x1A1E3A8A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

/* =========================
   OTHER PAGES (placeholders)
   ========================= */

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: 'Задания',
      subtitle: 'Позже добавим: бонусы, рефы, промо, ежедневные задания.',
      icon: Icons.checklist_rounded,
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: 'Настройки',
      subtitle: 'Позже добавим: язык, автозапуск, протокол, диагностика.',
      icon: Icons.settings_rounded,
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _Card(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* =========================
   UI CARD
   ========================= */

class _Card extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _Card({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x110F172A)),
        boxShadow: const [
          BoxShadow(blurRadius: 14, offset: Offset(0, 8), color: Color(0x14000000)),
        ],
      ),
      child: child,
    );
  }
}
