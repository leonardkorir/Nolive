import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_session_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

void main() {
  const base = RoomPageSessionState.initial();

  test('pending-only playback bootstrap fields do not notify listeners', () {
    final withPending = base.copyWith(
      playbackSession: base.playbackSession.copyWith(
        pendingPlaybackSource: PlaybackSource(
          url: Uri.parse('https://example.com/pending.m3u8'),
        ),
        pendingPlaybackAvailable: true,
        pendingPlaybackAutoPlay: true,
      ),
    );
    expect(
      shouldNotifyRoomPageSessionListeners(
        previous: base,
        next: withPending,
      ),
      isFalse,
      reason: 'UI does not read pendingPlayback* bookkeeping fields',
    );
  });

  test('playback source / availability changes do notify', () {
    final withSource = base.copyWith(
      playbackSession: base.playbackSession.copyWith(
        playbackSource: PlaybackSource(
          url: Uri.parse('https://example.com/live.m3u8'),
        ),
        playbackAvailable: true,
      ),
    );
    expect(
      shouldNotifyRoomPageSessionListeners(
        previous: base,
        next: withSource,
      ),
      isTrue,
    );
  });

  test('identical session state does not notify', () {
    expect(
      shouldNotifyRoomPageSessionListeners(previous: base, next: base),
      isFalse,
    );
  });

  test('volume and follow chrome fields notify', () {
    expect(
      shouldNotifyRoomPageSessionListeners(
        previous: base,
        next: base.copyWith(volume: 0.5),
      ),
      isTrue,
    );
    expect(
      shouldNotifyRoomPageSessionListeners(
        previous: base,
        next: base.copyWith(isFollowed: true),
      ),
      isTrue,
    );
  });

  test(
    'pending overlay on existing playback does not notify (bootstrap path)',
    () {
      final previous = RoomPageSessionState(
        playbackSession: RoomPlaybackSessionState(
          playbackSource: PlaybackSource(
            url: Uri.parse('https://example.com/a.m3u8'),
          ),
          playbackAvailable: true,
        ),
        playerPreferences: const PlayerPreferences(
          autoPlayEnabled: true,
          preferHighestQuality: false,
          autoQualityEnabled: true,
          backend: PlayerBackend.mpv,
          volume: 1,
          mpvHardwareAccelerationEnabled: true,
          mpvCompatModeEnabled: false,
          mpvDoubleBufferingEnabled: false,
          mpvCustomOutputEnabled: false,
          mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
          mpvAudioOutputDriver: kDefaultMpvAudioOutputDriver,
          mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
          mpvLogEnabled: false,
          wifiQualityPreference: NetworkQualityPreference.middle,
          cellularQualityPreference: NetworkQualityPreference.lowest,
          mdkLowLatencyEnabled: true,
          mdkAndroidTunnelEnabled: false,
          mdkAndroidHardwareVideoDecoderEnabled: true,
          forceHttpsEnabled: false,
          androidAutoFullscreenEnabled: true,
          androidBackgroundAutoPauseEnabled: true,
          androidPipHideDanmakuEnabled: true,
          scaleMode: PlayerScaleMode.contain,
        ),
      );
      final next = previous.copyWith(
        playbackSession: previous.playbackSession.copyWith(
          pendingPlaybackSource: PlaybackSource(
            url: Uri.parse('https://example.com/a.m3u8'),
          ),
          pendingPlaybackAvailable: true,
          pendingPlaybackAutoPlay: true,
        ),
      );
      expect(
        shouldNotifyRoomPageSessionListeners(previous: previous, next: next),
        isFalse,
      );
    },
  );
}
