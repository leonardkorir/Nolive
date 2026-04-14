import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('room runtime observation context forwards streams and current state',
      () async {
    final player = TestRecordingPlayer();
    addTearDown(player.dispose);
    final runtime = PlayerRuntimeController(player);
    final context = RoomRuntimeObservationContext.fromPlayerRuntime(runtime);
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
    );

    final stateFuture = context.states.first;
    player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: source,
      ),
    );

    final diagnosticsFuture = context.diagnostics.first;
    player.emitDiagnostics(
      PlayerDiagnostics(
        backend: player.backend,
        width: 1920,
        height: 1080,
      ),
    );

    expect(context.readCurrentState().source, source);
    expect((await stateFuture).source, source);
    expect((await diagnosticsFuture).width, 1920);
  });

  test(
      'room runtime control context keeps screenshot capability live across backend changes',
      () async {
    final player = TestRecordingPlayer(playerBackend: PlayerBackend.mpv);
    addTearDown(player.dispose);
    final runtime = _RuntimeControlTestRuntime(player);
    final context = RoomRuntimeControlContext.fromPlayerRuntime(runtime);

    expect(context.supportsScreenshot, isTrue);

    runtime.supportsScreenshotOverride = false;
    expect(context.supportsScreenshot, isFalse);

    await context.ensureBackendWithoutPlaybackState(PlayerBackend.mdk);
    final screenshot = await context.captureScreenshot();

    expect(runtime.ensuredBackends, <PlayerBackend>[PlayerBackend.mdk]);
    expect(screenshot, isNotNull);
    expect(context.resolveBackend(), PlayerBackend.mdk);
  });

  test('room runtime inspection context reflects live state and backend', () {
    final player = TestRecordingPlayer(playerBackend: PlayerBackend.mpv);
    addTearDown(player.dispose);
    final runtime = _RuntimeInspectionTestRuntime(player);
    final context = RoomRuntimeInspectionContext.fromPlayerRuntime(runtime);

    expect(context.resolveBackend(), PlayerBackend.mpv);

    runtime.backendOverride = PlayerBackend.mdk;
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/next.m3u8'),
    );
    player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: source,
      ),
    );

    expect(context.resolveBackend(), PlayerBackend.mdk);
    expect(context.readCurrentState().source, source);
  });
}

class _RuntimeControlTestRuntime extends PlayerRuntimeController {
  _RuntimeControlTestRuntime(this.player) : super(player);

  final TestRecordingPlayer player;
  final List<PlayerBackend> ensuredBackends = <PlayerBackend>[];
  PlayerBackend _backendOverride = PlayerBackend.mpv;
  bool supportsScreenshotOverride = true;

  @override
  PlayerBackend get backend => _backendOverride;

  @override
  bool get supportsScreenshot => supportsScreenshotOverride;

  @override
  Future<void> ensureBackendWithoutPlaybackState(PlayerBackend nextBackend) async {
    ensuredBackends.add(nextBackend);
    _backendOverride = nextBackend;
  }

  @override
  Future<Uint8List?> captureScreenshot() async => Uint8List.fromList(<int>[1]);
}

class _RuntimeInspectionTestRuntime extends PlayerRuntimeController {
  _RuntimeInspectionTestRuntime(this.player) : super(player);

  final TestRecordingPlayer player;
  PlayerBackend backendOverride = PlayerBackend.mpv;

  @override
  PlayerBackend get backend => backendOverride;
}
