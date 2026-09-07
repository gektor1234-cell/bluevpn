import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

class _LegacyBackend extends VpnBackend {
  int explicitConnects = 0;
  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    explicitConnects++;
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<VpnBackendResult> disconnect() async =>
      const VpnBackendResult(ok: true);
  @override
  Future<bool> isConnected() async => false;
}

void main() {
  test(
    'legacy backend cannot turn automatic recovery into explicit takeover',
    () async {
      final backend = _LegacyBackend();
      final result = await backend.reconnect(configPath: 'unused');
      expect(result.ok, isFalse);
      expect(backend.explicitConnects, 0);
    },
  );
}
