import 'package:flutter/material.dart';

void main() => runApp(const BlueVPNApp());

class BlueVPNApp extends StatelessWidget {
  const BlueVPNApp({super.key});

  static const blue = Color(0xFF1E66F5);
  static const bg = Color(0xFFF6F9FF);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: bg,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  // mock state
  bool vpnOn = false;
  String plan = "Pro";

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      VpnHome(
        vpnOn: vpnOn,
        plan: plan,
        onToggle: (v) => setState(() => vpnOn = v),
        openTariff: () => setState(() => index = 1),
      ),
      TariffPage(
        plan: plan,
        onChanged: (p) => setState(() => plan = p),
      ),
      const TasksPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.vpn_key_outlined), selectedIcon: Icon(Icons.vpn_key), label: 'VPN'),
          NavigationDestination(icon: Icon(Icons.star_border), selectedIcon: Icon(Icons.star), label: 'Тариф'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Задания'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}

class VpnHome extends StatefulWidget {
  final bool vpnOn;
  final String plan;
  final ValueChanged<bool> onToggle;
  final VoidCallback openTariff;

  const VpnHome({
    super.key,
    required this.vpnOn,
    required this.plan,
    required this.onToggle,
    required this.openTariff,
  });

  @override
  State<VpnHome> createState() => _VpnHomeState();
}

class _VpnHomeState extends State<VpnHome> {
  bool onlySocial = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          // Плашка "Тариф" вместо "Премиум"
          Material(
            color: const Color(0xFF243B63),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.openTariff,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Color(0xFFFFD54A)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Тариф", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(
                            "Текущий: ${widget.plan} • настрой подписку",
                            style: const TextStyle(color: Color(0xFFCBD7FF)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCBD7FF)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Главная большая кнопка
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BigVpnButton(
                    isOn: widget.vpnOn,
                    onTap: () => widget.onToggle(!widget.vpnOn),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.vpnOn ? "Подключено" : "Отключено",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: widget.vpnOn ? cs.primary : const Color(0xFF5B6B8C),
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
                  child: Text("Только для соц. сетей", style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Switch(value: onlySocial, onChanged: (v) => setState(() => onlySocial = v)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          _Card(
            color: const Color(0xFFEAF2FF),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Позже: выбор сервера/локации")),
              );
            },
            child: Row(
              children: const [
                Icon(Icons.bolt, color: Color(0xFF1E66F5)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Сервер", style: TextStyle(color: Color(0xFF5B6B8C))),
                      SizedBox(height: 2),
                      Text("Самая быстрая локация", style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Color(0xFF1E66F5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BigVpnButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback onTap;

  const BigVpnButton({super.key, required this.isOn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isOn ? const Color(0xFF1E66F5) : const Color(0xFF2C3A55);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 260,
        height: 96,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(48),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  isOn ? "ON" : "OFF",
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.fast_forward, color: cs.primary, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TariffPage extends StatelessWidget {
  final String plan;
  final ValueChanged<String> onChanged;

  const TariffPage({super.key, required this.plan, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Тариф", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: cs.primary)),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Выбери план (пока mock)", style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: plan,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: "Base", child: Text("Base")),
                    DropdownMenuItem(value: "Plus", child: Text("Plus")),
                    DropdownMenuItem(value: "Pro", child: Text("Pro")),
                  ],
                  onChanged: (v) => onChanged(v ?? plan),
                ),
                const SizedBox(height: 12),
                const Text("Дальше: конструктор как Yota + цена + оплата.", style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Задания (UI позже)"));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Настройки (UI позже)"));
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;

  const _Card({required this.child, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final base = Material(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );

    if (onTap == null) return base;
    return InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: base);
  }
}
