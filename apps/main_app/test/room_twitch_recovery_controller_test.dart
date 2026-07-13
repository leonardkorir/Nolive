import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_twitch_recovery_controller.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

void main() {
  test(
    'adaptive auto without promotion does not switch lines on zero progress',
    () async {
      final player = _TwitchRecoveryTestPlayer();
      final runtime = PlayerRuntimeController(player);
      final controller = RoomTwitchRecoveryController(
        runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
        delay: (_) async {},
      );
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      final auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
      final q1080 = LivePlayQuality(
        id: '1080p60',
        label: '1080p60',
        sortOrder: 4,
      );
      final popoutSource = PlaybackSource(
        url: Uri.parse(
          'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        ),
      );
      const playUrls = [
        LivePlayUrl(
          url: 'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
          lineLabel: '默认 Popout',
          metadata: {'playerType': 'popout'},
        ),
        LivePlayUrl(
          url: 'http://127.0.0.1:33101/twitch-ad-guard/embed/stream.m3u8',
          lineLabel: '备用 Embed',
          metadata: {'playerType': 'embed'},
        ),
      ];
      // No promotionQuality: Auto switch ON path.
      controller.applyStartupPlan(TwitchStartupPlan(startupQuality: auto));
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.buffering,
          position: Duration.zero,
          buffered: Duration.zero,
          source: popoutSource,
        ),
      );

      var switchLineCount = 0;
      var refreshCount = 0;
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: _buildSnapshot(
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: playUrls,
        ),
        playbackSource: popoutSource,
        playUrls: playUrls,
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              fail('should not change quality when adaptive auto has no promotion');
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              refreshCount += 1;
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          switchLineCount += 1;
        },
      );

      expect(switchLineCount, 0);
      expect(refreshCount, 0);
    },
  );

  test(
    'room twitch recovery waits on playing auto without refreshing source',
    () async {
      final player = _TwitchRecoveryTestPlayer();
      final runtime = PlayerRuntimeController(player);
      // Limit recursive wait ticks so zero-delay tests do not auto-promote.
      var delayTicks = 0;
      final controller = RoomTwitchRecoveryController(
        runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
        delay: (_) async {
          delayTicks += 1;
        },
      );
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      final auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
      final q1080 = LivePlayQuality(
        id: '1080p60',
        label: '1080p60',
        sortOrder: 4,
      );
      final playbackSource = PlaybackSource(
        url: Uri.parse('https://example.com/auto.m3u8'),
      );
      // Auto already has A/V (playing) but demuxer position not advanced yet.
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: Duration.zero,
          buffered: Duration.zero,
          source: playbackSource,
        ),
      );
      controller.applyStartupPlan(
        TwitchStartupPlan(startupQuality: auto, promotionQuality: q1080),
      );

      var refreshCount = 0;
      LivePlayQuality? switchedQuality;
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: _buildSnapshot(
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        ),
        playbackSource: playbackSource,
        playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        // Stop after first wait tick so we observe "wait, no refresh".
        isMounted: () => delayTicks < 2,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              switchedQuality = quality;
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              refreshCount += 1;
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('should not switch line during auto warm-up');
        },
      );

      expect(refreshCount, 0);
      expect(switchedQuality, isNull);
      expect(controller.current.startupPromotionQuality?.id, '1080p60');

      // After warm-up progress, promote once to highest.
      // Reset source-key gate from the interrupted wait tick above.
      controller.prepareForResolvedPlayback(startupPromotionQuality: q1080);
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: const Duration(milliseconds: 1500),
          buffered: const Duration(seconds: 3),
          source: playbackSource,
        ),
      );
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: _buildSnapshot(
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        ),
        playbackSource: playbackSource,
        playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              switchedQuality = quality;
              expect(resetTwitchRecoveryAttempts, isFalse);
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              fail('must not refresh auto before promotion');
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('should not switch line during promotion');
        },
      );

      expect(refreshCount, 0);
      expect(switchedQuality?.id, '1080p60');
      expect(controller.current.startupPromotionQuality, isNull);
    },
  );

  test(
    'room twitch recovery controller promotes startup quality after warmup',
    () async {
      final player = _TwitchRecoveryTestPlayer();
      final runtime = PlayerRuntimeController(player);
      final controller = RoomTwitchRecoveryController(
        runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
        delay: (_) async {},
      );
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      final auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
      final q1080 = LivePlayQuality(
        id: '1080p60',
        label: '1080p60',
        sortOrder: 4,
      );
      final playbackSource = PlaybackSource(
        url: Uri.parse('https://example.com/auto.m3u8'),
      );
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: const Duration(milliseconds: 1500),
          buffered: const Duration(seconds: 3),
          source: playbackSource,
        ),
      );
      controller.applyStartupPlan(
        TwitchStartupPlan(startupQuality: auto, promotionQuality: q1080),
      );

      LivePlayQuality? switchedQuality;
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: _buildSnapshot(
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        ),
        playbackSource: playbackSource,
        playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              switchedQuality = quality;
              expect(resetTwitchRecoveryAttempts, isFalse);
              expect(twitchStartupPromotionQuality, isNull);
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              fail('should not refresh playback source during promotion');
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('should not switch line during promotion');
        },
      );

      expect(switchedQuality?.id, '1080p60');
      expect(controller.current.startupPromotionQuality, isNull);
      expect(controller.current.recoveryAttempts, 0);
    },
  );

  test(
    'room twitch recovery controller waits for stripchat playback progress',
    () async {
      final player = _TwitchRecoveryTestPlayer();
      final runtime = PlayerRuntimeController(player);
      final controller = RoomTwitchRecoveryController(
        runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
        delay: (_) async {},
      );
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      final auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
      final q1080 = LivePlayQuality(
        id: '1080p',
        label: '1080p',
        sortOrder: 1080,
      );
      final playbackSource = PlaybackSource(
        url: Uri.parse('https://example.com/auto.m3u8'),
      );
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.ready,
          position: Duration.zero,
          buffered: Duration.zero,
          source: playbackSource,
        ),
      );
      controller.applyStartupPlan(
        TwitchStartupPlan(startupQuality: auto, promotionQuality: q1080),
      );

      LivePlayQuality? switchedQuality;
      await controller.scheduleRecovery(
        providerId: ProviderId.stripchat,
        snapshot: _buildSnapshot(
          providerId: ProviderId.stripchat,
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        ),
        playbackSource: playbackSource,
        playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              switchedQuality = quality;
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              fail(
                'should not refresh stripchat playback source during promotion',
              );
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('stripchat startup promotion should not switch line');
        },
      );

      expect(switchedQuality, isNull);
      expect(controller.current.startupPromotionQuality?.id, '1080p');
      expect(controller.current.recoveryAttempts, 2);

      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: const Duration(milliseconds: 1200),
          buffered: const Duration(seconds: 2),
          source: playbackSource,
        ),
      );
      await controller.scheduleRecovery(
        providerId: ProviderId.stripchat,
        snapshot: _buildSnapshot(
          providerId: ProviderId.stripchat,
          selectedQuality: auto,
          qualities: [auto, q1080],
          playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        ),
        playbackSource: playbackSource,
        playUrls: const [LivePlayUrl(url: 'https://example.com/auto.m3u8')],
        selectedQuality: auto,
        resolveCurrentQuality: () => auto,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              switchedQuality = quality;
              expect(resetTwitchRecoveryAttempts, isFalse);
              expect(twitchStartupPromotionQuality, isNull);
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              fail(
                'should not refresh stripchat playback source during promotion',
              );
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('stripchat startup promotion should not switch line');
        },
      );

      expect(switchedQuality?.id, '1080p');
      expect(controller.current.startupPromotionQuality, isNull);
      expect(controller.current.recoveryAttempts, 0);
    },
  );

  test(
    'room twitch recovery controller escalates from line switch to refresh',
    () async {
      final player = _TwitchRecoveryTestPlayer();
      final runtime = PlayerRuntimeController(player);
      final controller = RoomTwitchRecoveryController(
        runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
        delay: (_) async {},
      );
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      final q1080 = LivePlayQuality(
        id: '1080p60',
        label: '1080p60',
        sortOrder: 4,
      );
      final popoutSource = PlaybackSource(
        url: Uri.parse(
          'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        ),
      );
      final siteSource = PlaybackSource(
        url: Uri.parse(
          'http://127.0.0.1:33101/twitch-ad-guard/site/stream.m3u8',
        ),
      );
      const playUrls = [
        LivePlayUrl(
          url: 'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
          lineLabel: '默认 Popout',
          metadata: {'playerType': 'popout'},
        ),
        LivePlayUrl(
          url: 'http://127.0.0.1:33101/twitch-ad-guard/site/stream.m3u8',
          lineLabel: '备用 Site',
          metadata: {'playerType': 'site'},
        ),
      ];
      final snapshot = _buildSnapshot(
        selectedQuality: q1080,
        qualities: [q1080],
        playUrls: playUrls,
      );
      controller.applyStartupPlan(TwitchStartupPlan(startupQuality: q1080));

      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: Duration.zero,
          buffered: Duration.zero,
          source: popoutSource,
        ),
      );

      LivePlayUrl? switchedLine;
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: snapshot,
        playbackSource: popoutSource,
        playUrls: playUrls,
        selectedQuality: q1080,
        resolveCurrentQuality: () => q1080,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              fail('should not change quality during fixed line recovery');
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              fail('should switch line before refreshing current line');
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          switchedLine = playUrl;
          expect(resetTwitchRecoveryAttempts, isFalse);
        },
      );

      expect(switchedLine?.lineLabel, '备用 Site');
      expect(controller.current.recoveryAttempts, 1);

      controller.prepareForLineSwitch(resetAttempts: false);
      player.emit(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          position: Duration.zero,
          buffered: Duration.zero,
          source: siteSource,
        ),
      );

      var refreshCount = 0;
      PlaybackSource? refreshedSource;
      await controller.scheduleRecovery(
        providerId: ProviderId.twitch,
        snapshot: snapshot,
        playbackSource: siteSource,
        playUrls: playUrls,
        selectedQuality: q1080,
        resolveCurrentQuality: () => q1080,
        isMounted: () => true,
        switchQuality:
            (
              snapshot,
              quality, {
              bool resetTwitchRecoveryAttempts = true,
              LivePlayQuality? twitchStartupPromotionQuality,
            }) async {
              fail('should not change quality during current-line refresh');
            },
        refreshPlaybackSource:
            (
              snapshot,
              quality, {
              LivePlayQuality? twitchStartupPromotionQuality,
              bool resetTwitchRecoveryAttempts = false,
              PlaybackSource? preferredPlaybackSource,
              List<LivePlayUrl>? currentPlayUrls,
            }) async {
              refreshCount += 1;
              refreshedSource = preferredPlaybackSource;
              expect(resetTwitchRecoveryAttempts, isFalse);
              expect(currentPlayUrls, playUrls);
            },
        switchLine: (playUrl, {bool resetTwitchRecoveryAttempts = true}) async {
          fail('should refresh current line after one line retry');
        },
      );

      expect(refreshCount, 1);
      expect(
        refreshedSource?.url.toString(),
        'http://127.0.0.1:33101/twitch-ad-guard/site/stream.m3u8',
      );
      expect(controller.current.recoveryAttempts, 2);
    },
  );
}

