import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_player_runtime_observer.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  PlaybackSource source(String path) => PlaybackSource(
        url: Uri.parse('https://example.com/$path.m3u8'),
      );

  Future<void> flushEvents() async {
    await Future<void>.delayed(Duration.zero);
  }

  test('room player runtime observer forwards player state updates', () async {
    final player = TestRecordingPlayer();
    final runtime = PlayerRuntimeController(player);
    final traces = <String>[];
    final forwarded = <({PlaybackStatus status, bool playbackAvailable})>[];
    final observer = RoomPlayerRuntimeObserver(
      context: RoomPlayerRuntimeObserverContext(
        providerId: ProviderId.bilibili,
        roomId: '6',
        runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
        trace: traces.add,
        resolvePlaybackAvailable: () => true,
        onPlayerStateChanged: (
          state, {
          required playbackAvailable,
        }) {
          forwarded.add((
            status: state.status,
            playbackAvailable: playbackAvailable,
          ));
        },
      ),
    );
    addTearDown(observer.dispose);
    addTearDown(player.dispose);

    observer.attach();
    observer.syncCurrentState();
    player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: source('room'),
      ),
    );
    await flushEvents();

    expect(forwarded, hasLength(2));
    expect(forwarded.last.status, PlaybackStatus.playing);
    expect(forwarded.last.playbackAvailable, isTrue);
    expect(
      traces.where((entry) => entry.contains('player status=playing')),
      hasLength(1),
    );
  });

  test('room player runtime observer resets diagnostics dedupe after source change',
      () async {
    final player = TestRecordingPlayer();
    final runtime = PlayerRuntimeController(player);
    final traces = <String>[];
    final observer = RoomPlayerRuntimeObserver(
      context: RoomPlayerRuntimeObserverContext(
        providerId: ProviderId.bilibili,
        roomId: '6',
        runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
        trace: traces.add,
        resolvePlaybackAvailable: () => true,
        onPlayerStateChanged: (_, {required playbackAvailable}) {},
      ),
    );
    addTearDown(observer.dispose);
    addTearDown(player.dispose);

    observer.attach();
    player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: source('first'),
      ),
    );
    await flushEvents();

    final diagnostics = PlayerDiagnostics(
      backend: player.backend,
      width: 1920,
      height: 1080,
      videoParams: const {'codec': 'h264', 'frame_rate': '60'},
      rebufferCount: 1,
    );
    player.emitDiagnostics(diagnostics);
    await flushEvents();
    player.emitDiagnostics(diagnostics);
    await flushEvents();

    expect(
      traces.where((entry) => entry.startsWith('player diagnostics ')),
      hasLength(1),
    );

    player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: source('second'),
      ),
    );
    await flushEvents();
    player.emitDiagnostics(diagnostics);
    await flushEvents();

    expect(
      traces.where((entry) => entry.startsWith('player diagnostics ')),
      hasLength(2),
    );
  });

  test('room player runtime observer stops forwarding after dispose', () async {
    final player = TestRecordingPlayer();
    final runtime = PlayerRuntimeController(player);
    final traces = <String>[];
    var forwardCount = 0;
    final observer = RoomPlayerRuntimeObserver(
      context: RoomPlayerRuntimeObserverContext(
        providerId: ProviderId.bilibili,
        roomId: '6',
        runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
        trace: traces.add,
        resolvePlaybackAvailable: () => true,
        onPlayerStateChanged: (_, {required playbackAvailable}) {
          forwardCount += 1;
        },
      ),
    );
    addTearDown(player.dispose);

    observer.attach();
    await observer.dispose();

    player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: source('disposed'),
      ),
    );
    player.emitDiagnostics(
      PlayerDiagnostics(
        backend: player.backend,
        videoParams: const {'codec': 'h264'},
      ),
    );
    await flushEvents();

    expect(forwardCount, 0);
    expect(traces, isEmpty);
  });
}
