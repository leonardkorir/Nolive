import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';

void main() {
  test('room playback session state exposes stable defaults', () {
    const state = RoomPlaybackSessionState();

    expect(state.activeRoomDetail, isNull);
    expect(state.selectedQuality, isNull);
    expect(state.effectiveQuality, isNull);
    expect(state.playbackSource, isNull);
    expect(state.playUrls, isEmpty);
    expect(state.playbackAvailable, isFalse);
    expect(state.pendingPlaybackSource, isNull);
    expect(state.pendingPlaybackAvailable, isFalse);
    expect(state.pendingPlaybackAutoPlay, isFalse);
  });

  test('copyWith updates playback session fields while preserving others', () {
    const roomDetail = LiveRoomDetail(
      providerId: 'bilibili',
      roomId: '6',
      title: '系统演示直播间',
      streamerName: '系统演示主播',
    );
    const selectedQuality = LivePlayQuality(id: 'fhd', label: '原画');
    const effectiveQuality = LivePlayQuality(id: 'hd', label: '高清');
    const playUrl = LivePlayUrl(url: 'https://example.com/live.flv');
    final playbackSource = PlaybackSource(
      url: Uri.parse('https://example.com/live.flv'),
      headers: const {'referer': 'https://example.com'},
    );
    final pendingPlaybackSource = PlaybackSource(
      url: Uri.parse('https://example.com/pending.flv'),
    );

    final state = RoomPlaybackSessionState(
      activeRoomDetail: roomDetail,
      selectedQuality: selectedQuality,
      playbackSource: playbackSource,
      playUrls: const [playUrl],
      playbackAvailable: true,
    ).copyWith(
      effectiveQuality: effectiveQuality,
      pendingPlaybackSource: pendingPlaybackSource,
      pendingPlaybackAvailable: true,
      pendingPlaybackAutoPlay: true,
    );

    expect(state.activeRoomDetail, same(roomDetail));
    expect(state.selectedQuality, same(selectedQuality));
    expect(state.effectiveQuality, same(effectiveQuality));
    expect(state.playbackSource, same(playbackSource));
    expect(state.playUrls, const [playUrl]);
    expect(state.playbackAvailable, isTrue);
    expect(state.pendingPlaybackSource, same(pendingPlaybackSource));
    expect(state.pendingPlaybackAvailable, isTrue);
    expect(state.pendingPlaybackAutoPlay, isTrue);
  });

  test('copyWith clear flags drop nullable playback session fields', () {
    final state = RoomPlaybackSessionState(
      activeRoomDetail: const LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '6',
        title: '系统演示直播间',
        streamerName: '系统演示主播',
      ),
      selectedQuality: const LivePlayQuality(id: 'fhd', label: '原画'),
      effectiveQuality: const LivePlayQuality(id: 'hd', label: '高清'),
      playbackSource:
          PlaybackSource(url: Uri.parse('https://example.com/live.flv')),
      pendingPlaybackSource: PlaybackSource(
        url: Uri.parse('https://example.com/pending.flv'),
      ),
      pendingPlaybackAvailable: true,
      pendingPlaybackAutoPlay: true,
    ).copyWith(
      clearActiveRoomDetail: true,
      clearSelectedQuality: true,
      clearEffectiveQuality: true,
      clearPlaybackSource: true,
      clearPendingPlaybackSource: true,
      pendingPlaybackAvailable: false,
      pendingPlaybackAutoPlay: false,
    );

    expect(state.activeRoomDetail, isNull);
    expect(state.selectedQuality, isNull);
    expect(state.effectiveQuality, isNull);
    expect(state.playbackSource, isNull);
    expect(state.pendingPlaybackSource, isNull);
    expect(state.pendingPlaybackAvailable, isFalse);
    expect(state.pendingPlaybackAutoPlay, isFalse);
  });
}