LoadedRoomSnapshot _buildSnapshot({
  ProviderId providerId = ProviderId.twitch,
  required LivePlayQuality selectedQuality,
  required List<LivePlayQuality> qualities,
  required List<LivePlayUrl> playUrls,
}) {
  return LoadedRoomSnapshot(
    providerId: providerId,
    detail: LiveRoomDetail(
      providerId: providerId,
      roomId: 'room-id',
      title: 'title',
      streamerName: 'streamer',
      sourceUrl: 'https://www.twitch.tv/streamer',
      isLive: true,
    ),
    qualities: qualities,
    selectedQuality: selectedQuality,
    playUrls: playUrls,
  );
}

class _TwitchRecoveryTestPlayer implements BasePlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics =>
      const PlayerDiagnostics(backend: PlayerBackend.mpv);

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setSource(PlaybackSource source) async {
    emit(_currentState.copyWith(source: source));
  }

  @override
  Future<void> play() async {
    emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    emit(
      _currentState.copyWith(status: PlaybackStatus.ready, clearSource: true),
    );
  }

  @override
  Future<void> setVolume(double value) async {
    emit(_currentState.copyWith(volume: value));
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

  void emit(PlayerState next) {
    _currentState = next.copyWith(backend: PlayerBackend.mpv);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }
}
