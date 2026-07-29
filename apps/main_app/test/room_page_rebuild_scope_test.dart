import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_page_rebuild_scope.dart';

void main() {
  group('shouldSessionCoordinatorFanOutChildNotify', () {
    test('panel, follow, and controls do not fan into full session notify', () {
      expect(
        shouldSessionCoordinatorFanOutChildNotify(
          RoomSessionChildNotifySource.panelSelection,
        ),
        isFalse,
      );
      expect(
        shouldSessionCoordinatorFanOutChildNotify(
          RoomSessionChildNotifySource.followWatchlist,
        ),
        isFalse,
      );
      expect(
        shouldSessionCoordinatorFanOutChildNotify(
          RoomSessionChildNotifySource.controlsAction,
        ),
        isFalse,
      );
    });

    test('session / playback / status chrome sources still fan out', () {
      for (final source in <RoomSessionChildNotifySource>[
        RoomSessionChildNotifySource.sessionState,
        RoomSessionChildNotifySource.playbackController,
        RoomSessionChildNotifySource.followRoomTransition,
        RoomSessionChildNotifySource.danmakuState,
        RoomSessionChildNotifySource.fullscreenSession,
        RoomSessionChildNotifySource.playerRuntime,
      ]) {
        expect(
          shouldSessionCoordinatorFanOutChildNotify(source),
          isTrue,
          reason: '$source must still schedule full room rebuild fan-out',
        );
      }
    });
  });

  group('planRoomPreviewDispose', () {
    test(
      'cleanup defers heavy controller dispose until after leave cleanup',
      () {
        final plan = planRoomPreviewDispose(cleanupPlayback: true);
        expect(plan.cleanupPlayback, isTrue);
        expect(plan.deferHeavyControllerDisposeUntilAfterCleanup, isTrue);
      },
    );

    test('no cleanup disposes heavy controllers immediately', () {
      final plan = planRoomPreviewDispose(cleanupPlayback: false);
      expect(plan.cleanupPlayback, isFalse);
      expect(plan.deferHeavyControllerDisposeUntilAfterCleanup, isFalse);
    });
  });

  group('runRoomPreviewHeavyControllerDispose', () {
    test(
      'cleanupPlayback true runs cleanup before playback/fullscreen dispose',
      () async {
        final order = <String>[];
        final completer = Completer<void>();
        final plan = planRoomPreviewDispose(cleanupPlayback: true);

        final run = runRoomPreviewHeavyControllerDispose(
          plan: plan,
          hooks: RoomPreviewHeavyDisposeHooks(
            cleanupPlaybackOnLeave: () async {
              order.add('cleanup_start');
              // Simulate leave cleanup that still needs live controllers.
              await completer.future;
              order.add('cleanup_end');
            },
            disposeRuntime: () async {
              order.add('runtime');
            },
            disposePlayback: () {
              order.add('playback');
            },
            disposeDesktopMini: () async {
              order.add('desktop_mini');
            },
            disposeFullscreen: () {
              order.add('fullscreen');
            },
            disposeObserver: () async {
              order.add('observer');
            },
          ),
        );

        // While cleanup is still awaiting, heavy dispose must not have run.
        await Future<void>.delayed(Duration.zero);
        expect(order, ['cleanup_start']);
        expect(order, isNot(contains('playback')));
        expect(order, isNot(contains('fullscreen')));

        completer.complete();
        final steps = await run;

        expect(order, [
          'cleanup_start',
          'cleanup_end',
          'runtime',
          'playback',
          'desktop_mini',
          'fullscreen',
          'observer',
        ]);
        expect(steps.first, RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave);
        expect(
          steps.indexOf(RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave),
          lessThan(steps.indexOf(RoomPreviewHeavyDisposeStep.disposePlayback)),
        );
        expect(
          steps.indexOf(RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave),
          lessThan(
            steps.indexOf(RoomPreviewHeavyDisposeStep.disposeFullscreen),
          ),
        );
      },
    );

    test(
      'cleanupPlayback false skips cleanup and still tears down heavy controllers',
      () async {
        final order = <String>[];
        final plan = planRoomPreviewDispose(cleanupPlayback: false);

        final steps = await runRoomPreviewHeavyControllerDispose(
          plan: plan,
          hooks: RoomPreviewHeavyDisposeHooks(
            cleanupPlaybackOnLeave: () async {
              order.add('cleanup');
              fail('cleanup must not run when cleanupPlayback is false');
            },
            disposeRuntime: () async {
              order.add('runtime');
            },
            disposePlayback: () {
              order.add('playback');
            },
            disposeFullscreen: () {
              order.add('fullscreen');
            },
            disposeObserver: () async {
              order.add('observer');
            },
          ),
        );

        expect(order, ['runtime', 'playback', 'fullscreen', 'observer']);
        expect(
          steps,
          isNot(contains(RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave)),
        );
        expect(steps.first, RoomPreviewHeavyDisposeStep.disposeRuntime);
      },
    );

    test(
      'cleanup errors still dispose heavy controllers after cleanup attempt',
      () async {
        final order = <String>[];
        final plan = planRoomPreviewDispose(cleanupPlayback: true);

        final steps = await runRoomPreviewHeavyControllerDispose(
          plan: plan,
          hooks: RoomPreviewHeavyDisposeHooks(
            cleanupPlaybackOnLeave: () async {
              order.add('cleanup');
              throw StateError('cleanup failed');
            },
            disposeRuntime: () async {
              order.add('runtime');
            },
            disposePlayback: () {
              order.add('playback');
            },
            disposeFullscreen: () {
              order.add('fullscreen');
            },
            disposeObserver: () async {
              order.add('observer');
            },
          ),
        );

        expect(order, [
          'cleanup',
          'runtime',
          'playback',
          'fullscreen',
          'observer',
        ]);
        expect(steps.first, RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave);
        expect(steps, contains(RoomPreviewHeavyDisposeStep.disposePlayback));
      },
    );
  });

  group('shouldNotifyFullscreenSessionListeners', () {
    test('skips when view and gesture snapshots are equal', () {
      const a = Object();
      expect(
        shouldNotifyFullscreenSessionListeners(
          previousView: a,
          nextView: a,
          previousGesture: a,
          nextGesture: a,
        ),
        isFalse,
      );
    });

    test('notifies when either snapshot changes by equality', () {
      expect(
        shouldNotifyFullscreenSessionListeners(
          previousView: 1,
          nextView: 2,
          previousGesture: 'g',
          nextGesture: 'g',
        ),
        isTrue,
      );
      expect(
        shouldNotifyFullscreenSessionListeners(
          previousView: 1,
          nextView: 1,
          previousGesture: 'a',
          nextGesture: 'b',
        ),
        isTrue,
      );
    });
  });

  group('shouldScheduleFullRoomPageRebuildForPlayerState', () {
    const idle = PlayerState(status: PlaybackStatus.idle);
    final playing = PlayerState(
      status: PlaybackStatus.playing,
      source: PlaybackSource(url: Uri.parse('https://example.com/a.m3u8')),
      position: Duration.zero,
      buffered: Duration.zero,
    );

    test('null previous always rebuilds', () {
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: null,
          next: idle,
        ),
        isTrue,
      );
    });

    test('status and error transitions rebuild', () {
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: playing,
          next: playing.copyWith(status: PlaybackStatus.buffering),
        ),
        isTrue,
      );
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: playing,
          next: playing.copyWith(
            status: PlaybackStatus.error,
            errorMessage: 'boom',
          ),
        ),
        isTrue,
      );
    });

    test('source identity change rebuilds', () {
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: playing,
          next: playing.copyWith(
            source: PlaybackSource(
              url: Uri.parse('https://example.com/b.m3u8'),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('first progress after open rebuilds (loading shell exit)', () {
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: playing,
          next: playing.copyWith(position: const Duration(milliseconds: 40)),
        ),
        isTrue,
      );
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: playing,
          next: playing.copyWith(buffered: const Duration(milliseconds: 600)),
        ),
        isTrue,
      );
    });

    test('steady progress ticks after first frame do not rebuild', () {
      final afterFirstFrame = playing.copyWith(
        position: const Duration(seconds: 2),
        buffered: const Duration(seconds: 4),
      );
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: afterFirstFrame,
          next: afterFirstFrame.copyWith(position: const Duration(seconds: 3)),
        ),
        isFalse,
      );
      expect(
        shouldScheduleFullRoomPageRebuildForPlayerState(
          previous: afterFirstFrame,
          next: afterFirstFrame.copyWith(buffered: const Duration(seconds: 5)),
        ),
        isFalse,
      );
    });

    test('playerStateHasFirstFrameProgress matches shell progress branch', () {
      expect(playerStateHasFirstFrameProgress(playing), isFalse);
      expect(
        playerStateHasFirstFrameProgress(
          playing.copyWith(position: const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
      expect(
        playerStateHasFirstFrameProgress(
          playing.copyWith(buffered: const Duration(milliseconds: 501)),
        ),
        isTrue,
      );
    });

    test(
      'same PlayerState with forceRebuild (diagnostics size first-frame) rebuilds',
      () {
        // Simulates room_player_runtime_observer re-notifying current state
        // when video width/height first become non-zero.
        expect(
          shouldScheduleFullRoomPageRebuildForPlayerState(
            previous: playing,
            next: playing,
            forceRebuild: true,
          ),
          isTrue,
        );
        expect(
          shouldScheduleFullRoomPageRebuildForPlayerState(
            previous: playing,
            next: playing,
            forceRebuild: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('shouldForceRoomPageRebuildForVideoSizeChange', () {
    test('first non-zero size forces rebuild', () {
      expect(
        shouldForceRoomPageRebuildForVideoSizeChange(
          previousWidth: null,
          previousHeight: null,
          nextWidth: 1280,
          nextHeight: 720,
        ),
        isTrue,
      );
      expect(
        shouldForceRoomPageRebuildForVideoSizeChange(
          previousWidth: 0,
          previousHeight: 0,
          nextWidth: 1280,
          nextHeight: 720,
        ),
        isTrue,
      );
    });

    test('zero size does not force rebuild', () {
      expect(
        shouldForceRoomPageRebuildForVideoSizeChange(
          previousWidth: null,
          previousHeight: null,
          nextWidth: 0,
          nextHeight: 0,
        ),
        isFalse,
      );
    });

    test('same size after first frame does not force again', () {
      expect(
        shouldForceRoomPageRebuildForVideoSizeChange(
          previousWidth: 1280,
          previousHeight: 720,
          nextWidth: 1280,
          nextHeight: 720,
        ),
        isFalse,
      );
    });
  });
}
