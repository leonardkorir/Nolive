import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('switchable player forwards background lifecycle view flags', () async {
    final mpvPlayer = _CapturingPlayer(PlayerBackend.mpv);
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => _CapturingPlayer(PlayerBackend.mdk),
      },
    );

    final view = player.buildView(
      key: const ValueKey('room-player'),
      aspectRatio: 16 / 9,
      fit: BoxFit.cover,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: true,
    );

    expect(view, isA<SizedBox>());
    expect(mpvPlayer.lastKey, const ValueKey('room-player'));
    expect(mpvPlayer.lastAspectRatio, 16 / 9);
    expect(mpvPlayer.lastFit, BoxFit.cover);
    expect(mpvPlayer.lastPauseUponEnteringBackgroundMode, isFalse);
    expect(mpvPlayer.lastResumeUponEnteringForegroundMode, isTrue);

    await player.dispose();
  });

  test('switchable player exposes delegate current diagnostics immediately',
      () async {
    final mpvPlayer = _CapturingPlayer(
      PlayerBackend.mpv,
      diagnostics: const PlayerDiagnostics(
        backend: PlayerBackend.mpv,
        width: 1920,
        height: 1080,
      ),
    );
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => _CapturingPlayer(PlayerBackend.mdk),
      },
    );

    expect(player.currentDiagnostics.width, 1920);
    expect(player.currentDiagnostics.height, 1080);

    await player.dispose();
  });
}

class _CapturingPlayer implements BasePlayer {
  _CapturingPlayer(
    this.backend, {
    PlayerDiagnostics? diagnostics,
  })  : _currentState = PlayerState(backend: backend),
        _currentDiagnostics = diagnostics ?? PlayerDiagnostics.empty(backend);

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();

  @override
  final PlayerBackend backend;

  PlayerState _currentState;
  final PlayerDiagnostics _currentDiagnostics;
  Key? lastKey;
  double? lastAspectRatio;
  BoxFit? lastFit;
  bool? lastPauseUponEnteringBackgroundMode;
  bool? lastResumeUponEnteringForegroundMode;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnosticsController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setSource(PlaybackSource source) async {
    _currentState = _currentState.copyWith(source: source);
  }

  @override
  Future<void> play() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.paused);
  }

  @override
  Future<void> stop() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.ready);
  }

  @override
  Future<void> setVolume(double value) async {
    _currentState = _currentState.copyWith(volume: value);
  }

  @override
  Future<Uint8List?> captureScreenshot() async => null;

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    lastKey = key;
    lastAspectRatio = aspectRatio;
    lastFit = fit;
    lastPauseUponEnteringBackgroundMode = pauseUponEnteringBackgroundMode;
    lastResumeUponEnteringForegroundMode = resumeUponEnteringForegroundMode;
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _diagnosticsController.close();
  }
}
