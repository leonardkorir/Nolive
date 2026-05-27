import 'dart:async';

class DanmakuActivityWatchdog {
  DanmakuActivityWatchdog({
    required Duration timeout,
    required FutureOr<void> Function() onTimeout,
  })  : _timeout = timeout,
        _onTimeout = onTimeout;

  final Duration _timeout;
  final FutureOr<void> Function() _onTimeout;

  Timer? _timer;
  bool _timedOut = false;

  void start() {
    _reschedule();
  }

  void ping() {
    if (_timedOut) {
      return;
    }
    _reschedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _timedOut = true;
  }

  void _reschedule() {
    _timer?.cancel();
    _timer = Timer(_timeout, _handleTimeout);
  }

  void _handleTimeout() {
    if (_timedOut) {
      return;
    }
    _timedOut = true;
    _timer = null;
    unawaited(Future<void>.sync(_onTimeout));
  }
}
