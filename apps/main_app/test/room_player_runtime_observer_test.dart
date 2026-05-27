import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_player_runtime_observer.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  PlaybackSource source(String path) =>
      PlaybackSource(url: Uri.parse('https://example.com/$path.m3u8'));

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
        onPlayerStateChanged: (state, {required playbackAvailable}) {
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
      PlayerState(status: PlaybackStatus.playing, source: source('room')),
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

  test(
    'room player runtime observer resets diagnostics dedupe after source change',
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
        PlayerState(status: PlaybackStatus.playing, source: source('first')),
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
        PlayerState(status: PlaybackStatus.playing, source: source('second')),
      );
      await flushEvents();
      player.emitDiagnostics(diagnostics);
      await flushEvents();

      expect(
        traces.where((entry) => entry.startsWith('player diagnostics ')),
        hasLength(2),
      );
    },
  );

  test(
    'room player runtime observer refreshes after unexpected completion',
    () async {
      final player = TestRecordingPlayer();
      final runtime = PlayerRuntimeController(player);
      final traces = <String>[];
      var recoveryCount = 0;
      final observer = RoomPlayerRuntimeObserver(
        context: RoomPlayerRuntimeObserverContext(
          providerId: ProviderId.bilibili,
          roomId: '6',
          runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
          trace: traces.add,
          resolvePlaybackAvailable: () => true,
          onPlayerStateChanged: (_, {required playbackAvailable}) {},
          unexpectedStopRecoveryDelay: Duration.zero,
          onUnexpectedPlaybackStop: (_) async {
            recoveryCount += 1;
          },
        ),
      );
      addTearDown(observer.dispose);
      addTearDown(player.dispose);

      observer.attach();
      player.emit(
        PlayerState(status: PlaybackStatus.completed, source: source('room')),
      );
      await flushEvents();
      await flushEvents();

      expect(recoveryCount, 1);
      expect(
        traces,
        contains('player unexpected stop recovery scheduled status=completed'),
      );
      expect(
        traces,
        contains('player unexpected stop recovery refresh status=completed'),
      );
    },
  );

  test(
    'room player runtime observer cancels unexpected completion on leave',
    () async {
      final player = TestRecordingPlayer();
      final runtime = PlayerRuntimeController(player);
      var leavingRoom = false;
      var recoveryCount = 0;
      final observer = RoomPlayerRuntimeObserver(
        context: RoomPlayerRuntimeObserverContext(
          providerId: ProviderId.bilibili,
          roomId: '6',
          runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
          trace: (_) {},
          resolvePlaybackAvailable: () => true,
          resolveIsLeavingRoom: () => leavingRoom,
          onPlayerStateChanged: (_, {required playbackAvailable}) {},
          unexpectedStopRecoveryDelay: const Duration(milliseconds: 1),
          onUnexpectedPlaybackStop: (_) async {
            recoveryCount += 1;
          },
        ),
      );
      addTearDown(observer.dispose);
      addTearDown(player.dispose);

      observer.attach();
      player.emit(
        PlayerState(status: PlaybackStatus.completed, source: source('room')),
      );
      leavingRoom = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(recoveryCount, 0);
    },
  );

  test(
    'room player runtime observer skips unexpected stop recovery when disabled',
    () async {
      final player = TestRecordingPlayer();
      final runtime = PlayerRuntimeController(player);
      final traces = <String>[];
      var recoveryCount = 0;
      final observer = RoomPlayerRuntimeObserver(
        context: RoomPlayerRuntimeObserverContext(
          providerId: ProviderId.stripchat,
          roomId: 'test_room',
          runtime: RoomRuntimeObservationContext.fromPlayerRuntime(runtime),
          trace: traces.add,
          resolvePlaybackAvailable: () => true,
          shouldRecoverUnexpectedStop: (_) => false,
          onPlayerStateChanged: (_, {required playbackAvailable}) {},
          unexpectedStopRecoveryDelay: Duration.zero,
          onUnexpectedPlaybackStop: (_) async {
            recoveryCount += 1;
          },
        ),
      );
      addTearDown(observer.dispose);
      addTearDown(player.dispose);

      observer.attach();
      player.emit(
        PlayerState(status: PlaybackStatus.error, source: source('room')),
      );
      await flushEvents();
      await flushEvents();

      expect(recoveryCount, 0);
      expect(
        traces.where((entry) => entry.contains('unexpected stop recovery')),
        isEmpty,
      );
    },
  );

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
      PlayerState(status: PlaybackStatus.playing, source: source('disposed')),
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
