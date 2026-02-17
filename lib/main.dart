import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const BlueVPNApp());
}

/* =========================
   APP
   ========================= */

class BlueVPNApp extends StatefulWidget {
  const BlueVPNApp({super.key});

  @override
  State<BlueVPNApp> createState() => _BlueVPNAppState();
}

class _BlueVPNAppState extends State<BlueVPNApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F8FC),
    );

    final dark = ThemeData(
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1220),
    );

    return MaterialApp(
      title: 'BlueVPN',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: _themeMode,
      home: RootShell(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

/* =========================
   MODELS
   ========================= */

class ServerLocation {
  final String id;
  final String title;
  final String subtitle;
  final int? pingMs;
  final bool isAuto;

  const ServerLocation({
    required this.id,
    required this.title,
    required this.subtitle,
    this.pingMs,
    this.isAuto = false,
  });
}

enum SocialApp {
  telegram('Telegram', Icons.send_rounded),
  instagram('Instagram', Icons.photo_camera_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  discord('Discord', Icons.forum_rounded),
  youtube('YouTube', Icons.play_circle_fill_rounded);

  const SocialApp(this.title, this.icon);
  final String title;
  final IconData icon;
}

/* =========================
   ROOT SHELL
   ========================= */

class RootShell extends StatefulWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  const RootShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  static const String _tunnelName = 'BlueVPN'; // РёРјСЏ С‚СѓРЅРЅРµР»СЏ (Рё С„Р°Р№Р»Р° РєРѕРЅС„РёРіР°) вЂ” РќР• РўР РћР“РђР•Рњ
  late final VpnBackend _vpnBackend;

  int _index = 0;

  // VPN state
  bool vpnEnabled = false;
  bool vpnBusy = false;

  // вЂњРўРѕР»СЊРєРѕ РґР»СЏ СЃРѕС†СЃРµС‚РµР№вЂќ
  bool socialOnlyEnabled = false;
  final Set<SocialApp> socialOnlyApps = {SocialApp.telegram, SocialApp.instagram};

  // РЎРµСЂРІРµСЂ
  final List<ServerLocation> servers = const [
    ServerLocation(
      id: 'auto',
      title: 'РђРІС‚Рѕ',
      subtitle: 'РЎР°РјР°СЏ Р±С‹СЃС‚СЂР°СЏ Р»РѕРєР°С†РёСЏ',
      pingMs: null,
      isAuto: true,
    ),
    ServerLocation(
      id: 'nl',
      title: 'РќРёРґРµСЂР»Р°РЅРґС‹',
      subtitle: 'РђРјСЃС‚РµСЂРґР°Рј',
      pingMs: 32,
    ),
    ServerLocation(
      id: 'de',
      title: 'Р“РµСЂРјР°РЅРёСЏ',
      subtitle: 'Р¤СЂР°РЅРєС„СѓСЂС‚',
      pingMs: 44,
    ),
    ServerLocation(
      id: 'fi',
      title: 'Р¤РёРЅР»СЏРЅРґРёСЏ',
      subtitle: 'РҐРµР»СЊСЃРёРЅРєРё',
      pingMs: 48,
    ),
    ServerLocation(
      id: 'uk',
      title: 'Р’РµР»РёРєРѕР±СЂРёС‚Р°РЅРёСЏ',
      subtitle: 'Р›РѕРЅРґРѕРЅ',
      pingMs: 58,
    ),
    ServerLocation(
      id: 'us',
      title: 'РЎРЁРђ',
      subtitle: 'РќСЊСЋ-Р™РѕСЂРє',
      pingMs: 120,
    ),
  ];

  ServerLocation selectedServer = const ServerLocation(
    id: 'auto',
    title: 'РђРІС‚Рѕ',
    subtitle: 'РЎР°РјР°СЏ Р±С‹СЃС‚СЂР°СЏ Р»РѕРєР°С†РёСЏ',
    pingMs: null,
    isAuto: true,
  );

  // ===== TARIFF STATE (РѕСЃС‚Р°РІР»СЏРµРј РєР°Рє Р±С‹Р»Рѕ, РЅРѕ РґРѕР±Р°РІРёР»Рё trafficGb РґР»СЏ вЂњР»СЋР±РѕР№ РѕР±СЉС‘РјвЂќ) =====

  // РўР°СЂРёС„-РєРѕРЅСЃС‚СЂСѓРєС‚РѕСЂ (UI-Р»РѕРіРёРєР°)
  final Set<TariffApp> selectedApps = {};
  TrafficPack trafficPack = TrafficPack.gb20; // РёСЃРїРѕР»СЊР·СѓРµРј РєР°Рє вЂњСЂРµР¶РёРјвЂќ (РїРѕ Р“Р‘ / Р±РµР·Р»РёРјРёС‚)
  double trafficGb = 20; // Р»СЋР±РѕР№ РѕР±СЉС‘Рј Р“Р‘
  int devices = 1;

  bool optNoAds = true;
  bool optSmartRouting = true; // СЌС‚РёРј С„Р»Р°РіРѕРј СѓРїСЂР°РІР»СЏРµРј РґРѕСЃС‚СѓРїРЅРѕСЃС‚СЊСЋ вЂњСЃРѕС†СЃРµС‚РµР№вЂќ
  bool optDedicatedIp = false;

  // ===== SETTINGS STATE =====

  bool sAutoStart = false;
  bool sAutoConnect = false;
  bool sNotifications = true;
  bool sKillSwitch = true;
  bool sSplitTunneling = true;
  bool sSendDiagnostics = true;

  String sLanguage = 'Р СѓСЃСЃРєРёР№';
  String sProtocol = 'WireGuard';
  String sDns = 'РђРІС‚Рѕ';

  void goToTab(int i) => setState(() => _index = i);

  String get _configFileName => '$_tunnelName.conf';
  String get _configPath => kIsWeb ? _configFileName : File(_configFileName).absolute.path;

  @override
  void initState() {
    super.initState();
    _vpnBackend = VpnBackend.createDefault(tunnelName: _tunnelName);
    _syncVpnStatus();
  }

  Future<void> _syncVpnStatus() async {
    final on = await _vpnBackend.isConnected();
    if (mounted) setState(() => vpnEnabled = on);
  }

  Future<void> _toggleVpnReal() async {
    if (vpnBusy) return;
    setState(() => vpnBusy = true);

    try {
      if (!vpnEnabled) {
        final conf = File(_configPath);
        if (!conf.existsSync()) {
          _toast(
            context,
            'РќРµС‚ РєРѕРЅС„РёРіР° $_configFileName.\n'
            'РџРѕР»РѕР¶Рё WireGuard-РєРѕРЅС„РёРі СЂСЏРґРѕРј СЃ РїСЂРёР»РѕР¶РµРЅРёРµРј (РёР»Рё РІ РїР°РїРєСѓ Р·Р°РїСѓСЃРєР°) Рё РЅР°Р·РѕРІРё "$_configFileName".',
          );
          return;
        }

        final res = await _vpnBackend.connect(configPath: _configPath);
        if (!res.ok) {
          _toast(context, res.message ?? 'РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕРґРєР»СЋС‡РёС‚СЊ VPN.');
          await _syncVpnStatus();
          return;
        }

        await _syncVpnStatus();
        _toast(context, 'VPN РІРєР»СЋС‡С‘РЅ.');
      } else {
        final res = await _vpnBackend.disconnect();
        if (!res.ok) {
          _toast(context, res.message ?? 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕС‚РєР»СЋС‡РёС‚СЊ VPN.');
          await _syncVpnStatus();
          return;
        }

        await _syncVpnStatus();
        _toast(context, 'VPN РІС‹РєР»СЋС‡РµРЅ.');
      }
    } finally {
      if (mounted) setState(() => vpnBusy = false);
    }
  }

  Future<void> _exportConfigToClipboard() async {
    final conf = File(_configPath);
    if (!conf.existsSync()) {
      _toast(context, 'РљРѕРЅС„РёРі $_configFileName РЅРµ РЅР°Р№РґРµРЅ СЂСЏРґРѕРј СЃ РїСЂРёР»РѕР¶РµРЅРёРµРј.');
      return;
    }
    final text = await conf.readAsString();
    await Clipboard.setData(ClipboardData(text: text));
    _toast(context, 'РљРѕРЅС„РёРі СЃРєРѕРїРёСЂРѕРІР°РЅ РІ Р±СѓС„РµСЂ РѕР±РјРµРЅР°.');
  }

  Future<void> _copyDiagnosticsToClipboard() async {
    final sb = StringBuffer();
    sb.writeln('BlueVPN diagnostics (UI)');
    sb.writeln('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    sb.writeln('Tunnel: $_tunnelName');
    sb.writeln('Config: $_configPath');
    sb.writeln('VPN enabled (UI): $vpnEnabled');
    sb.writeln('Selected server (UI): ${selectedServer.title} / ${selectedServer.subtitle}');
    sb.writeln('Social-only (UI): $socialOnlyEnabled');
    sb.writeln('Social apps (UI): ${socialOnlyApps.map((e) => e.title).join(', ')}');
    sb.writeln('Tariff mode (UI): ${trafficPack.title}');
    sb.writeln('Traffic GB (UI): ${trafficGb.round()}');
    sb.writeln('Unlimited apps (UI): ${selectedApps.map((e) => e.title).join(', ')}');
    sb.writeln('Options (UI): noAds=$optNoAds smartRouting=$optSmartRouting dedicatedIp=$optDedicatedIp');
    sb.writeln('Settings (UI): autoStart=$sAutoStart autoConnect=$sAutoConnect notif=$sNotifications kill=$sKillSwitch split=$sSplitTunneling diag=$sSendDiagnostics');
    sb.writeln('');
    sb.writeln('Backend: ${_vpnBackend.runtimeType}');
    final backendStatus = await _vpnBackend.isConnected();
    sb.writeln('Backend isConnected(): $backendStatus');

    await Clipboard.setData(ClipboardData(text: sb.toString()));
    _toast(context, 'Р”РёР°РіРЅРѕСЃС‚РёРєР° СЃРєРѕРїРёСЂРѕРІР°РЅР° РІ Р±СѓС„РµСЂ.');
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      VpnPage(
        vpnEnabled: vpnEnabled,
        onToggleVpn: () => _toggleVpnReal(),

        // РЎРµСЂРІРµСЂ
        selectedServer: selectedServer,
        onOpenServerPicker: () => _openServerPicker(context),

        // РЎРѕС†СЃРµС‚Рё
        socialOnlyEnabled: socialOnlyEnabled,
        socialOnlyAllowed: optSmartRouting, // РїСЂРёРІСЏР·РєР° Рє С‚Р°СЂРёС„Сѓ
        socialOnlyApps: socialOnlyApps,
        onToggleSocialOnly: (v) {
          if (!optSmartRouting) {
            _toast(context, 'РќРµРґРѕСЃС‚СѓРїРЅРѕ РІ С‚РµРєСѓС‰РµР№ РїРѕРґРїРёСЃРєРµ. Р’РєР»СЋС‡Рё вЂњРЈРјРЅСѓСЋ РјР°СЂС€СЂСѓС‚РёР·Р°С†РёСЋвЂќ РІ С‚Р°СЂРёС„Рµ.');
            return;
          }
          setState(() => socialOnlyEnabled = v);
        },
        onConfigureSocialApps: () {
          if (!optSmartRouting) {
            _toast(context, 'РќРµРґРѕСЃС‚СѓРїРЅРѕ РІ С‚РµРєСѓС‰РµР№ РїРѕРґРїРёСЃРєРµ. Р’РєР»СЋС‡Рё вЂњРЈРјРЅСѓСЋ РјР°СЂС€СЂСѓС‚РёР·Р°С†РёСЋвЂќ РІ С‚Р°СЂРёС„Рµ.');
            return;
          }
          _openSocialAppsPicker(context);
        },

        onOpenTariff: () => goToTab(1),
      ),

      TariffPage(
        selectedApps: selectedApps,
        trafficPack: trafficPack,
        trafficGb: trafficGb,
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
        onTrafficChanged: (p) => setState(() => trafficPack = p),
        onTrafficGbChanged: (gb) => setState(() => trafficGb = gb),
        onDevicesChanged: (v) => setState(() => devices = v.clamp(1, 5)),
        onOptNoAds: (v) => setState(() => optNoAds = v),
        onOptSmartRouting: (v) {
          setState(() {
            optSmartRouting = v;

            // РµСЃР»Рё РѕС‚РєР»СЋС‡РёР»Рё smart routing вЂ” вЂњСЃРѕС†СЃРµС‚РёвЂќ СЃС‚Р°РЅРѕРІСЏС‚СЃСЏ РЅРµРґРѕСЃС‚СѓРїРЅС‹, РіР°СЃРёРј РёС…
            if (!optSmartRouting) {
              socialOnlyEnabled = false;
            }
          });
        },
        onOptDedicatedIp: (v) => setState(() => optDedicatedIp = v),
      ),

      const TasksPage(),

      SettingsPage(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,

        autoStart: sAutoStart,
        autoConnect: sAutoConnect,
        notifications: sNotifications,
        killSwitch: sKillSwitch,
        splitTunneling: sSplitTunneling,
        sendDiagnostics: sSendDiagnostics,

        language: sLanguage,
        protocol: sProtocol,
        dns: sDns,

        onAutoStart: (v) => setState(() => sAutoStart = v),
        onAutoConnect: (v) => setState(() => sAutoConnect = v),
        onNotifications: (v) => setState(() => sNotifications = v),
        onKillSwitch: (v) => setState(() => sKillSwitch = v),
        onSplitTunneling: (v) => setState(() => sSplitTunneling = v),
        onSendDiagnostics: (v) => setState(() => sSendDiagnostics = v),

        onPickLanguage: () => _pickOne(
          context,
          title: 'РЇР·С‹Рє',
          current: sLanguage,
          items: const ['Р СѓСЃСЃРєРёР№', 'English'],
          onSelect: (v) => setState(() => sLanguage = v),
        ),

        onPickProtocol: () => _pickOne(
          context,
          title: 'РџСЂРѕС‚РѕРєРѕР»',
          current: sProtocol,
          items: const ['WireGuard', 'OpenVPN (UI)', 'IKEv2 (UI)'],
          onSelect: (v) => setState(() => sProtocol = v),
        ),

        onPickDns: () => _pickOne(
          context,
          title: 'DNS',
          current: sDns,
          items: const ['РђРІС‚Рѕ', 'Cloudflare (1.1.1.1)', 'Google (8.8.8.8)'],
          onSelect: (v) => setState(() => sDns = v),
        ),

        onAction: (action) => _handleSettingsAction(context, action),
      ),
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
          BottomNavigationBarItem(icon: Icon(Icons.star_rounded), label: 'РўР°СЂРёС„'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Р—Р°РґР°РЅРёСЏ'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'РќР°СЃС‚СЂРѕР№РєРё'),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openServerPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<ServerLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bg = theme.colorScheme.surface;

        return _BottomSheetFrame(
          title: 'Р’С‹Р±РѕСЂ СЃРµСЂРІРµСЂР°',
          subtitle: 'РџРѕРєР° UI. РџРѕР·Р¶Рµ РїРѕРґРєР»СЋС‡РёРј СЂРµР°Р»СЊРЅС‹Рµ Р»РѕРєР°С†РёРё.',
          leading: Icons.bolt_rounded,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  itemCount: servers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = servers[i];
                    final selected = s.id == selectedServer.id;

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(ctx).pop(s),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x140F172A)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark ? const Color(0xFF111827) : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                s.isAuto ? Icons.auto_awesome_rounded : Icons.public_rounded,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.isAuto ? 'РђРІС‚Рѕ-РїРѕРґР±РѕСЂ' : '${s.subtitle}${s.pingMs != null ? ' вЂў ${s.pingMs} ms' : ''}',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                              color: selected ? const Color(0xFF2563EB) : theme.colorScheme.onSurface.withOpacity(0.35),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => selectedServer = picked);
    }
  }

  Future<void> _openSocialAppsPicker(BuildContext context) async {
    // Р»РѕРєР°Р»СЊРЅР°СЏ РєРѕРїРёСЏ РІС‹Р±РѕСЂР°
    final initial = Set<SocialApp>.from(socialOnlyApps);

    final picked = await showModalBottomSheet<Set<SocialApp>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _BottomSheetFrame(
          title: 'РЎРѕС†СЃРµС‚Рё С‡РµСЂРµР· VPN',
          subtitle: 'Р’С‹Р±РµСЂРё РїСЂРёР»РѕР¶РµРЅРёСЏ, РєРѕС‚РѕСЂС‹Рµ РїРѕР№РґСѓС‚ С‡РµСЂРµР· VPN.',
          leading: Icons.filter_alt_rounded,
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.66,
                minChildSize: 0.45,
                maxChildSize: 0.92,
                builder: (_, controller) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            children: [
                              ...SocialApp.values.map((app) {
                                final on = initial.contains(app);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0x140F172A)),
                                    color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  ),
                                  child: SwitchListTile(
                                    value: on,
                                    onChanged: (v) {
                                      setLocal(() {
                                        if (v) {
                                          initial.add(app);
                                        } else {
                                          initial.remove(app);
                                        }
                                      });
                                    },
                                    secondary: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF111827) : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(app.icon, color: const Color(0xFF2563EB)),
                                    ),
                                    title: Text(app.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                                    subtitle: const Text('РўСЂР°С„РёРє СЌС‚РѕРіРѕ РїСЂРёР»РѕР¶РµРЅРёСЏ РїРѕР№РґС‘С‚ С‡РµСЂРµР· VPN'),
                                  ),
                                );
                              }),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(null),
                                  child: const Text('РћС‚РјРµРЅР°', style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () {
                                    if (initial.isEmpty) {
                                      _toast(ctx, 'Р’С‹Р±РµСЂРё С…РѕС‚СЏ Р±С‹ РѕРґРЅРѕ РїСЂРёР»РѕР¶РµРЅРёРµ.');
                                      return;
                                    }
                                    Navigator.of(ctx).pop(initial);
                                  },
                                  child: const Text('Р“РѕС‚РѕРІРѕ', style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        socialOnlyApps
          ..clear()
          ..addAll(picked);
      });
    }
  }

  Future<void> _pickOne(
    BuildContext context, {
    required String title,
    required String current,
    required List<String> items,
    required void Function(String v) onSelect,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _BottomSheetFrame(
          title: title,
          subtitle: 'Р’С‹Р±РµСЂРё Р·РЅР°С‡РµРЅРёРµ',
          leading: Icons.tune_rounded,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final it = items[i];
                final on = it == current;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(ctx).pop(it),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x140F172A)),
                      color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(it, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        Icon(
                          on ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                          color: on ? const Color(0xFF2563EB) : Theme.of(ctx).colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (picked != null) onSelect(picked);
  }

  void _handleSettingsAction(BuildContext context, SettingsAction action) {
    switch (action) {
      case SettingsAction.exportConfig:
        _exportConfigToClipboard();
        break;
      case SettingsAction.copyDiagnostics:
        _copyDiagnosticsToClipboard();
        break;
      case SettingsAction.resetApp:
        _toast(context, 'UI: РїРѕР·Р¶Рµ РґРѕР±Р°РІРёРј СЃР±СЂРѕСЃ РЅР°СЃС‚СЂРѕРµРє/РєСЌС€Р°.');
        break;
      case SettingsAction.about:
        _showAbout(context);
        break;
    }
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('BlueVPN'),
          content: const Text(
            'UI-РїСЂРѕС‚РѕС‚РёРї.\n\n'
            'Р”Р°Р»СЊС€Рµ РїРѕРґРєР»СЋС‡РёРј СЂРµР°Р»СЊРЅС‹Рµ РєРѕРЅС„РёРіРё, Р°РєС‚РёРІР°С†РёСЋ РїРѕРґРїРёСЃРєРё Рё РјР°СЂС€СЂСѓС‚РёР·Р°С†РёСЋ.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('РћРє')),
          ],
        );
      },
    );
  }
}

