import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

class PlayerRuntimeController {
  PlayerRuntimeController(this._delegate);

  final BasePlayer _delegate;
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

  Future<void> waitForPendingRoomTeardown() => _pendingRoomTeardown;

  Future<void> serializeRoomTeardown(Future<void> Function() action) {
    final previous = _pendingRoomTeardown;
    final hadPendingRoomTeardown = hasPendingRoomTeardown;
    final completer = Completer<void>();
    _queuedRoomTeardowns += 1;
    _pendingRoomTeardown = completer.future;
    return (() async {
      try {
        if (hadPendingRoomTeardown) {
          await previous;
        }
        await action();
      } finally {
        _queuedRoomTeardowns -= 1;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    })();
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
      PlaybackStatus.error =>
        true,
      _ => false,
    };
  }
}
