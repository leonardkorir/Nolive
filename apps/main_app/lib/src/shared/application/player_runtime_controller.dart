import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

class PlayerRuntimeController {
  PlayerRuntimeController(
    this._delegate, {
    Duration roomTeardownTimeout = defaultRoomTeardownTimeout,
  }) : _roomTeardownTimeout = roomTeardownTimeout;

  /// Bound for a single room teardown action / pending wait.
  ///
  /// Stalled native `stop()` must not leave [hasPendingRoomTeardown] true
  /// indefinitely (observed on ChromeOS ARC after long playback).
  static const Duration defaultRoomTeardownTimeout = Duration(seconds: 5);

  static final Object _roomTeardownZoneKey = Object();

  final BasePlayer _delegate;
  final Duration _roomTeardownTimeout;
  final Set<_BoundedWait> _boundedWaits = <_BoundedWait>{};
  Future<void> _pendingRoomTeardown = Future<void>.value();
  int _queuedRoomTeardowns = 0;

  PlayerBackend get backend => _delegate.backend;

  Stream<PlayerState> get states => _delegate.states;

  Stream<PlayerDiagnostics> get diagnostics => _delegate.diagnostics;

  PlayerState get currentState => _delegate.currentState;

  PlayerDiagnostics get currentDiagnostics => _delegate.currentDiagnostics;

  bool get supportsEmbeddedView => _delegate.supportsEmbeddedView;

  bool get supportsScreenshot => _delegate.supportsScreenshot;

  bool get hasPendingRoomTeardown => _queuedRoomTeardowns > 0;

  Duration get roomTeardownTimeout => _roomTeardownTimeout;

