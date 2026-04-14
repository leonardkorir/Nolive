import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_view_adapter.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  testWidgets('room runtime view adapter exposes runtime read surface', (
    tester,
  ) async {
    final player = TestRecordingPlayer(
      currentDiagnostics: PlayerDiagnostics(
        backend: PlayerBackend.mpv,
        width: 1920,
        height: 1080,
      ),
    );
    addTearDown(player.dispose);
    final runtime = PlayerRuntimeController(player);
    final adapter = RoomRuntimeViewAdapter(runtime);
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
    );
    player.emit(
      PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
        source: source,
      ),
    );
    final initialDiagnostics = adapter.initialDiagnostics;

    final diagnostics = adapter.diagnosticsStream.first;
    player.emitDiagnostics(
      PlayerDiagnostics(
        backend: PlayerBackend.mpv,
        width: 1280,
        height: 720,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: adapter.buildEmbeddedView(
          key: const Key('room-embedded-view'),
          aspectRatio: 16 / 9,
          fit: BoxFit.cover,
        ),
      ),
    );

    expect(adapter.supportsEmbeddedView, isTrue);
    expect(adapter.supportsScreenshot, isTrue);
    expect(adapter.backendLabel, 'MPV');
    expect(adapter.currentStatusLabel, 'playing');
    expect(adapter.currentPlaybackSource, source);
    expect(initialDiagnostics.width, 1920);
    expect(player.events, contains('buildView'));
    expect(player.viewKeys.last, const Key('room-embedded-view'));
    expect((await diagnostics).width, 1280);
  });
}
