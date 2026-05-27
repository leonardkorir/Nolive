import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('player state uses value equality across playback source metadata', () {
    final sourceA = PlaybackSource(
      url: Uri.parse('https://video.example/master.m3u8'),
      headers: const {'referer': 'https://room.example/'},
      masterPlaylistUrl: Uri.parse('https://video.example/master.m3u8'),
      masterPlaylistContent: '#EXTM3U',
      hlsBitrate: '3296000',
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://video.example/audio.m3u8'),
        headers: const {'origin': 'https://room.example'},
        label: 'English',
        mimeType: 'application/x-mpegURL',
      ),
    );
    final sourceB = PlaybackSource(
      url: Uri.parse('https://video.example/master.m3u8'),
      headers: const {'referer': 'https://room.example/'},
      masterPlaylistUrl: Uri.parse('https://video.example/master.m3u8'),
      masterPlaylistContent: '#EXTM3U',
      hlsBitrate: '3296000',
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://video.example/audio.m3u8'),
        headers: const {'origin': 'https://room.example'},
        label: 'English',
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(sourceA, sourceB);
    expect(
      PlayerState(
        status: PlaybackStatus.playing,
        source: sourceA,
        backend: PlayerBackend.memory,
      ),
      PlayerState(
        status: PlaybackStatus.playing,
        source: sourceB,
        backend: PlayerBackend.memory,
      ),
    );
  });
}