/* =========================
   VPN PAGE
   ========================= */

class VpnPage extends StatelessWidget {
  final bool vpnEnabled;
  final VoidCallback onToggleVpn;

  final VoidCallback onOpenTariff;

  final ServerLocation selectedServer;
  final VoidCallback onOpenServerPicker;

  final bool socialOnlyEnabled;
  final bool socialOnlyAllowed;
  final Set<SocialApp> socialOnlyApps;
  final ValueChanged<bool> onToggleSocialOnly;
  final VoidCallback onConfigureSocialApps;

  const VpnPage({
    super.key,
    required this.vpnEnabled,
    required this.onToggleVpn,
    required this.onOpenTariff,
    required this.selectedServer,
    required this.onOpenServerPicker,
    required this.socialOnlyEnabled,
    required this.socialOnlyAllowed,
    required this.socialOnlyApps,
    required this.onToggleSocialOnly,
    required this.onConfigureSocialApps,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = vpnEnabled ? 'Р’РєР»СЋС‡РµРЅРѕ' : 'РћС‚РєР»СЋС‡РµРЅРѕ';

    final serverTitle = selectedServer.isAuto ? 'РЎР°РјР°СЏ Р±С‹СЃС‚СЂР°СЏ Р»РѕРєР°С†РёСЏ' : selectedServer.title;
    final serverSub = selectedServer.isAuto
        ? 'РђРІС‚Рѕ-РїРѕРґР±РѕСЂ'
        : '${selectedServer.subtitle}${selectedServer.pingMs != null ? ' вЂў ${selectedServer.pingMs} ms' : ''}';

    final appsText = socialOnlyApps.isEmpty ? 'РќРµ РІС‹Р±СЂР°РЅРѕ' : socialOnlyApps.map((e) => e.title).join(', ');

    final disabledOverlay = !socialOnlyAllowed
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x220F172A)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 6),
                Text(
                  'РўСЂРµР±СѓРµС‚СЃСЏ вЂњРЈРјРЅР°СЏ РјР°СЂС€СЂСѓС‚РёР·Р°С†РёСЏвЂќ',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

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
                  _BigToggle(enabled: vpnEnabled, onTap: onToggleVpn),
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

          // РўРѕР»СЊРєРѕ РґР»СЏ СЃРѕС†СЃРµС‚РµР№
          _Card(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'РўРѕР»СЊРєРѕ РґР»СЏ СЃРѕС†. СЃРµС‚РµР№',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    Switch(
                      value: socialOnlyEnabled,
                      onChanged: socialOnlyAllowed ? onToggleSocialOnly : (_) => onToggleSocialOnly(false),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        socialOnlyEnabled ? 'Р§РµСЂРµР· VPN: $appsText' : 'Р’С‹Р±РµСЂРё РїСЂРёР»РѕР¶РµРЅРёСЏ (РµСЃР»Рё РґРѕСЃС‚СѓРїРЅРѕ РІ РїРѕРґРїРёСЃРєРµ)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: (socialOnlyAllowed && socialOnlyEnabled) ? onConfigureSocialApps : null,
                          child: const Text('РќР°СЃС‚СЂРѕРёС‚СЊ', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        if (!socialOnlyAllowed) Positioned(right: 0, child: disabledOverlay),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // РЎРµСЂРІРµСЂ
          _Card(
            tint: const Color(0xFFEFF6FF),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onOpenServerPicker,
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('РЎРµСЂРІРµСЂ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          serverTitle,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          serverSub,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
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
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(blurRadius: 12, offset: Offset(0, 6), color: Color(0x22000000)),
          ],
        ),
        child: Row(
          children: const [
            Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('РўР°СЂРёС„', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  SizedBox(height: 2),
                  Text(
                    'РўРµРєСѓС‰РёР№: Base вЂў РЅР°СЃС‚СЂРѕР№ РїРѕРґРїРёСЃРєСѓ',
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

enum TrafficPack {
  gb5('5 Р“Р‘', 99),
  gb20('20 Р“Р‘', 199),
  gb50('50 Р“Р‘', 299),
  gb100('100 Р“Р‘', 399),
  unlimited('Р‘РµР·Р»РёРјРёС‚', 799);

  const TrafficPack(this.title, this.basePriceRub);
  final String title;
  final int basePriceRub;
}

class TariffPage extends StatelessWidget {
  final Set<TariffApp> selectedApps;
  final TrafficPack trafficPack;
  final double trafficGb;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;

  final void Function(TariffApp) onToggleApp;
  final void Function(TrafficPack) onTrafficChanged;
  final ValueChanged<double> onTrafficGbChanged;
  final void Function(int) onDevicesChanged;

  final void Function(bool) onOptNoAds;
  final void Function(bool) onOptSmartRouting;
  final void Function(bool) onOptDedicatedIp;

  const TariffPage({
    super.key,
    required this.selectedApps,
    required this.trafficPack,
    required this.trafficGb,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
    required this.onToggleApp,
    required this.onTrafficChanged,
    required this.onTrafficGbChanged,
    required this.onDevicesChanged,
    required this.onOptNoAds,
    required this.onOptSmartRouting,
    required this.onOptDedicatedIp,
  });

  int _basePriceForGb(double gb) {
    final g = gb.clamp(1.0, 500.0);

    const points = <_GbPricePoint>[
      _GbPricePoint(1, 79),
      _GbPricePoint(5, 99),
      _GbPricePoint(20, 199),
      _GbPricePoint(50, 299),
      _GbPricePoint(100, 399),
      _GbPricePoint(200, 499),
      _GbPricePoint(500, 699),
    ];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (g <= b.gb) {
        final t = (g - a.gb) / (b.gb - a.gb);
        final price = a.price + (b.price - a.price) * t;
        return price.round();
      }
    }
    return points.last.price;
  }

  int _calcPriceRub() {
    final isUnlimited = trafficPack == TrafficPack.unlimited;

    final base = isUnlimited ? trafficPack.basePriceRub : _basePriceForGb(trafficGb);

    final apps = isUnlimited ? 0 : selectedApps.length * 49;

    final dev = (devices - 1) * 49;
    final extras = (optNoAds ? 49 : 0) + (optSmartRouting ? 29 : 0) + (optDedicatedIp ? 149 : 0);

    final total = base + apps + dev + extras;
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    final price = _calcPriceRub();

    final appsText = selectedApps.isEmpty ? 'Р‘РµР· Р±РµР·Р»РёРјРёС‚РЅС‹С… РїСЂРёР»РѕР¶РµРЅРёР№' : selectedApps.map((e) => e.title).join(', ');

    final appsDisabled = trafficPack == TrafficPack.unlimited;

    final gbInt = trafficGb.round().clamp(1, 500);
    final baseForGb = appsDisabled ? trafficPack.basePriceRub : _basePriceForGb(trafficGb);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const _PageTitle(
            title: 'РўР°СЂРёС„',
            subtitle: 'Р“РёРіР°Р±Р°Р№С‚С‹ РёР»Рё Р±РµР·Р»РёРјРёС‚ + РґРѕРєСѓРїР°Р№ Р±РµР·Р»РёРјРёС‚ РЅР° РїСЂРёР»РѕР¶РµРЅРёСЏ',
            icon: Icons.star_rounded,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('РўСЂР°С„РёРє'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appsDisabled ? 'Р‘РµР·Р»РёРјРёС‚РЅС‹Р№ С‚СЂР°С„РёРє' : 'РўСЂР°С„РёРє: $gbInt Р“Р‘',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ChipButton(
                            icon: Icons.data_usage_rounded,
                            text: 'РџРѕ Р“Р‘',
                            selected: !appsDisabled,
                            onTap: () => onTrafficChanged(TrafficPack.gb20),
                          ),
                          const SizedBox(width: 8),
                          _ChipButton(
                            icon: Icons.all_inclusive_rounded,
                            text: 'Р‘РµР·Р»РёРјРёС‚',
                            selected: appsDisabled,
                            onTap: () => onTrafficChanged(TrafficPack.unlimited),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Opacity(
                        opacity: appsDisabled ? 0.45 : 1,
                        child: IgnorePointer(
                          ignoring: appsDisabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Slider(
                                value: gbInt.toDouble(),
                                min: 1,
                                max: 500,
                                divisions: 499,
                                label: '$gbInt Р“Р‘',
                                onChanged: (v) => onTrafficGbChanged(v.roundToDouble()),
                              ),
                              Row(
                                children: const [
                                  Text('1 Р“Р‘', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
                                  Spacer(),
                                  Text('500 Р“Р‘', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        appsDisabled ? 'Р‘Р°Р·Р°: $baseForGb в‚Ѕ (Р±РµР·Р»РёРјРёС‚)' : 'Р‘Р°Р·Р°: $baseForGb в‚Ѕ Р·Р° $gbInt Р“Р‘',
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      if (appsDisabled) ...const [
                        SizedBox(height: 10),
                        Text(
                          'Р’С‹Р±СЂР°РЅ вЂњР‘РµР·Р»РёРјРёС‚вЂќ вЂ” Р±РµР·Р»РёРјРёС‚РЅС‹Рµ РїСЂРёР»РѕР¶РµРЅРёСЏ РЅРµ РЅСѓР¶РЅС‹ (Рё РѕС‚РєР»СЋС‡РµРЅС‹).',
                          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Р‘РµР·Р»РёРјРёС‚РЅС‹Рµ РїСЂРёР»РѕР¶РµРЅРёСЏ (РґС‘С€РµРІРѕ)'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: TariffApp.values.map((app) {
                          final on = selectedApps.contains(app);
                          return Opacity(
                            opacity: appsDisabled ? 0.45 : 1,
                            child: IgnorePointer(
                              ignoring: appsDisabled,
                              child: _ChipButton(
                                icon: app.icon,
                                text: app.title,
                                selected: on,
                                onTap: () => onToggleApp(app),
                              ),
                            ),
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
                      const _SectionTitle('РЈСЃС‚СЂРѕР№СЃС‚РІР°'),
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
                              'РЎРєРѕР»СЊРєРѕ РґРµРІР°Р№СЃРѕРІ РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ',
                              style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w700),
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
                      const _SectionTitle('РћРїС†РёРё'),
                      const SizedBox(height: 6),
                      _SwitchRow(
                        title: 'Р‘РµР· СЂРµРєР»Р°РјС‹',
                        subtitle: 'Р§РёСЃС‚С‹Р№ РёРЅС‚РµСЂС„РµР№СЃ РІ РїСЂРёР»РѕР¶РµРЅРёРё',
                        value: optNoAds,
                        onChanged: onOptNoAds,
                      ),
                      const Divider(height: 18),
                      _SwitchRow(
                        title: 'РЈРјРЅР°СЏ РјР°СЂС€СЂСѓС‚РёР·Р°С†РёСЏ',
                        subtitle: 'РќСѓР¶РЅС‹Рµ СЃР°Р№С‚С‹/РїСЂРёР»РѕР¶РµРЅРёСЏ С‡РµСЂРµР· VPN',
                        value: optSmartRouting,
                        onChanged: onOptSmartRouting,
                      ),
                      const Divider(height: 18),
                      _SwitchRow(
                        title: 'Р’С‹РґРµР»РµРЅРЅС‹Р№ IP',
                        subtitle: 'Р”Р»СЏ СЃРІРѕРёС… СЃРµСЂРІРёСЃРѕРІ/РґРѕСЃС‚СѓРїРѕРІ',
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
              color: Theme.of(context).colorScheme.surface,
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
                      const Text('РС‚РѕРіРѕ', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '$price в‚Ѕ / РјРµСЃ',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        trafficPack == TrafficPack.unlimited ? 'Р‘РµР·Р»РёРјРёС‚' : '$gbInt Р“Р‘ вЂў $appsText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12),
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
                      const SnackBar(content: Text('РџРѕРєР° UI рџ™‚ РџРѕР·Р¶Рµ РїРѕРґРєР»СЋС‡РёРј РѕРїР»Р°С‚Сѓ/Р°РєС‚РёРІР°С†РёСЋ.')),
                    );
                  },
                  child: const Text('РћС„РѕСЂРјРёС‚СЊ', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GbPricePoint {
  final double gb;
  final int price;
  const _GbPricePoint(this.gb, this.price);
}

/* =========================
   TASKS PAGE (placeholder)
   ========================= */

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: 'Р—Р°РґР°РЅРёСЏ',
      subtitle: 'РџРѕР·Р¶Рµ РґРѕР±Р°РІРёРј: Р±РѕРЅСѓСЃС‹, СЂРµС„С‹, РїСЂРѕРјРѕ, РµР¶РµРґРЅРµРІРЅС‹Рµ Р·Р°РґР°РЅРёСЏ.',
      icon: Icons.checklist_rounded,
    );
  }
}

/* =========================
   SETTINGS PAGE
   ========================= */

enum SettingsAction { exportConfig, copyDiagnostics, resetApp, about }

class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  final bool autoStart;
  final bool autoConnect;
  final bool notifications;
  final bool killSwitch;
  final bool splitTunneling;
  final bool sendDiagnostics;

  final String language;
  final String protocol;
  final String dns;

  final ValueChanged<bool> onAutoStart;
  final ValueChanged<bool> onAutoConnect;
  final ValueChanged<bool> onNotifications;
  final ValueChanged<bool> onKillSwitch;
  final ValueChanged<bool> onSplitTunneling;
  final ValueChanged<bool> onSendDiagnostics;

  final VoidCallback onPickLanguage;
  final VoidCallback onPickProtocol;
  final VoidCallback onPickDns;

  final void Function(SettingsAction action) onAction;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.autoStart,
    required this.autoConnect,
    required this.notifications,
    required this.killSwitch,
    required this.splitTunneling,
    required this.sendDiagnostics,
    required this.language,
    required this.protocol,
    required this.dns,
    required this.onAutoStart,
    required this.onAutoConnect,
    required this.onNotifications,
    required this.onKillSwitch,
    required this.onSplitTunneling,
    required this.onSendDiagnostics,
    required this.onPickLanguage,
    required this.onPickProtocol,
    required this.onPickDns,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const _PageTitle(
            title: 'РќР°СЃС‚СЂРѕР№РєРё',
            subtitle: 'РЇР·С‹Рє, РїСЂРѕС‚РѕРєРѕР», Р°РІС‚РѕР·Р°РїСѓСЃРє, РґРёР°РіРЅРѕСЃС‚РёРєР°',
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Р’РЅРµС€РЅРёР№ РІРёРґ'),
                const SizedBox(height: 8),
                _SwitchRow(
                  title: 'РўС‘РјРЅР°СЏ С‚РµРјР°',
                  subtitle: 'РњРµРЅСЏРµС‚ С‚РµРјСѓ РїСЂРёР»РѕР¶РµРЅРёСЏ',
                  value: isDark,
                  onChanged: (v) => onThemeModeChanged(v ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('РџСЂРёР»РѕР¶РµРЅРёРµ'),
                const SizedBox(height: 8),
                _SettingsNavRow(
                  title: 'РЇР·С‹Рє',
                  subtitle: language,
                  icon: Icons.language_rounded,
                  onTap: onPickLanguage,
                ),
                const Divider(height: 18),
                _SwitchRow(
                  title: 'РђРІС‚РѕР·Р°РїСѓСЃРє',
                  subtitle: 'Р—Р°РїСѓСЃРєР°С‚СЊ РІРјРµСЃС‚Рµ СЃ Windows',
                  value: autoStart,
                  onChanged: onAutoStart,
                ),
                const Divider(height: 18),
                _SwitchRow(
                  title: 'РђРІС‚РѕРїРѕРґРєР»СЋС‡РµРЅРёРµ',
                  subtitle: 'РџРѕРґРєР»СЋС‡Р°С‚СЊ VPN СЃСЂР°Р·Сѓ РїРѕСЃР»Рµ Р·Р°РїСѓСЃРєР°',
                  value: autoConnect,
                  onChanged: onAutoConnect,
                ),
                const Divider(height: 18),
                _SwitchRow(
                  title: 'РЈРІРµРґРѕРјР»РµРЅРёСЏ',
                  subtitle: 'РЎС‚Р°С‚СѓСЃ, РѕС€РёР±РєРё, РїРѕРґСЃРєР°Р·РєРё',
                  value: notifications,
                  onChanged: onNotifications,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('VPN'),
                const SizedBox(height: 8),
                _SettingsNavRow(
                  title: 'РџСЂРѕС‚РѕРєРѕР»',
                  subtitle: protocol,
                  icon: Icons.swap_horiz_rounded,
                  onTap: onPickProtocol,
                ),
                const Divider(height: 18),
                _SettingsNavRow(
                  title: 'DNS',
                  subtitle: dns,
                  icon: Icons.dns_rounded,
                  onTap: onPickDns,
                ),
                const Divider(height: 18),
                _SwitchRow(
                  title: 'Kill Switch',
                  subtitle: 'Р СѓР±РёС‚ РёРЅС‚РµСЂРЅРµС‚ РїСЂРё РѕР±СЂС‹РІРµ VPN',
                  value: killSwitch,
                  onChanged: onKillSwitch,
                ),
                const Divider(height: 18),
                _SwitchRow(
                  title: 'Split Tunneling',
                  subtitle: 'РСЃРєР»СЋС‡РµРЅРёСЏ (С‡Р°СЃС‚СЊ С‚СЂР°С„РёРєР° РјРёРјРѕ VPN)',
                  value: splitTunneling,
                  onChanged: onSplitTunneling,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Р”РёР°РіРЅРѕСЃС‚РёРєР°'),
                const SizedBox(height: 8),
                _SwitchRow(
                  title: 'РћС‚РїСЂР°РІР»СЏС‚СЊ РґРёР°РіРЅРѕСЃС‚РёРєСѓ',
                  subtitle: 'РђРЅРѕРЅРёРјРЅС‹Рµ Р»РѕРіРё/РєСЂР°С€Рё (РїРѕРєР° UI)',
                  value: sendDiagnostics,
                  onChanged: onSendDiagnostics,
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'РЎРєРѕРїРёСЂРѕРІР°С‚СЊ РѕС‚С‡С‘С‚ РґРёР°РіРЅРѕСЃС‚РёРєРё',
                  subtitle: 'Р›РѕРіРё, СЃРµС‚СЊ, СЃС‚Р°С‚СѓСЃС‹, РєРѕРЅС„РёРі (РїРѕР·Р¶Рµ)',
                  icon: Icons.copy_all_rounded,
                  onTap: () => onAction(SettingsAction.copyDiagnostics),
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'Р­РєСЃРїРѕСЂС‚ РєРѕРЅС„РёРіСѓСЂР°С†РёРё',
                  subtitle: 'Р¤Р°Р№Р» / QR (РїРѕР·Р¶Рµ)',
                  icon: Icons.qr_code_rounded,
                  onTap: () => onAction(SettingsAction.exportConfig),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Рћ РїСЂРёР»РѕР¶РµРЅРёРё'),
                const SizedBox(height: 8),
                _SettingsActionRow(
                  title: 'Рћ BlueVPN',
                  subtitle: 'Р’РµСЂСЃРёСЏ, Р»РёС†РµРЅР·РёРё, РёРЅС„РѕСЂРјР°С†РёСЏ',
                  icon: Icons.info_outline_rounded,
                  onTap: () => onAction(SettingsAction.about),
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'РЎР±СЂРѕСЃРёС‚СЊ РЅР°СЃС‚СЂРѕР№РєРё (UI)',
                  subtitle: 'Р’РµСЂРЅСѓС‚СЊ РґРµС„РѕР»С‚ (РїРѕР·Р¶Рµ)',
                  icon: Icons.restart_alt_rounded,
                  onTap: () => onAction(SettingsAction.resetApp),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

/* =========================
   UI HELPERS
   ========================= */

class _BottomSheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leading;
  final Widget child;

  const _BottomSheetFrame({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark ? const Color(0xFF111827) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(leading, color: const Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PageTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

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
          child: Icon(icon, color: const Color(0xFF2563EB)),
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
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
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
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsNavRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF111827) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurface.withOpacity(0.35)),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF111827) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurface.withOpacity(0.35)),
        ],
      ),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
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

class _Card extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _Card({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint ?? Theme.of(context).colorScheme.surface,
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

/* =========================
   BACKEND (Р Р•РђР›Р¬РќРћР• РџРћР”РљР›Р®Р§Р•РќРР•)
   ========================= */

class VpnBackendResult {
  final bool ok;
  final String? message;
  const VpnBackendResult({required this.ok, this.message});
}

abstract class VpnBackend {
  const VpnBackend();

  Future<VpnBackendResult> connect({required String configPath});
  Future<VpnBackendResult> disconnect();
  Future<bool> isConnected();

  static VpnBackend createDefault({required String tunnelName}) { if (kIsWeb) { return const UnsupportedVpnBackend(reason: 'Web-режим: реальное подключение недоступно. Запусти как Windows: flutter run -d windows'); } if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return UnsupportedVpnBackend(reason: 'РџР»Р°С‚С„РѕСЂРјР° РЅРµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚СЃСЏ РґР»СЏ СЂРµР°Р»СЊРЅРѕРіРѕ РїРѕРґРєР»СЋС‡РµРЅРёСЏ (РїРѕРєР° СЃРґРµР»Р°РЅРѕ РїРѕРґ Windows).');
  }
}

class UnsupportedVpnBackend extends VpnBackend {
  final String reason;
  const UnsupportedVpnBackend({required this.reason});

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    return VpnBackendResult(ok: false, message: reason);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    return VpnBackendResult(ok: false, message: reason);
  }

  @override
  Future<bool> isConnected() async => false;
}

class WireGuardWindowsBackend extends VpnBackend {
  final String tunnelName;
  final String _exe;

  WireGuardWindowsBackend({required this.tunnelName}) : _exe = _resolveWireGuardExe();

  static String _resolveWireGuardExe() {
    final candidates = <String>[];

    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];

    if (pf != null) candidates.add('$pf\\WireGuard\\wireguard.exe');
    if (pf86 != null) candidates.add('$pf86\\WireGuard\\wireguard.exe');

    candidates.add(r'C:\Program Files\WireGuard\wireguard.exe');
    candidates.add(r'C:\Program Files (x86)\WireGuard\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }

    // fallback: РїСѓСЃС‚СЊ РёС‰РµС‚СЃСЏ С‡РµСЂРµР· PATH
    return 'wireguard.exe';
  }

  String get _serviceName => 'WireGuardTunnel\$${tunnelName}';

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(
      exe,
      args,
      runInShell: true,
    );
    // РµСЃР»Рё РЅР°РґРѕ Р±СѓРґРµС‚ вЂ” РґРѕР±Р°РІРёРј workingDirectory/env
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    // Р’РђР–РќРћ: РёРјСЏ С„Р°Р№Р»Р° РґРѕР»Р¶РЅРѕ СЃРѕРІРїР°РґР°С‚СЊ СЃ tunnelName (РґР»СЏ WireGuard for Windows)
    // РќР°РїСЂРёРјРµСЂ: BlueVPN.conf -> С‚СѓРЅРЅРµР»СЊ BlueVPN
    final fileName = File(configPath).uri.pathSegments.isNotEmpty ? File(configPath).uri.pathSegments.last : configPath;
    if (!fileName.toLowerCase().endsWith('.conf')) {
      return const VpnBackendResult(ok: false, message: 'РљРѕРЅС„РёРі РґРѕР»Р¶РµРЅ РёРјРµС‚СЊ СЂР°СЃС€РёСЂРµРЅРёРµ .conf');
    }

    try {
      final res = await _run(_exe, ['/installtunnelservice', configPath]);
      if (res.exitCode != 0) {
        final out = (res.stdout ?? '').toString().trim();
        final err = (res.stderr ?? '').toString().trim();
        return VpnBackendResult(
          ok: false,
          message: 'WireGuard РЅРµ РїРѕРґРЅСЏР»СЃСЏ.\n'
              'Р’РѕР·РјРѕР¶РЅС‹Рµ РїСЂРёС‡РёРЅС‹: РЅРµС‚ РїСЂР°РІ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР° / РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ WireGuard.\n'
              '${err.isNotEmpty ? err : out}',
        );
      }

      // РїСЂРѕРІРµСЂРёРј СЃС‚Р°С‚СѓСЃ
      final ok = await isConnected();
      if (!ok) {
        return const VpnBackendResult(ok: false, message: 'РўСѓРЅРЅРµР»СЊ СѓСЃС‚Р°РЅРѕРІР»РµРЅ, РЅРѕ СЃРµСЂРІРёСЃ РЅРµ РІ СЃРѕСЃС‚РѕСЏРЅРёРё RUNNING.');
      }

      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'РћС€РёР±РєР° Р·Р°РїСѓСЃРєР° WireGuard: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    try {
      final res = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
      if (res.exitCode != 0) {
        final out = (res.stdout ?? '').toString().trim();
        final err = (res.stderr ?? '').toString().trim();
        return VpnBackendResult(
          ok: false,
          message: 'WireGuard РЅРµ РѕС‚РєР»СЋС‡РёР»СЃСЏ.\n'
              'Р’РѕР·РјРѕР¶РЅС‹Рµ РїСЂРёС‡РёРЅС‹: РЅРµС‚ РїСЂР°РІ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°.\n'
              '${err.isNotEmpty ? err : out}',
        );
      }

      final ok = await isConnected();
      if (ok) {
        return const VpnBackendResult(ok: false, message: 'РЎРµСЂРІРёСЃ РІСЃС‘ РµС‰С‘ RUNNING РїРѕСЃР»Рµ РѕС‚РєР»СЋС‡РµРЅРёСЏ.');
      }

      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'РћС€РёР±РєР° РѕС‚РєР»СЋС‡РµРЅРёСЏ WireGuard: $e');
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final res = await _run('sc', ['query', _serviceName]);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('RUNNING');
    } catch (_) {
      return false;
    }
  }
}


