import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/single_flight_operation.dart';

void main() {
  test('concurrent callers join the same operation', () async {
    final gate = Completer<void>();
    final operation = SingleFlightOperation();
    var calls = 0;

    final first = operation.run(() async {
      calls += 1;
      await gate.future;
    });
    final second = operation.run(() async {
      calls += 1;
    });

    expect(identical(first, second), isTrue);
    expect(operation.isRunning, isTrue);
    expect(calls, 1);

    gate.complete();
    await Future.wait([first, second]);
    expect(operation.isRunning, isFalse);
  });

  test('a completed operation permits a later refresh', () async {
    final operation = SingleFlightOperation();
    var calls = 0;

    await operation.run(() async => calls += 1);
    await operation.run(() async => calls += 1);

    expect(calls, 2);
    expect(operation.isRunning, isFalse);
  });

  test('a failed operation clears the in-flight state', () async {
    final operation = SingleFlightOperation();
    var calls = 0;

    await expectLater(
      operation.run(() async {
        calls += 1;
        throw StateError('catalog failed');
      }),
      throwsStateError,
    );
    await operation.run(() async => calls += 1);

    expect(calls, 2);
    expect(operation.isRunning, isFalse);
  });
}
