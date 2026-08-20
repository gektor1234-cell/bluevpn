import 'dart:async';

class SingleFlightOperation {
  Future<void>? _inFlight;

  bool get isRunning => _inFlight != null;

  Future<void> run(Future<void> Function() operation) {
    final existing = _inFlight;
    if (existing != null) return existing;

    late final Future<void> current;
    current = Future<void>.sync(operation).whenComplete(() {
      if (identical(_inFlight, current)) _inFlight = null;
    });
    _inFlight = current;
    return current;
  }
}
