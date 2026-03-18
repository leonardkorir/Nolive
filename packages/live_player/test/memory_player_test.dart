import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('memory player emits ready and playing states', () async {
    final player = MemoryPlayer();
    final emitted = <PlaybackStatus>[];
    final subscription = player.states.listen((state) {
      emitted.add(state.status);
    });

    await player.initialize();
    await player.setSource(
      PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
    );
    await player.play();
    await Future<void>.delayed(Duration.zero);

    expect(
      emitted,
      containsAll([
        PlaybackStatus.initializing,
        PlaybackStatus.ready,
        PlaybackStatus.playing,
      ]),
    );
    expect(player.currentState.backend, PlayerBackend.memory);
    expect(player.supportsEmbeddedView, isFalse);

    await subscription.cancel();
    await player.dispose();
  });

  test('switchable player keeps source when backend changes', () async {
    final player = SwitchablePlayer();
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.flv'));

    await player.initialize();
    await player.setSource(source);
    await player.play();
    await player.switchBackend(PlayerBackend.mpv);

    expect(player.backend, PlayerBackend.mpv);
    expect(player.currentState.source?.url, source.url);
    expect(player.currentState.status, PlaybackStatus.playing);
    expect(player.supportsEmbeddedView, isFalse);

    await player.switchBackend(PlayerBackend.mdk);
    expect(player.backend, PlayerBackend.mdk);
    expect(player.currentState.source?.url, source.url);

    await player.dispose();
  });

  test('switchable player can refresh same backend and keep source', () async {
    final player = SwitchablePlayer(initialBackend: PlayerBackend.mpv);
    final source =
        PlaybackSource(url: Uri.parse('https://example.com/live.m3u8'));

    await player.initialize();
    await player.setSource(source);
    await player.play();
    await player.refreshBackend();

    expect(player.backend, PlayerBackend.mpv);
    expect(player.currentState.source?.url, source.url);
    expect(player.currentState.status, PlaybackStatus.playing);

    await player.dispose();
  });
}
