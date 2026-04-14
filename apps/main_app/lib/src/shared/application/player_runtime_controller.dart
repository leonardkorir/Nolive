import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

class PlayerRuntimeController {
  const PlayerRuntimeController(this._delegate);

  final BasePlayer _delegate;

  PlayerBackend get backend => _delegate.backend;

  Stream<PlayerState> get states => _delegate.states;

  Stream<PlayerDiagnostics> get diagnostics => _delegate.diagnostics;

  PlayerState get currentState => _delegate.currentState;

  PlayerDiagnostics get currentDiagnostics => _delegate.currentDiagnostics;

  bool get supportsEmbeddedView => _delegate.supportsEmbeddedView;

  bool get supportsScreenshot => _delegate.supportsScreenshot;

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
    if (delegate is SwitchablePlayer && delegate.backend != nextBackend) {
      await delegate.switchBackendWithoutPlaybackState(nextBackend);
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
}
