import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_playback_source_helpers.dart';

void main() {
  test('summarizePlaybackSource includes split audio metadata', () {
    final source = PlaybackSource(
      url: Uri.parse('https://video.example/chunklist_video.m3u8'),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://video.example/chunklist_audio.m3u8'),
      ),
    );

    expect(
      summarizePlaybackSource(source),
      'video.example/chunklist_video.m3u8 + audio=video.example/chunklist_audio.m3u8',
    );
  });

  test(
    'samePlaybackSource compares HLS metadata and external media fields',
    () {
      final baseline = PlaybackSource(
        url: Uri.parse('https://video.example/master.m3u8'),
        headers: const {'referer': 'https://room.example/'},
        masterPlaylistUrl: Uri.parse('https://video.example/master.m3u8'),
        masterPlaylistContent: '#EXTM3U',
        hlsBitrate: '3296000',
        externalAudio: PlaybackExternalMedia(
          url: Uri.parse('https://video.example/audio.m3u8'),
          headers: {'origin': 'https://room.example'},
          label: 'English',
          mimeType: 'application/x-mpegURL',
        ),
      );

      final differentBitrate = PlaybackSource(
        url: baseline.url,
        headers: baseline.headers,
        masterPlaylistUrl: baseline.masterPlaylistUrl,
        masterPlaylistContent: baseline.masterPlaylistContent,
        hlsBitrate: '1296000',
        externalAudio: baseline.externalAudio,
      );
      final differentAudioLabel = PlaybackSource(
        url: baseline.url,
        headers: baseline.headers,
        masterPlaylistUrl: baseline.masterPlaylistUrl,
        masterPlaylistContent: baseline.masterPlaylistContent,
        hlsBitrate: baseline.hlsBitrate,
        externalAudio: PlaybackExternalMedia(
          url: Uri.parse('https://video.example/audio.m3u8'),
          headers: {'origin': 'https://room.example'},
          label: 'Japanese',
          mimeType: 'application/x-mpegURL',
        ),
      );

      expect(samePlaybackSource(baseline, differentBitrate), isFalse);
      expect(samePlaybackSource(baseline, differentAudioLabel), isFalse);
      expect(
        samePlaybackExternalMedia(
          baseline.externalAudio,
          differentAudioLabel.externalAudio,
        ),
        isFalse,
      );
    },
  );

  test('samePlaybackExternalMediaForPreRefresh only keys on audio URL', () {
    final baseline = PlaybackExternalMedia(
      url: Uri.parse('https://video.example/audio.m3u8'),
      headers: {'origin': 'https://room.example'},
      label: 'English',
      mimeType: 'application/x-mpegURL',
    );
    final refreshedMetadata = PlaybackExternalMedia(
      url: Uri.parse('https://video.example/audio.m3u8'),
      headers: {'origin': 'https://next-room.example'},
      label: 'Japanese',
      mimeType: 'audio/mp4',
    );

    expect(samePlaybackExternalMedia(baseline, refreshedMetadata), isFalse);
    expect(
      samePlaybackExternalMediaForPreRefresh(baseline, refreshedMetadata),
      isTrue,
    );
  });
}
