import 'dart:io';

class WireGuardService {
  // Твой реальный сервис:
  static const String tunnelServiceName = r'WireGuardTunnel$BlueVPN';

  // CLI WireGuard (для логов):
  static const String wireguardExe = r'C:\Program Files\WireGuard\wireguard.exe';

  static Future<String> getServiceState() async {
    final res = await Process.run(
      'sc',
      ['query', tunnelServiceName],
      runInShell: true,
    );

    final out = ('${res.stdout}\n${res.stderr}').toString();
    if (out.contains('STATE') && out.contains('RUNNING')) return 'RUNNING';
    if (out.contains('STATE') && out.contains('STOPPED')) return 'STOPPED';
    if (out.contains('1060') || out.toLowerCase().contains('не установлена')) return 'MISSING';
    return 'UNKNOWN';
  }

  static Future<ExecResult> connect() async => _runNet(['start', tunnelServiceName]);

  static Future<ExecResult> disconnect() async => _runNet(['stop', tunnelServiceName]);

  static Future<ExecResult> dumpLogTail({int lines = 200}) async {
    final res = await Process.run(
      wireguardExe,
      ['/dumplog', '/tail'],
      runInShell: true,
    );

    final full = ('${res.stdout}\n${res.stderr}').trim();
    final split = full.isEmpty ? <String>[] : full.split('\n');
    final tail = split.length <= lines ? split : split.sublist(split.length - lines);

    return ExecResult(
      exitCode: res.exitCode,
      stdout: tail.join('\n'),
      stderr: '',
    );
  }

  static Future<ExecResult> _runNet(List<String> args) async {
    final res = await Process.run('net', args, runInShell: true);
    return ExecResult(
      exitCode: res.exitCode,
      stdout: res.stdout.toString(),
      stderr: res.stderr.toString(),
    );
  }
}

class ExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => exitCode == 0;
}
