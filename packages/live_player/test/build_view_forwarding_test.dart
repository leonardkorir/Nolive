import 'dart:async';

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
}

class _CapturingPlayer implements BasePlayer {
  _CapturingPlayer(this.backend)
      : _currentState = PlayerState(backend: backend);

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  @override
  final PlayerBackend backend;

  PlayerState _currentState;
  Key? lastKey;
  double? lastAspectRatio;
  BoxFit? lastFit;
  bool? lastPauseUponEnteringBackgroundMode;
  bool? lastResumeUponEnteringForegroundMode;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  bool get supportsEmbeddedView => true;

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
  Future<void> dispose() => _stateController.close();
}