  List<PlayerBackend> get supportedBackends {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      return delegate.supportedBackends;
    }
    return <PlayerBackend>[delegate.backend];
  }

  Future<void> ensureBackend(PlayerBackend nextBackend) async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer && delegate.backend != nextBackend) {
      await delegate.switchBackend(nextBackend);
    }
  }

  Future<void> ensureBackendWithoutPlaybackState(
    PlayerBackend nextBackend,
  ) async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      if (delegate.backend != nextBackend) {
        await delegate.switchBackendWithoutPlaybackState(nextBackend);
        return;
      }
      if (_hasPlaybackState(delegate.currentState)) {
        await delegate.refreshBackendWithoutPlaybackState();
      }
      return;
    }
    if (_hasPlaybackState(currentState)) {
      await _delegate.stop();
    }
  }

  Future<void> switchBackend(PlayerBackend nextBackend) async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      await delegate.switchBackend(nextBackend);
    }
  }

  Future<void> switchBackendWithoutPlaybackState(
    PlayerBackend nextBackend,
  ) async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      await delegate.switchBackendWithoutPlaybackState(nextBackend);
      return;
    }
    await switchBackend(nextBackend);
  }

  Future<void> refreshBackend() async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      await delegate.refreshBackend();
    }
  }

  Future<void> refreshBackendWithoutPlaybackState() async {
    final delegate = _delegate;
    if (delegate is SwitchablePlayer) {
      await delegate.refreshBackendWithoutPlaybackState();
      return;
    }
    await refreshBackend();
  }

  Future<void> initialize() => _delegate.initialize();

  Future<void> setSource(PlaybackSource source) => _delegate.setSource(source);

  Future<void> play() => _delegate.play();

  Future<void> pause() => _delegate.pause();

  Future<void> stop() => _delegate.stop();

  Future<void> setVolume(double value) => _delegate.setVolume(value);

  Future<Uint8List?> captureScreenshot() => _delegate.captureScreenshot();

  Future<void> waitForPendingRoomTeardown({Duration? timeout}) {
    final bound = _effectiveTeardownTimeout(timeout);
    return _awaitBounded(
      _pendingRoomTeardown,
      bound,
      // Pending queue should already drain via serialize timeout; this is a
      // belt-and-suspenders so room load never blocks forever.
      onTimeout: () {},
    );
  }

  /// Cancels every armed teardown watchdog, then disposes the delegate.
  ///
  /// A disposed runtime has no "next room load" left to unblock, so keeping the
  /// watchdogs armed would only leave stray timers behind (which is also what
  /// makes widget tests report pending timers after tearing down a room page).
  Future<void> dispose() async {
    for (final wait in _boundedWaits.toList(growable: false)) {
      wait.abort();
    }
    _boundedWaits.clear();
    await _delegate.dispose();
  }

  Future<void> serializeRoomTeardown(
    Future<void> Function() action, {
    Duration? timeout,
  }) {
    final bound = _effectiveTeardownTimeout(timeout);
    final previous = _pendingRoomTeardown;
    final activeRoomTeardown = Zone.current[_roomTeardownZoneKey];
    final completer = Completer<void>();
    _queuedRoomTeardowns += 1;
    _pendingRoomTeardown = completer.future;
    return runZoned(() async {
      try {
        if (!identical(activeRoomTeardown, previous)) {
          await _awaitBounded(previous, bound, onTimeout: () {});
        }
        await _awaitBounded(action(), bound);
      } on TimeoutException {
        // Release waiters even when stop/cleanup stalls in native code.
      } finally {
        _queuedRoomTeardowns -= 1;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }, zoneValues: <Object?, Object?>{_roomTeardownZoneKey: completer.future});
  }

  Duration _effectiveTeardownTimeout(Duration? timeout) {
    return timeout ?? _roomTeardownTimeout;
  }

  /// Like [Future.timeout], but the watchdog is tracked so [dispose] can cancel
  /// it instead of leaving an armed timer behind.
  Future<void> _awaitBounded(
    Future<void> future,
    Duration bound, {
    void Function()? onTimeout,
  }) {
    if (bound <= Duration.zero) {
      return future;
    }
    final wait = _BoundedWait(future, bound, onTimeout: onTimeout);
    _boundedWaits.add(wait);
    return wait.future.whenComplete(() => _boundedWaits.remove(wait));
  }

  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return _delegate.buildView(
      key: key,
      aspectRatio: aspectRatio,
      fit: fit,
      pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
      resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
    );
  }

  bool _hasPlaybackState(PlayerState state) {
    if (state.source != null) {
      return true;
    }
    return switch (state.status) {
      PlaybackStatus.buffering ||
      PlaybackStatus.playing ||
      PlaybackStatus.paused ||
      PlaybackStatus.completed ||
      PlaybackStatus.error => true,
      _ => false,
    };
  }
}

/// A [Future.timeout]-style bound whose watchdog can be cancelled early.
///
/// [abort] releases waiters without waiting for the wrapped future, which is
/// what lets [PlayerRuntimeController.dispose] tear down cleanly while a native
/// `stop()` is still stalled.
class _BoundedWait {
  _BoundedWait(Future<void> future, this._bound, {void Function()? onTimeout})
    : _onTimeout = onTimeout {
    _timer = Timer(_bound, _fireTimeout);
    future.then(
      (_) => _settle(),
      onError: (Object error, StackTrace stackTrace) =>
          _settle(error, stackTrace),
    );
  }

  final Duration _bound;
  final void Function()? _onTimeout;
  final Completer<void> _completer = Completer<void>();
  late final Timer _timer;

  Future<void> get future => _completer.future;

  void _fireTimeout() {
    if (_completer.isCompleted) {
      return;
    }
    final onTimeout = _onTimeout;
    if (onTimeout != null) {
      onTimeout();
      _completer.complete();
      return;
    }
    _completer.completeError(TimeoutException('operation timed out', _bound));
  }

  void _settle([Object? error, StackTrace? stackTrace]) {
    _timer.cancel();
    if (_completer.isCompleted) {
      return;
    }
    if (error != null) {
      _completer.completeError(error, stackTrace ?? StackTrace.current);
    } else {
      _completer.complete();
    }
  }

  /// Cancels the watchdog and releases waiters. Teardown is over, so this
  /// completes normally rather than surfacing a timeout the caller cannot act
  /// on.
  void abort() {
    _timer.cancel();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
