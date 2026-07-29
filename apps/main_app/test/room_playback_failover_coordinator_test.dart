import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_playback_failover_coordinator.dart';
import 'package:nolive_app/src/features/room/application/room_playback_session_state.dart';

void main() {
  group('RoomPlaybackFailoverCoordinator', () {
    test('a stop while leaving the room does nothing', () async {
      final harness = _Harness(isLeavingRoom: true);

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(harness.binds, isEmpty);
      expect(harness.refreshes, isEmpty);
    });

    test('a stop during a rebind does nothing', () async {
      final harness = _Harness(isRebindInFlight: true);

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(harness.binds, isEmpty);
      expect(harness.refreshes, isEmpty);
    });

    test('a stop during a refresh does nothing', () async {
      final harness = _Harness(isRefreshInFlight: true);

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(harness.binds, isEmpty);
      expect(harness.refreshes, isEmpty);
    });

    test('walks to the next line when the current one dies', () async {
      final harness = _Harness(playUrls: _lines(3));

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(harness.binds, isNotEmpty);
      expect(
        harness.refreshes,
        isEmpty,
        reason: 'a usable next line must not escalate to a full reload',
      );
    });

    test('a failed bind keeps walking instead of escalating', () async {
      final harness = _Harness(playUrls: _lines(3), bindResult: false);

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(
        harness.binds.length,
        greaterThan(1),
        reason:
            'bind==false means this line is dead, not that every CDN is dead',
      );
    });

    test('providers with their own recovery skip the generic loop', () async {
      final harness = _Harness(
        providerId: ProviderId.twitch,
        playUrls: _lines(3),
      );

      await harness.coordinator.handleUnexpectedPlaybackStop(_errorState());

      expect(harness.binds, isEmpty);
      expect(harness.refreshes, hasLength(1));
    });

    test('a soft stall with no lines refreshes without reloading', () async {
      final harness = _Harness();

      await harness.coordinator.handleUnexpectedPlaybackStop(
        _errorState(message: null),
      );

      expect(harness.refreshes, hasLength(1));
      expect(harness.refreshes.single.reloadPlayer, isFalse);
    });

    test('a hard open failure reloads play sources', () async {
      final harness = _Harness();

      await harness.coordinator.handleUnexpectedPlaybackStop(
        _errorState(message: 'failed to open stream'),
      );

      expect(harness.refreshes, hasLength(1));
      expect(harness.refreshes.single.reloadPlayer, isTrue);
    });

    test('the terminal reload budget caps repeated hard failures', () async {
      final harness = _Harness();

      for (var i = 0; i < 12; i += 1) {
        await harness.coordinator.handleUnexpectedPlaybackStop(
          _errorState(message: 'failed to open stream'),
        );
      }

      expect(
        harness.refreshes.length,
        lessThan(12),
        reason: 'without a cap, a dead CDN tight-loops getH5Play/rebind',
      );
      expect(harness.refreshes, isNotEmpty);
    });

    test('leaving the room mid-delay refunds the budget slot', () async {
      final harness = _Harness();
      harness.leaveDuringDelay = true;

      await harness.coordinator.handleUnexpectedPlaybackStop(
        _errorState(message: 'failed to open stream'),
      );

      expect(
        harness.refreshes,
        isEmpty,
        reason: 'aborting after the delay must not spend a budget slot',
      );
    });

    test('re-entering a different room resets the budget', () async {
      final harness = _Harness();

      for (var i = 0; i < 12; i += 1) {
        await harness.coordinator.handleUnexpectedPlaybackStop(
          _errorState(message: 'failed to open stream'),
        );
      }
      final exhausted = harness.refreshes.length;

      harness.roomId = 'another-room';
      await harness.coordinator.handleUnexpectedPlaybackStop(
        _errorState(message: 'failed to open stream'),
      );

      expect(harness.refreshes.length, greaterThan(exhausted));
    });

    test('the first playing tick already counts as having played', () {
      final harness = _Harness();

      expect(harness.coordinator.hasReachedPlaying, isFalse);
      harness.coordinator.notePlaying(isPlaying: true);

      expect(
        harness.coordinator.hasReachedPlaying,
        isTrue,
        reason:
            'registering the room key must not clear the flag the same tick '
            'just raised',
      );
    });

    test('entering a different room clears hasReachedPlaying', () {
      final harness = _Harness();
      harness.coordinator.notePlaying(isPlaying: true);

      harness.roomId = 'another-room';
      harness.coordinator.notePlaying(isPlaying: false);

      expect(
        harness.coordinator.hasReachedPlaying,
        isTrue,
        reason: 'a non-playing tick does not re-register the room',
      );

      harness.coordinator.notePlaying(isPlaying: true);
      expect(harness.coordinator.hasReachedPlaying, isTrue);
    });

    test('an overlapping stop does not start a second ladder', () async {
      final playUrls = _lines(3);
      final bindGate = Completer<void>();
      final binds = <String>[];
      final traces = <String>[];
      final coordinator = RoomPlaybackFailoverCoordinator(
        resolveProviderId: () => ProviderId.douyu,
        resolveRoomId: () => 'room-a',
        resolvePlaybackSession: () =>
            RoomPlaybackSessionState(playUrls: playUrls),
        isActive: () => true,
        isLeavingRoom: () => false,
        isRefreshInFlight: () => false,
        isRebindInFlight: () => false,
        bindPlaybackSource:
            ({
              required playbackSource,
              required label,
              required autoPlay,
              currentPlaybackSource,
            }) async {
              binds.add(playbackSource.url.toString());
              // Hold the first ladder mid-bind so a second stop can race.
              if (binds.length == 1) {
                await bindGate.future;
              }
              return true;
            },
        refreshRoom:
            ({
              required showFeedback,
              required reloadPlayer,
              required forcePlaybackRebind,
            }) async {},
        trace: traces.add,
        delay: (_) async {},
      );

      final first = coordinator.handleUnexpectedPlaybackStop(_errorState());
      // Yield until the first call is parked inside bind.
      for (var i = 0; i < 20 && binds.isEmpty; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(binds, isNotEmpty, reason: 'first ladder must reach bind');

      await coordinator.handleUnexpectedPlaybackStop(_errorState());
      bindGate.complete();
      await first;

      expect(
        binds,
        hasLength(1),
        reason: 'a second stop mid-ladder must not walk lines again',
      );
      expect(
        traces.any((line) => line.contains('skip overlapping stop')),
        isTrue,
      );
    });
  });
}

PlayerState _errorState({String? message = 'connection reset'}) {
  return PlayerState(
    status: PlaybackStatus.error,
    errorMessage: message,
    source: PlaybackSource(url: Uri.parse('https://edge.example/line-0.m3u8')),
  );
}

List<LivePlayUrl> _lines(int count) {
  return List<LivePlayUrl>.generate(
    count,
    (index) => LivePlayUrl(
      url: 'https://edge.example/line-$index.m3u8',
      lineLabel: '线路${index + 1}',
    ),
    growable: false,
  );
}

class _Harness {
  _Harness({
    this.providerId = ProviderId.douyu,
    List<LivePlayUrl> playUrls = const <LivePlayUrl>[],
    this.bindResult = true,
    this.isLeavingRoom = false,
    this.isRefreshInFlight = false,
    this.isRebindInFlight = false,
  }) : _playUrls = playUrls {
    coordinator = RoomPlaybackFailoverCoordinator(
      resolveProviderId: () => providerId,
      resolveRoomId: () => roomId,
      resolvePlaybackSession: () =>
          RoomPlaybackSessionState(playUrls: _playUrls),
      isActive: () => active,
      isLeavingRoom: () => isLeavingRoom,
      isRefreshInFlight: () => isRefreshInFlight,
      isRebindInFlight: () => isRebindInFlight,
      bindPlaybackSource:
          ({
            required playbackSource,
            required label,
            required autoPlay,
            currentPlaybackSource,
          }) async {
            binds.add(playbackSource.url.toString());
            return bindResult;
          },
      refreshRoom:
          ({
            required showFeedback,
            required reloadPlayer,
            required forcePlaybackRebind,
          }) async {
            refreshes.add((reloadPlayer: reloadPlayer));
          },
      trace: traces.add,
      // Collapse every escalation wait so the ladder runs at test speed.
      delay: (duration) async {
        delays.add(duration);
        if (leaveDuringDelay) {
          isLeavingRoom = true;
        }
      },
    );
  }

  final ProviderId providerId;
  final List<LivePlayUrl> _playUrls;
  final bool bindResult;

  String roomId = 'room-a';
  bool active = true;
  bool isLeavingRoom;
  bool isRefreshInFlight;
  bool isRebindInFlight;
  bool leaveDuringDelay = false;

  final List<String> binds = <String>[];
  final List<({bool reloadPlayer})> refreshes = <({bool reloadPlayer})>[];
  final List<Duration> delays = <Duration>[];
  final List<String> traces = <String>[];

  late final RoomPlaybackFailoverCoordinator coordinator;
}
