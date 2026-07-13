import 'dart:developer' as developer;

class NfrIsolateTelemetry {
  NfrIsolateTelemetry._();

  static final Map<String, int> _activeByType = <String, int>{};
  static final Map<String, int> _peakByType = <String, int>{};
  static int _sequence = 0;

  static void markStarted(String workerType, {String? detail}) {
    _change(workerType, delta: 1, event: 'started', detail: detail);
  }

  static void markReady(String workerType, {String? detail}) {
    _emit(workerType, event: 'ready', detail: detail);
  }

  static void markStopped(String workerType, {String? detail}) {
    _change(workerType, delta: -1, event: 'stopped', detail: detail);
  }

  static void markFailed(String workerType, Object error, {String? detail}) {
    _change(
      workerType,
      delta: -1,
      event: 'failed',
      detail: _joinDetail(detail, 'error=${error.runtimeType}'),
    );
  }

  static int activeCount(String workerType) {
    return _activeByType[workerType] ?? 0;
  }

  static int peakCount(String workerType) {
    return _peakByType[workerType] ?? 0;
  }

  static void snapshot(String workerType, {String? detail}) {
    _emit(workerType, event: 'snapshot', detail: detail);
  }

  static void _change(
    String workerType, {
    required int delta,
    required String event,
    String? detail,
  }) {
    final next = (_activeByType[workerType] ?? 0) + delta;
    final active = next < 0 ? 0 : next;
    _activeByType[workerType] = active;
    final peak = _peakByType[workerType] ?? 0;
    if (active > peak) {
      _peakByType[workerType] = active;
    }
    _emit(workerType, event: event, detail: detail);
  }

  static void _emit(
    String workerType, {
    required String event,
    String? detail,
  }) {
    _sequence += 1;
    final active = _activeByType[workerType] ?? 0;
    final peak = _peakByType[workerType] ?? 0;
    final suffix = detail == null || detail.isEmpty ? '' : ' $detail';
    final message =
        'workerType=$workerType event=$event active=$active peak=$peak '
        'sequence=$_sequence$suffix';
    developer.log(message, name: 'nfr/isolate');
    // ignore: avoid_print
    print('nfr/isolate $message');
  }

  static String _joinDetail(String? first, String second) {
    if (first == null || first.isEmpty) {
      return second;
    }
    return '$first $second';
  }
}
