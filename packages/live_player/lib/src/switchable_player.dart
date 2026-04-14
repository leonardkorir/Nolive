import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'base_player.dart';
import 'memory_player.dart';
import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';
import 'simulated_mdk_player.dart';
import 'simulated_mpv_player.dart';

typedef PlayerBuilder = BasePlayer Function();

class SwitchablePlayer implements BasePlayer {
  SwitchablePlayer({
    PlayerBackend initialBackend = PlayerBackend.memory,
    Map<PlayerBackend, PlayerBuilder>? builders,
  })  : _builders = builders ??
            {
              PlayerBackend.memory: MemoryPlayer.new,
              PlayerBackend.mpv: SimulatedMpvPlayer.new,
              PlayerBackend.mdk: SimulatedMdkPlayer.new,
            },
        _activeBackend = initialBackend,
        _delegate = (builders ??
            {
              PlayerBackend.memory: MemoryPlayer.new,
              PlayerBackend.mpv: SimulatedMpvPlayer.new,
              PlayerBackend.mdk: SimulatedMdkPlayer.new,
            })[initialBackend]!() {
    _attachDelegate();
  }

  final Map<PlayerBackend, PlayerBuilder> _builders;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();

  late BasePlayer _delegate;
  late PlayerBackend _activeBackend;
  StreamSubscription<PlayerState>? _delegateSubscription;
  StreamSubscription<PlayerDiagnostics>? _delegateDiagnosticsSubscription;
  bool _initialized = false;

  List<PlayerBackend> get supportedBackends =>
      _builders.keys.toList(growable: false);

  @override
  PlayerBackend get backend => _activeBackend;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnosticsController.stream;

  @override
  PlayerState get currentState => _delegate.currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _delegate.currentDiagnostics;

  @override
  bool get supportsEmbeddedView => _delegate.supportsEmbeddedView;

  @override
  bool get supportsScreenshot => _delegate.supportsScreenshot;

  Future<void> switchBackend(PlayerBackend nextBackend) async {
    if (nextBackend == _activeBackend) {
      return;
    }
    await _replaceDelegate(nextBackend);
  }

  Future<void> switchBackendWithoutPlaybackState(
    PlayerBackend nextBackend,
  ) async {
    if (nextBackend == _activeBackend) {
      return;
    }
    await _replaceDelegate(
      nextBackend,
      preservePlaybackState: false,
    );
  }

  Future<void> refreshBackend() => _replaceDelegate(_activeBackend);

  Future<void> refreshBackendWithoutPlaybackState() => _replaceDelegate(
        _activeBackend,
        preservePlaybackState: false,
      );

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _delegate.initialize();
  }

  @override
  Future<void> setSource(PlaybackSource source) => _delegate.setSource(source);

  @override
  Future<void> play() => _delegate.play();

  @override
  Future<void> pause() => _delegate.pause();

  @override
  Future<void> stop() => _delegate.stop();

  @override
  Future<void> setVolume(double value) => _delegate.setVolume(value);

  @override
  Future<Uint8List?> captureScreenshot() => _delegate.captureScreenshot();

  @override
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

  @override
  Future<void> dispose() async {
    await _delegateSubscription?.cancel();
    await _delegateDiagnosticsSubscription?.cancel();
    await _stopDelegateBestEffort(_delegate);
    await _delegate.dispose();
    await _stateController.close();
    await _diagnosticsController.close();
  }

  Future<void> _replaceDelegate(
    PlayerBackend nextBackend, {
    bool preservePlaybackState = true,
  }) async {
    final previousState = currentState;
    final source = preservePlaybackState ? previousState.source : null;
    final status =
        preservePlaybackState ? previousState.status : PlaybackStatus.ready;
    final volume = previousState.volume;
    await _delegateSubscription?.cancel();
    await _delegateDiagnosticsSubscription?.cancel();
    await _stopDelegateBestEffort(_delegate);
    await _delegate.dispose();
    _activeBackend = nextBackend;
    _delegate = _builders[nextBackend]!();
    _attachDelegate();
    if (_initialized) {
      await _delegate.initialize();
      await _delegate.setVolume(volume);
      if (source != null) {
        await _delegate.setSource(source);
        if (status == PlaybackStatus.playing) {
          await _delegate.play();
        } else if (status == PlaybackStatus.paused) {
          await _delegate.pause();
        }
      }
    }
  }

  Future<void> _stopDelegateBestEffort(BasePlayer delegate) async {
    final state = delegate.currentState;
    final shouldStop = state.source != null ||
        switch (state.status) {
          PlaybackStatus.buffering ||
          PlaybackStatus.playing ||
          PlaybackStatus.paused ||
          PlaybackStatus.completed ||
          PlaybackStatus.error =>
            true,
          _ => false,
        };
    if (!shouldStop) {
      return;
    }
    try {
      await delegate.stop();
    } catch (_) {
      // Best-effort shutdown before dispose.
    }
  }

  void _attachDelegate() {
    _delegateSubscription = _delegate.states.listen((state) {
      if (!_stateController.isClosed) {
        _stateController.add(state.copyWith(backend: _activeBackend));
      }
    });
    _delegateDiagnosticsSubscription = _delegate.diagnostics.listen((
      diagnostics,
    ) {
      if (!_diagnosticsController.isClosed) {
        _diagnosticsController.add(
          diagnostics.copyWith(backend: _activeBackend),
        );
      }
    });
  }
}
