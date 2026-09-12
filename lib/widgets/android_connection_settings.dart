import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AndroidConnectionSettings extends StatefulWidget {
  final MethodChannel channel;
  const AndroidConnectionSettings({super.key, required this.channel});
  @override
  State<AndroidConnectionSettings> createState() =>
      _AndroidConnectionSettingsState();
}

class _AndroidConnectionSettingsState extends State<AndroidConnectionSettings> {
  bool? _sounds;
  bool _saving = false;
  bool _adding = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.channel.invokeMethod<bool>(
        'connectionSoundsEnabled',
      );
      if (mounted) setState(() => _sounds = value ?? false);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось прочитать настройку звука.');
      }
    }
  }

  Future<void> _save(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.channel.invokeMethod<bool>(
        'setConnectionSoundsEnabled',
        {'enabled': value},
      );
      if (saved != true) throw StateError('not_saved');
      if (mounted) {
        setState(() {
          _sounds = value;
          _message = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось сохранить настройку звука.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTile() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final result = await widget.channel.invokeMethod<String>(
        'requestAddQuickTile',
      );
      final message = switch (result) {
        'added' => 'Плитка Green VPN добавлена.',
        'already_added' => 'Плитка Green VPN уже добавлена.',
        'manual' =>
          'Плитка Green VPN доступна в редакторе быстрых настроек Android.',
        'declined' => 'Добавление отменено.',
        'pending' => 'Android уже ожидает ответа.',
        _ =>
          'Android не смог добавить плитку. Она доступна в редакторе быстрых настроек.',
      };
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось открыть системный запрос.');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Подключение', style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Звуки подключения'),
        value: _sounds ?? false,
        onChanged: _sounds == null || _saving ? null : _save,
      ),
      const Divider(height: 18),
      ListTile(
        key: const Key('android_add_quick_tile'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: const Text('Добавить в шторку'),
        trailing: _adding
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        onTap: _adding ? null : _addTile,
      ),
      if (_message != null)
        Text(_message!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
