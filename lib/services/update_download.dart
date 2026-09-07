import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

const maxUpdateBytes = 256 * 1024 * 1024;

bool validUpdateIntegrity(String sha256, int size) =>
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256.trim()) &&
    size > 0 &&
    size <= maxUpdateBytes;

Future<bool> updateFileMatches(File file, String sha256, int size) async {
  if (!validUpdateIntegrity(sha256, size) || !await file.exists()) return false;
  if (await file.length() != size) return false;
  final hash = await crypto.sha256.bind(file.openRead()).first;
  return hash.toString().toLowerCase() == sha256.trim().toLowerCase();
}

class UpdateDownloadCancelled implements Exception {}

class UpdateDownloadTask {
  final Duration connectTimeout;
  final Duration idleTimeout;
  final Duration totalTimeout;
  final HttpClient Function() clientFactory;
  HttpClient? _client;
  Object? _cancellation;

  UpdateDownloadTask({
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 25),
    this.totalTimeout = const Duration(minutes: 10),
    HttpClient Function()? clientFactory,
  }) : clientFactory = clientFactory ?? HttpClient.new;

  void cancel([Object? reason]) {
    _cancellation ??= reason ?? UpdateDownloadCancelled();
    _client?.close(force: true);
  }

  void _checkCancellation() {
    final reason = _cancellation;
    if (reason != null) throw reason;
  }

  Future<File> download({
    required Uri uri,
    required File destination,
    required String sha256,
    required int size,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!validUpdateIntegrity(sha256, size)) {
      throw const FormatException('Invalid update integrity metadata');
    }
    _checkCancellation();
    final partial = File('${destination.path}.download');
    final client = clientFactory()..connectionTimeout = connectTimeout;
    _client = client;
    final timer = Timer(
      totalTimeout,
      () => cancel(TimeoutException('Update download deadline')),
    );
    IOSink? sink;
    var completed = false;
    try {
      final request = await client.getUrl(uri).timeout(connectTimeout);
      request.followRedirects = false;
      final response = await request.close().timeout(idleTimeout);
      _checkCancellation();
      if (response.statusCode != HttpStatus.ok ||
          (response.contentLength >= 0 && response.contentLength != size)) {
        throw const FormatException('Invalid update response or length');
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(idleTimeout)) {
        _checkCancellation();
        received += chunk.length;
        if (received > size) {
          throw const FormatException('Update exceeds expected size');
        }
        sink.add(chunk);
        await sink.flush();
        onProgress?.call(received, size);
      }
      await sink.close();
      sink = null;
      _checkCancellation();
      if (received != size || !await updateFileMatches(partial, sha256, size)) {
        throw const FormatException('Update integrity check failed');
      }
      _checkCancellation();
      if (await destination.exists()) await destination.delete();
      final result = await partial.rename(destination.path);
      completed = true;
      return result;
    } catch (error) {
      throw _cancellation ?? error;
    } finally {
      timer.cancel();
      client.close(force: true);
      _client = null;
      try {
        await sink?.close();
      } finally {
        if (!completed && await partial.exists()) await partial.delete();
      }
    }
  }
}
