import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/update_download.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late File destination;
  final bytes = List<int>.generate(4096, (index) => index % 251);
  final hash = sha256.convert(bytes).toString();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'greenvpn-update-fixture-',
    );
    destination = File('${directory.path}/fixture.bin');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  Future<File> download(UpdateDownloadTask task, {String? expectedHash}) =>
      task.download(
        uri: Uri.parse('http://127.0.0.1:${server.port}/fixture'),
        destination: destination,
        sha256: expectedHash ?? hash,
        size: bytes.length,
      );
  void respond(List<int> body, {int? length, int status = 200}) {
    server.listen((request) async {
      request.response.statusCode = status;
      if (length != null) request.response.contentLength = length;
      request.response.add(body);
      await request.response.close();
    });
  }

  void expectNoPartial() {
    expect(File('${destination.path}.download').existsSync(), isFalse);
    expect(destination.existsSync(), isFalse);
  }

  test(
    'only exact bytes are committed; modified cache fails revalidation',
    () async {
      respond(bytes, length: bytes.length);
      final file = await download(UpdateDownloadTask());
      expect(await updateFileMatches(file, hash, bytes.length), isTrue);
      await file.writeAsBytes(List<int>.filled(bytes.length, 0));
      expect(await updateFileMatches(file, hash, bytes.length), isFalse);
      expect(File('${destination.path}.download').existsSync(), isFalse);
    },
  );
  test('hash mismatch removes partial and never creates installer', () async {
    respond(bytes);
    await expectLater(
      download(UpdateDownloadTask(), expectedHash: '0' * 64),
      throwsFormatException,
    );
    expectNoPartial();
  });
  test(
    'short and oversized bodies are rejected without trusting headers',
    () async {
      respond(bytes.sublist(0, bytes.length - 1));
      await expectLater(download(UpdateDownloadTask()), throwsFormatException);
      expectNoPartial();
    },
  );
  test('oversized chunk is rejected', () async {
    respond([...bytes, 0]);
    await expectLater(download(UpdateDownloadTask()), throwsFormatException);
    expectNoPartial();
  });
  test('redirects cannot send download to another origin', () async {
    respond([], status: 302);
    await expectLater(download(UpdateDownloadTask()), throwsFormatException);
    expectNoPartial();
  });
  test('missing headers cannot wait forever', () async {
    server.listen((_) {});
    await expectLater(
      download(
        UpdateDownloadTask(idleTimeout: const Duration(milliseconds: 150)),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expectNoPartial();
  });
  test(
    'cancel aborts outstanding request and prevents installer creation',
    () async {
      final arrived = Completer<void>();
      server.listen((_) => arrived.complete());
      final task = UpdateDownloadTask();
      final result = expectLater(
        download(task),
        throwsA(isA<UpdateDownloadCancelled>()),
      );
      await arrived.future;
      task.cancel();
      await result;
      expectNoPartial();
    },
  );
  test('total deadline interrupts an outstanding response', () async {
    server.listen((_) {});
    await expectLater(
      download(
        UpdateDownloadTask(totalTimeout: const Duration(milliseconds: 150)),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expectNoPartial();
  });
}
