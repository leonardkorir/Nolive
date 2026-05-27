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

  test('switchable player retries delegate initialization after failure',
      () async {
    final mpvPlayer = _CapturingPlayer(
      PlayerBackend.mpv,
      initializeError: StateError('init failed'),
    );
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => _CapturingPlayer(PlayerBackend.mdk),
      },
    );

    await expectLater(player.initialize(), throwsA(isA<StateError>()));
    await expectLater(player.initialize(), throwsA(isA<StateError>()));

    expect(mpvPlayer.events, ['initialize', 'initialize']);

    await player.dispose();
  });

  test('switchable player stops active delegate before backend replace',
      () async {
    final mpvPlayer = _CapturingPlayer(PlayerBackend.mpv);
    final mdkPlayer = _CapturingPlayer(PlayerBackend.mdk);
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => mdkPlayer,
      },
    );
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();
    await player.switchBackend(PlayerBackend.mdk);

    expect(
      mpvPlayer.events,
      containsAllInOrder(
          ['initialize', 'setSource', 'play', 'stop', 'dispose']),
    );
    expect(
      mdkPlayer.events,
      containsAllInOrder([
        'initialize',
        'setVolume:1.00',
        'setSource',
        'play',
      ]),
    );

    await player.dispose();
  });

  test('switchable player stops active delegate before dispose', () async {
    final mpvPlayer = _CapturingPlayer(PlayerBackend.mpv);
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => _CapturingPlayer(PlayerBackend.mdk),
      },
    );
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();
    await player.dispose();

    expect(
      mpvPlayer.events,
      containsAllInOrder(
          ['initialize', 'setSource', 'play', 'stop', 'dispose']),
    );
  });

  test('switchable player can replace backend without replaying old source',
      () async {
    final mpvPlayer = _CapturingPlayer(PlayerBackend.mpv);
    final mdkPlayer = _CapturingPlayer(PlayerBackend.mdk);
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => mpvPlayer,
        PlayerBackend.mdk: () => mdkPlayer,
      },
    );
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();
    await player.switchBackendWithoutPlaybackState(PlayerBackend.mdk);

    expect(
      mpvPlayer.events,
      containsAllInOrder(
          ['initialize', 'setSource', 'play', 'stop', 'dispose']),
    );
    expect(
      mdkPlayer.events,
      containsAllInOrder([
        'initialize',
        'setVolume:1.00',
      ]),
    );
    expect(mdkPlayer.events, isNot(contains('setSource')));
    expect(mdkPlayer.events, isNot(contains('play')));
    expect(player.currentState.source, isNull);

    await player.dispose();
  });

  test('switchable player serializes concurrent backend replacement requests',
      () async {
    final initialStopCompleter = Completer<void>();
    final initialMpvPlayer = _CapturingPlayer(
      PlayerBackend.mpv,
      stopCompleter: initialStopCompleter,
    );
    final mpvPlayers = <_CapturingPlayer>[initialMpvPlayer];
    final mdkPlayers = <_CapturingPlayer>[];
    var mpvBuildCount = 0;
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () {
          if (mpvBuildCount == 0) {
            mpvBuildCount += 1;
            return initialMpvPlayer;
          }
          final instance = _CapturingPlayer(PlayerBackend.mpv);
          mpvPlayers.add(instance);
          return instance;
        },
        PlayerBackend.mdk: () {
          final instance = _CapturingPlayer(PlayerBackend.mdk);
          mdkPlayers.add(instance);
          return instance;
        },
      },
    );
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();

    final switchFuture = player.switchBackend(PlayerBackend.mdk);
    final refreshFuture = player.refreshBackend();
    await Future<void>.delayed(Duration.zero);
    initialStopCompleter.complete();
    await Future.wait<void>([switchFuture, refreshFuture]);

    expect(player.backend, PlayerBackend.mdk);
    expect(mpvPlayers, hasLength(1));
    expect(mdkPlayers, hasLength(2));

    await player.dispose();
  });

  test('switchable player does not build a new backend after dispose',
      () async {
    final initialStopCompleter = Completer<void>();
    final initialMpvPlayer = _CapturingPlayer(
      PlayerBackend.mpv,
      stopCompleter: initialStopCompleter,
    );
    var mdkBuildCount = 0;
    final player = SwitchablePlayer(
      initialBackend: PlayerBackend.mpv,
      builders: {
        PlayerBackend.memory: () => _CapturingPlayer(PlayerBackend.memory),
        PlayerBackend.mpv: () => initialMpvPlayer,
        PlayerBackend.mdk: () {
          mdkBuildCount += 1;
          return _CapturingPlayer(PlayerBackend.mdk);
        },
      },
    );
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();

    final switchFuture = player.switchBackend(PlayerBackend.mdk);
    await Future<void>.delayed(Duration.zero);
    final disposeFuture = player.dispose();
    await Future<void>.delayed(Duration.zero);
    initialStopCompleter.complete();

    await Future.wait<void>([switchFuture, disposeFuture]);

    expect(mdkBuildCount, 0);
    expect(
      initialMpvPlayer.events,
      containsAllInOrder(
          ['initialize', 'setSource', 'play', 'stop', 'dispose']),
    );
  });
}

class _CapturingPlayer implements BasePlayer {
  _CapturingPlayer(
    this.backend, {
    PlayerDiagnostics? diagnostics,
    this.stopCompleter,
    this.initializeError,
  })  : _currentState = PlayerState(backend: backend),
        _currentDiagnostics = diagnostics ?? PlayerDiagnostics.empty(backend);

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();

  @override
  final PlayerBackend backend;
  final Completer<void>? stopCompleter;
  final Object? initializeError;

  PlayerState _currentState;
  final PlayerDiagnostics _currentDiagnostics;
  final List<String> events = <String>[];
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
  Future<void> initialize() async {
    events.add('initialize');
    final error = initializeError;
    if (error != null) {
      throw error;
    }
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
    final completer = stopCompleter;
    if (completer != null) {
      await completer.future;
    }
    _currentState = _currentState.copyWith(status: PlaybackStatus.ready);
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
    lastKey = key;
    lastAspectRatio = aspectRatio;
    lastFit = fit;
    lastPauseUponEnteringBackgroundMode = pauseUponEnteringBackgroundMode;
    lastResumeUponEnteringForegroundMode = resumeUponEnteringForegroundMode;
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    await _stateController.close();
    await _diagnosticsController.close();
  }
}
