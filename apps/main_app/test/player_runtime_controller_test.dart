import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

void main() {
  test(
      'ensureBackendWithoutPlaybackState refreshes same backend when source exists',
      () async {
    var buildCount = 0;
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.mpv: () {
          buildCount += 1;
          return _TestSwitchablePlayer(PlayerBackend.mpv);
        },
        PlayerBackend.mdk: () => _TestSwitchablePlayer(PlayerBackend.mdk),
      },
    );
    addTearDown(player.dispose);
    final runtime = PlayerRuntimeController(player);
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
    );

    await runtime.initialize();
    await runtime.setSource(source);
    expect(runtime.currentState.source, isNotNull);

    await runtime.ensureBackendWithoutPlaybackState(PlayerBackend.mpv);

    expect(buildCount, 2);
    expect(runtime.backend, PlayerBackend.mpv);
    expect(runtime.currentState.source, isNull);
  });

  test(
      'ensureBackendWithoutPlaybackState leaves same backend intact when no playback state exists',
      () async {
    var buildCount = 0;
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.mpv: () {
          buildCount += 1;
          return _TestSwitchablePlayer(PlayerBackend.mpv);
        },
        PlayerBackend.mdk: () => _TestSwitchablePlayer(PlayerBackend.mdk),
      },
    );
    addTearDown(player.dispose);
    final runtime = PlayerRuntimeController(player);

    await runtime.initialize();
    await runtime.ensureBackendWithoutPlaybackState(PlayerBackend.mpv);

    expect(buildCount, 1);
    expect(runtime.currentState.source, isNull);
  });
}

class _TestSwitchablePlayer implements BasePlayer {
  _TestSwitchablePlayer(this.playerBackend)
      : _currentState = PlayerState(backend: playerBackend),
        _currentDiagnostics = PlayerDiagnostics(backend: playerBackend);

  final PlayerBackend playerBackend;
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;
  final PlayerDiagnostics _currentDiagnostics;

  @override
  PlayerBackend get backend => playerBackend;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => true;

  @override
  Future<void> initialize() async {
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
      ),
    );
  }

  @override
  Future<void> play() async {
    _emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
      ),
    );
  }

  @override
  Future<void> setVolume(double value) async {
    _emit(_currentState.copyWith(volume: value));
  }

  @override
  Future<Uint8List?> captureScreenshot() async => Uint8List.fromList([1]);

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _diagnostics.close();
  }

  void _emit(PlayerState state) {
    _currentState = state.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
    if (!_diagnostics.isClosed) {
      _diagnostics.add(_currentDiagnostics);
    }
  }
}
