import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

class NfrFrameTimingTelemetry {
  NfrFrameTimingTelemetry._();

  static final NfrFrameTimingTelemetry instance = NfrFrameTimingTelemetry._();
  static const Duration _defaultInterval = Duration(seconds: 10);
  static const Duration _jankThreshold = Duration(microseconds: 16667);

  final List<FrameTiming> _pending = <FrameTiming>[];
  Timer? _timer;
  bool _started = false;

  void start({Duration interval = _defaultInterval}) {
    if (_started || interval <= Duration.zero) {
      return;
    }
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_handleTimings);
    _timer = Timer.periodic(interval, (_) {
      _emit(finalSample: false, reason: 'periodic');
    });
    AppLog.instance.info(
      'nfr/frame',
      'frame timing telemetry start intervalMs=${interval.inMilliseconds} '
          'jankThresholdUs=${_jankThreshold.inMicroseconds}',
    );
  }

  @visibleForTesting
  void stopForTesting({String reason = 'test'}) {
    if (!_started) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _emit(finalSample: true, reason: reason);
    SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    _started = false;
  }

  void _handleTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return;
    }
    _pending.addAll(timings);
  }

  void _emit({required bool finalSample, required String reason}) {
    if (_pending.isEmpty) {
      return;
    }
    final timings = List<FrameTiming>.from(_pending);
    _pending.clear();

    final totalUs =
        timings
            .map((timing) => timing.totalSpan.inMicroseconds)
            .toList(growable: false)
          ..sort();
    final buildUs =
        timings
            .map((timing) => timing.buildDuration.inMicroseconds)
            .toList(growable: false)
          ..sort();
    final rasterUs =
        timings
            .map((timing) => timing.rasterDuration.inMicroseconds)
            .toList(growable: false)
          ..sort();
    final frameCount = timings.length;
    final jankyCount = totalUs
        .where((durationUs) => durationUs > _jankThreshold.inMicroseconds)
        .length;
    final jankPct = frameCount == 0 ? 0 : (jankyCount * 100 / frameCount);

    AppLog.instance.info(
      'nfr/frame',
      'frames=$frameCount janky=$jankyCount '
          'jankPct=${jankPct.toStringAsFixed(2)} '
          'p50TotalMs=${_percentileMs(totalUs, 0.50)} '
          'p90TotalMs=${_percentileMs(totalUs, 0.90)} '
          'p95TotalMs=${_percentileMs(totalUs, 0.95)} '
          'p99TotalMs=${_percentileMs(totalUs, 0.99)} '
          'p90BuildMs=${_percentileMs(buildUs, 0.90)} '
          'p90RasterMs=${_percentileMs(rasterUs, 0.90)} '
          'maxTotalMs=${_durationMs(totalUs.last)} '
          'final=$finalSample reason=$reason',
    );
  }

  @visibleForTesting
  static String percentileMsForTesting(List<int> sortedMicroseconds, double p) {
    return _percentileMs(sortedMicroseconds, p);
  }

  static String _percentileMs(List<int> sortedMicroseconds, double p) {
    if (sortedMicroseconds.isEmpty) {
      return '0.00';
    }
    final index = ((sortedMicroseconds.length - 1) * p).ceil();
    return _durationMs(sortedMicroseconds[index]);
  }

  static String _durationMs(int microseconds) {
    return (microseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(
      2,
    );
  }
}
