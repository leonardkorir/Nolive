import 'dart:async';

/// Coalesces high-frequency UI update signals into short-interval flushes.
///
/// Used by the follow list progressive refresh path so each remote entry
/// resolve does not force a full-page rebuild.
class ProgressiveUiCoalescer {
  ProgressiveUiCoalescer({
    this.interval = const Duration(milliseconds: 120),
    required this.onFlush,
  });

  final Duration interval;
  final void Function() onFlush;

  Timer? _timer;
  bool _pending = false;
  bool _disposed = false;

  /// True when a flush is scheduled and has not run yet.
  bool get hasPendingFlush => _pending || (_timer?.isActive ?? false);

  /// Schedules a coalesced flush; multiple calls within [interval] merge.
  void schedule() {
    if (_disposed) {
      return;
    }
    _pending = true;
    if (_timer?.isActive ?? false) {
      return;
    }
    _timer = Timer(interval, _fire);
  }

  /// Applies immediately (e.g. final refresh result) and cancels the timer.
  void flushNow() {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (!_pending) {
      // Still invoke so callers can force a terminal paint.
      onFlush();
      return;
    }
    _pending = false;
    onFlush();
  }

  /// Drops any scheduled flush without invoking [onFlush].
  ///
  /// Used when a newer refresh generation supersedes in-flight progressive UI.
  void cancel() {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _pending = false;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = false;
  }

  void _fire() {
    _timer = null;
    if (_disposed || !_pending) {
      return;
    }
    _pending = false;
    onFlush();
  }
}
