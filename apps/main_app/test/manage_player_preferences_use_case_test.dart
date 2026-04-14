import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

void main() {
  test('apply player preferences refreshes active mpv backend when runtime knobs change', () async {
    final harness = _SwitchableHarness(initialBackend: PlayerBackend.mpv);
    addTearDown(harness.dispose);
    final useCase = ApplyPlayerPreferencesToRuntimeUseCase(
      PlayerRuntimeController(harness.player),
    );

    final current = _preferences();
    final next = current.copyWith(
      mpvLogEnabled: true,
      volume: 0.4,
    );

    await useCase(current: current, next: next);

    expect(harness.instances(PlayerBackend.mpv), hasLength(2));
    expect(harness.player.backend, PlayerBackend.mpv);
    expect(
      harness.latest(PlayerBackend.mpv).events,
      contains('setVolume:0.40'),
    );
  });

  test('apply player preferences switches backend and applies volume', () async {
    final harness = _SwitchableHarness(initialBackend: PlayerBackend.mpv);
    addTearDown(harness.dispose);
    final runtime = PlayerRuntimeController(harness.player);
    final useCase = ApplyPlayerPreferencesToRuntimeUseCase(runtime);

    final current = _preferences();
    final next = current.copyWith(
      backend: PlayerBackend.mdk,
      volume: 0.35,
    );

    await useCase(current: current, next: next);

    expect(runtime.backend, PlayerBackend.mdk);
    expect(harness.instances(PlayerBackend.mpv), hasLength(1));
    expect(harness.instances(PlayerBackend.mdk), hasLength(1));
    expect(
      harness.latest(PlayerBackend.mdk).events,
      contains('setVolume:0.35'),
    );
  });

  test('apply player preferences refreshes active mdk backend when decoder knob changes',
      () async {
    final harness = _SwitchableHarness(initialBackend: PlayerBackend.mdk);
    addTearDown(harness.dispose);
    final useCase = ApplyPlayerPreferencesToRuntimeUseCase(
      PlayerRuntimeController(harness.player),
    );

    final current = _preferences(backend: PlayerBackend.mdk);
    final next = current.copyWith(
      mdkAndroidHardwareVideoDecoderEnabled: false,
    );

    await useCase(current: current, next: next);

    expect(harness.instances(PlayerBackend.mdk), hasLength(2));
    expect(harness.player.backend, PlayerBackend.mdk);
  });
}

PlayerPreferences _preferences({
  PlayerBackend backend = PlayerBackend.mpv,
  double volume = 1.0,
  bool mpvLogEnabled = false,
}) {
  return PlayerPreferences(
    autoPlayEnabled: true,
    preferHighestQuality: false,
    backend: backend,
    volume: volume,
    mpvHardwareAccelerationEnabled: true,
    mpvCompatModeEnabled: false,
    mpvDoubleBufferingEnabled: false,
    mpvCustomOutputEnabled: false,
    mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
    mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
    mpvLogEnabled: mpvLogEnabled,
    mdkLowLatencyEnabled: true,
    mdkAndroidTunnelEnabled: false,
    mdkAndroidHardwareVideoDecoderEnabled: true,
    forceHttpsEnabled: false,
    androidAutoFullscreenEnabled: true,
    androidBackgroundAutoPauseEnabled: true,
    androidPipHideDanmakuEnabled: true,
    scaleMode: PlayerScaleMode.contain,
  );
}

class _SwitchableHarness {
  _SwitchableHarness({required PlayerBackend initialBackend})
      : player = SwitchablePlayer(
          initialBackend: initialBackend,
          builders: {
            PlayerBackend.mpv: () => _buildPlayer(
                  backend: PlayerBackend.mpv,
                  sink: _mpvInstances,
                ),
            PlayerBackend.mdk: () => _buildPlayer(
                  backend: PlayerBackend.mdk,
                  sink: _mdkInstances,
                ),
            PlayerBackend.memory: () => _buildPlayer(
                  backend: PlayerBackend.memory,
                  sink: _memoryInstances,
                ),
          },
        );

  static final List<_TestPlayer> _mpvInstances = <_TestPlayer>[];
  static final List<_TestPlayer> _mdkInstances = <_TestPlayer>[];
  static final List<_TestPlayer> _memoryInstances = <_TestPlayer>[];

  final SwitchablePlayer player;

  List<_TestPlayer> instances(PlayerBackend backend) {
    return switch (backend) {
      PlayerBackend.mpv => _mpvInstances,
      PlayerBackend.mdk => _mdkInstances,
      PlayerBackend.memory => _memoryInstances,
    };
  }

  _TestPlayer latest(PlayerBackend backend) => instances(backend).last;

  Future<void> dispose() async {
    await player.dispose();
    _mpvInstances.clear();
    _mdkInstances.clear();
    _memoryInstances.clear();
  }

  static _TestPlayer _buildPlayer({
    required PlayerBackend backend,
    required List<_TestPlayer> sink,
  }) {
    final player = _TestPlayer(backend);
    sink.add(player);
    return player;
  }
}

class _TestPlayer implements BasePlayer {
  _TestPlayer(this._backend)
      : _currentDiagnostics = PlayerDiagnostics(backend: _backend),
        _currentState = PlayerState(backend: _backend);

  final PlayerBackend _backend;
  final List<String> events = <String>[];
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;
  final PlayerDiagnostics _currentDiagnostics;

  @override
  PlayerBackend get backend => _backend;

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
  bool get supportsScreenshot => false;

  @override
  Future<void> initialize() async {
    events.add('initialize');
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    _currentState = _currentState.copyWith(source: source);
  }

  @override
  Future<void> play() async {
    events.add('play');
    _currentState = _currentState.copyWith(status: PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    _currentState = _currentState.copyWith(status: PlaybackStatus.paused);
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    _currentState = _currentState.copyWith(
      status: PlaybackStatus.ready,
      clearSource: true,
    );
  }

  @override
  Future<void> setVolume(double value) async {
    events.add('setVolume:${value.toStringAsFixed(2)}');
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
    return SizedBox(key: key);
  }

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) {
      await _states.close();
    }
    if (!_diagnostics.isClosed) {
      await _diagnostics.close();
    }
  }
}
