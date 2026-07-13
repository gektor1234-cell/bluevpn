import 'dart:io';
import 'dart:convert';

import 'package:greenvpn/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows secure local file can overwrite its hidden file', () async {
    if (!Platform.isWindows) return;

    final directory = await Directory.systemTemp.createTemp(
      'greenvpn_secure_file_test_',
    );
    final path = '${directory.path}\\session.dat';
    final store = SecureLocalFile(path, encrypted: true);
    try {
      await store.writeString('{"value":1}');
      await store.writeString('{"value":2}');

      expect(await store.readString(), '{"value":2}');
      final stored = await File(path).readAsString();
      expect(stored, isNot(contains('{"value"')));
      expect(() => base64Decode(stored.trim()), returnsNormally);
    } finally {
      await WindowsLocalSecurity.preparePrivateFileForWrite(path);
      await Process.run('attrib', ['-h', '-s', '-r', directory.path]);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
