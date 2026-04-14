import 'dart:async';

import 'package:flutter/foundation.dart';

typedef TwitchWebPlaybackScheduleTimer = Timer Function(
    Duration duration, void Function() callback);
typedef TwitchWebPlaybackIdleDispose = Future<void> Function(String reason);

class TwitchWebPlaybackLifecycle {
  TwitchWebPlaybackLifecycle({
    required Duration idleDisposeDelay,
    required TwitchWebPlaybackIdleDispose onIdleDispose,
    TwitchWebPlaybackScheduleTimer? scheduleTimer,
  })  : _idleDisposeDelay = idleDisposeDelay,
        _onIdleDispose = onIdleDispose,
        _scheduleTimer = scheduleTimer ?? _defaultScheduleTimer;

  final Duration _idleDisposeDelay;
  final TwitchWebPlaybackIdleDispose _onIdleDispose;
  final TwitchWebPlaybackScheduleTimer _scheduleTimer;

  Timer? _idleDisposeTimer;
  int _activeUseCount = 0;
  int _epoch = 0;

  static Timer _defaultScheduleTimer(
    Duration duration,
    void Function() callback,
  ) {
    return Timer(duration, callback);
  }

  @visibleForTesting
  int get activeUseCount => _activeUseCount;

  @visibleForTesting
  int get epoch => _epoch;

  int beginUse() {
    _cancelIdleDispose();
    _activeUseCount += 1;
    return _epoch;
  }

  void endUse(
    int leaseEpoch, {
    String? idleReason,
  }) {
    if (_activeUseCount > 0) {
      _activeUseCount -= 1;
    }
    if (leaseEpoch != _epoch || _activeUseCount != 0 || idleReason == null) {
      return;
    }
    _scheduleIdleDispose(
      reason: idleReason,
      expectedEpoch: leaseEpoch,
    );
  }

  void invalidate() {
    _cancelIdleDispose();
    _epoch += 1;
  }

  void dispose() {
    _cancelIdleDispose();
    _activeUseCount = 0;
  }

  void _cancelIdleDispose() {
    _idleDisposeTimer?.cancel();
    _idleDisposeTimer = null;
  }

  void _scheduleIdleDispose({
    required String reason,
    required int expectedEpoch,
  }) {
    _cancelIdleDispose();
    _idleDisposeTimer = _scheduleTimer(_idleDisposeDelay, () {
      if (expectedEpoch != _epoch || _activeUseCount != 0) {
        return;
      }
      unawaited(_onIdleDispose(reason));
    });
  }
}
