import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/widgets/android_connection_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/connection_settings');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'sound preference is loaded and persisted; tile is explicitly requested',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'connectionSoundsEnabled' => true,
              'setConnectionSoundsEnabled' => true,
              'requestAddQuickTile' => 'added',
              _ => null,
            };
          });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidConnectionSettings(channel: channel)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      expect(calls, ['connectionSoundsEnabled']);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.tap(find.byKey(const Key('android_add_quick_tile')));
      await tester.pumpAndSettle();
      expect(find.text('Плитка Green VPN добавлена.'), findsOneWidget);
      expect(calls.where((c) => c == 'requestAddQuickTile').length, 1);
    },
  );

  testWidgets(
    'failed save preserves the actual switch; older Android shows manual availability',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'connectionSoundsEnabled' => true,
              'setConnectionSoundsEnabled' => false,
              'requestAddQuickTile' => 'manual',
              _ => null,
            };
          });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidConnectionSettings(channel: channel)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      expect(
        find.text('Не удалось сохранить настройку звука.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('android_add_quick_tile')));
      await tester.pumpAndSettle();
      expect(find.textContaining('редакторе быстрых настроек'), findsOneWidget);
    },
  );
}
