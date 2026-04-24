import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

void main() {
  PlaybackSource source(String path) => PlaybackSource(
        url: Uri.parse('https://example.com/$path.m3u8'),
      );

  test('room playback controller pre-refreshes MDK on same-source rebind',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
        source: source('same'),
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    final resetLabels = <String>[];
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => source('same'),
      resetEmbeddedPlayerViewAfterBackendRefresh: (label) async {
        resetLabels.add(label);
      },
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    final bound = await controller.bindPlaybackSource(
      playbackSource: source('same'),
      label: 'same-source rebind',
      autoPlay: true,
      currentPlaybackSource: source('same'),
    );

    expect(bound, isTrue);
    expect(
      player.events,
      containsAllInOrder(<String>['refreshBackend', 'setSource', 'play']),
    );
    expect(runtime.refreshCount, 1);
    expect(resetLabels, <String>['same-source rebind']);
  });

  test('room playback controller performs staged MDK texture recovery',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
      pendingSetSourceFailures: 2,
    );
    final runtime = _RefreshTrackingRuntime(player);
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => null,
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    final bound = await controller.bindPlaybackSource(
      playbackSource: source('retry'),
      label: 'retry source',
      autoPlay: true,
    );

    expect(bound, isTrue);
    expect(
      player.events,
      containsAllInOrder(<String>[
        'setSource',
        'stop',
        'setSource',
        'stop',
        'refreshBackend',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  test(
      'room playback controller aborts stale retry after pending target changes',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
      pendingSetSourceFailures: 1,
    );
    final runtime = _RefreshTrackingRuntime(player);
    late final RoomPlaybackController controller;
    var switchedTarget = false;
    controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => null,
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {
        if (!switchedTarget) {
          switchedTarget = true;
          controller.schedulePlaybackBootstrap(
            playbackSource: source('next'),
            hasPlayback: true,
            autoPlay: true,
          );
        }
      },
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: source('old'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();

    expect(player.boundSources.map((value) => value.url.toString()).last,
        'https://example.com/next.m3u8');
    expect(
      player.events,
      containsAllInOrder(<String>['setSource', 'stop', 'setSource', 'play']),
    );
  });

  test(
      'room playback controller stops current runtime when target becomes unavailable',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: source('current'),
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => source('current'),
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: null,
      hasPlayback: false,
      autoPlay: false,
    );
    await scheduler.flush();

    expect(player.events, contains('stop'));
    expect(runtime.currentState.source, isNull);
  });

  test(
      'room playback controller rebinds same target after runtime source was cleared',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => source('same'),
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: source('same'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();
    await runtime.stop();
    player.events.clear();

    controller.schedulePlaybackBootstrap(
      playbackSource: source('same'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();

    expect(
      player.events,
      containsAllInOrder(<String>['setSource', 'play']),
    );
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  test(
      'room playback controller resumes same target when autoplay target is paused',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => source('same'),
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: source('same'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();
    await runtime.pause();
    player.events.clear();

    controller.schedulePlaybackBootstrap(
      playbackSource: source('same'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();

    expect(player.events, contains('play'));
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  test(
      'room playback controller restore uses recovery path before resuming playback',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
      pendingSetSourceFailures: 1,
    );
    final runtime = _RefreshTrackingRuntime(player);
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => source('restore'),
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (_) async {},
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    await controller.restorePlaybackState(
      previousState: PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: source('restore'),
      ),
      label: 'follow transition',
    );

    expect(
      player.events,
      containsAllInOrder(<String>['setSource', 'stop', 'setSource', 'play']),
    );
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  test(
      'room playback controller skips stale twitch bootstrap target after wait-surface',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.ready,
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    late final RoomPlaybackController controller;
    var initialWaitConsumed = false;
    controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.twitch,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => null,
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: scheduler.schedule,
      delay: (duration) async {
        if (!initialWaitConsumed &&
            duration == const Duration(milliseconds: 220)) {
          initialWaitConsumed = true;
          controller.schedulePlaybackBootstrap(
            playbackSource: source('fresh'),
            hasPlayback: true,
            autoPlay: true,
          );
        }
      },
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: source('stale'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();

    expect(
      player.boundSources.map((value) => value.url.toString()),
      <String>['https://example.com/fresh.m3u8'],
    );
    expect(player.events, containsAllInOrder(<String>['setSource', 'play']));
  });

  test(
      'room playback controller waits initial embedded surface bootstrap on android mpv',
      () async {
    final scheduler = _TestPlaybackScheduler();
    final player = _TestPlaybackPlayer(
      initialState: const PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.ready,
      ),
    );
    final runtime = _RefreshTrackingRuntime(player);
    final waitDurations = <Duration>[];
    final controller = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => null,
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      waitForInitialEmbeddedSurfaceBootstrap: true,
      schedulePostFrame: scheduler.schedule,
      delay: (duration) async {
        waitDurations.add(duration);
      },
      waitForEndOfFrame: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(player.dispose);

    controller.schedulePlaybackBootstrap(
      playbackSource: source('initial'),
      hasPlayback: true,
      autoPlay: true,
    );
    await scheduler.flush();

    expect(
      waitDurations,
      contains(const Duration(milliseconds: 220)),
    );
    expect(player.events, containsAllInOrder(<String>['setSource', 'play']));
  });
}

class _TestPlaybackScheduler {
  final Queue<Future<void> Function()> _actions =
      Queue<Future<void> Function()>();

  void schedule(Future<void> Function() action) {
    _actions.add(action);
  }

  Future<void> flush() async {
    while (_actions.isNotEmpty) {
      final action = _actions.removeFirst();
      await action();
    }
  }
}

class _TestPlaybackPlayer implements BasePlayer {
  _TestPlaybackPlayer({
    required PlayerState initialState,
    this.pendingSetSourceFailures = 0,
  }) : _currentState = initialState;

  final List<String> events = <String>[];
  final List<PlaybackSource> boundSources = <PlaybackSource>[];
  int pendingSetSourceFailures;
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;

  @override
  PlayerBackend get backend => _currentState.backend ?? PlayerBackend.mdk;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics =>
      PlayerDiagnostics(backend: backend);

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    boundSources.add(source);
    if (pendingSetSourceFailures > 0) {
      pendingSetSourceFailures -= 1;
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          errorMessage: 'MDK texture initialization timed out after 3000ms',
          clearSource: true,
        ),
      );
      return;
    }
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        clearErrorMessage: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    events.add('play');
    _emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
      ),
    );
  }

  @override
  Future<void> setVolume(double value) async {}

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
    return const SizedBox.shrink();
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _diagnostics.close();
  }

  void handleBackendRefresh() {
    events.add('refreshBackend');
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
        clearErrorMessage: true,
      ),
    );
  }

  void _emit(PlayerState next) {
    _currentState = next.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }
}

class _RefreshTrackingRuntime extends PlayerRuntimeController {
  _RefreshTrackingRuntime(this.player) : super(player);

  final _TestPlaybackPlayer player;
  int refreshCount = 0;

  @override
  Future<void> refreshBackend() async {
    refreshCount += 1;
    player.handleBackendRefresh();
  }

  @override
  Future<void> refreshBackendWithoutPlaybackState() async {
    await refreshBackend();
  }
}
