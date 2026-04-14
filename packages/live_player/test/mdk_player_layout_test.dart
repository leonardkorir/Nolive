import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('resolveMdkTextureRenderSize prefers decoded video size', () {
    final size = resolveMdkTextureRenderSize(
      diagnostics: const PlayerDiagnostics(
        backend: PlayerBackend.mdk,
        width: 1920,
        height: 1080,
      ),
      aspectRatio: null,
    );

    expect(size.width, 1920);
    expect(size.height, 1080);
  });

  test('resolveMdkTextureRenderSize falls back to requested aspect ratio', () {
    final size = resolveMdkTextureRenderSize(
      diagnostics: const PlayerDiagnostics(backend: PlayerBackend.mdk),
      aspectRatio: 16 / 9,
    );

    expect(size.width, closeTo(1777.777, 0.01));
    expect(size.height, 1000);
  });

  test('resolveMdkTextureRenderSize keeps non-zero default size', () {
    final size = resolveMdkTextureRenderSize(
      diagnostics: const PlayerDiagnostics(backend: PlayerBackend.mdk),
      aspectRatio: null,
    );

    expect(size.width, 1600);
    expect(size.height, 900);
  });

  test('resolveMdkPostTextureStatus preserves playing state', () {
    final status = resolveMdkPostTextureStatus(
      currentStatus: PlaybackStatus.playing,
    );

    expect(status, PlaybackStatus.playing);
  });

  test('resolveMdkPostTextureStatus promotes buffering to ready', () {
    final status = resolveMdkPostTextureStatus(
      currentStatus: PlaybackStatus.buffering,
    );

    expect(status, PlaybackStatus.ready);
  });

  test('resolveMdkBufferingStatusTransition enters buffering while playing',
      () {
    final status = resolveMdkBufferingStatusTransition(
      currentStatus: PlaybackStatus.playing,
      buffering: true,
      hasSource: true,
      firstFrameRendered: true,
    );

    expect(status, PlaybackStatus.buffering);
  });

  test('resolveMdkBufferingStatusTransition restores playing after rebuffer',
      () {
    final status = resolveMdkBufferingStatusTransition(
      currentStatus: PlaybackStatus.buffering,
      buffering: false,
      hasSource: true,
      firstFrameRendered: true,
    );

    expect(status, PlaybackStatus.playing);
  });

  test('resolveMdkBufferingStatusTransition restores ready before first frame',
      () {
    final status = resolveMdkBufferingStatusTransition(
      currentStatus: PlaybackStatus.buffering,
      buffering: false,
      hasSource: true,
      firstFrameRendered: false,
    );

    expect(status, PlaybackStatus.ready);
  });

  test('resolveMdkBufferingStatusTransition keeps paused state stable', () {
    final status = resolveMdkBufferingStatusTransition(
      currentStatus: PlaybackStatus.paused,
      buffering: true,
      hasSource: true,
      firstFrameRendered: true,
    );

    expect(status, isNull);
  });

  test('shouldPrimeMdkPlaybackBeforeTexture follows tunnel mode', () {
    expect(
      shouldPrimeMdkPlaybackBeforeTexture(androidTunnel: true),
      isTrue,
    );
    expect(
      shouldPrimeMdkPlaybackBeforeTexture(androidTunnel: false),
      isFalse,
    );
  });

  test('shouldAttemptMdkTunnelFallback only when tunnel stall is recoverable',
      () {
    expect(
      shouldAttemptMdkTunnelFallback(
        androidTunnel: true,
        firstFrameRendered: false,
        fallbackAttempted: false,
        hasSource: true,
        textureId: 3,
      ),
      isTrue,
    );
    expect(
      shouldAttemptMdkTunnelFallback(
        androidTunnel: true,
        firstFrameRendered: true,
        fallbackAttempted: false,
        hasSource: true,
        textureId: 3,
      ),
      isFalse,
    );
    expect(
      shouldAttemptMdkTunnelFallback(
        androidTunnel: true,
        firstFrameRendered: false,
        fallbackAttempted: true,
        hasSource: true,
        textureId: 3,
      ),
      isFalse,
    );
    expect(
      shouldAttemptMdkTunnelFallback(
        androidTunnel: true,
        firstFrameRendered: false,
        fallbackAttempted: false,
        hasSource: false,
        textureId: 3,
      ),
      isFalse,
    );
    expect(
      shouldAttemptMdkTunnelFallback(
        androidTunnel: false,
        firstFrameRendered: false,
        fallbackAttempted: false,
        hasSource: true,
        textureId: 3,
      ),
      isFalse,
    );
  });

  test('resolveMdkRegisterOptions includes tunnel-aware low latency config',
      () {
    final options = resolveMdkRegisterOptions(
      lowLatency: true,
      androidTunnel: true,
    );

    expect(options, <String, Object>{
      'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
      'lowLatency': 2,
      'tunnel': true,
    });
  });

  test('resolveMdkRegisterOptions omits low latency when disabled', () {
    final options = resolveMdkRegisterOptions(
      lowLatency: false,
      androidTunnel: false,
    );

    expect(options, <String, Object>{
      'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
      'tunnel': false,
    });
  });

  test('resolveMdkBufferStrategy keeps default low latency buffer window', () {
    final strategy = resolveMdkBufferStrategy(lowLatency: true);

    expect(strategy.minMs, 500);
    expect(strategy.maxMs, 4000);
    expect(strategy.drop, isFalse);
  });

  test('resolveMdkBufferStrategy widens heavy stream buffer window', () {
    final strategy = resolveMdkBufferStrategy(
      lowLatency: true,
      bufferProfile: PlaybackBufferProfile.heavyStreamStable,
    );

    expect(strategy.minMs, 1000);
    expect(strategy.maxMs, 8000);
    expect(strategy.drop, isFalse);
  });

  test('resolveMdkBufferStrategy keeps normal mode on wider buffer', () {
    final strategy = resolveMdkBufferStrategy(lowLatency: false);

    expect(strategy.minMs, 500);
    expect(strategy.maxMs, 6000);
    expect(strategy.drop, isFalse);
  });

  test('shouldPollMdkRuntimeDiagnostics only while playback context exists',
      () {
    expect(
      shouldPollMdkRuntimeDiagnostics(
        hasSource: false,
        hasTexture: false,
      ),
      isFalse,
    );
    expect(
      shouldPollMdkRuntimeDiagnostics(
        hasSource: true,
        hasTexture: false,
      ),
      isTrue,
    );
    expect(
      shouldPollMdkRuntimeDiagnostics(
        hasSource: false,
        hasTexture: true,
      ),
      isTrue,
    );
  });

  test('resolveMdkPreferredVideoDecoders prefers Android hardware decoding',
      () {
    final decoders = resolveMdkPreferredVideoDecoders(
      preferHardwareVideoDecoder: true,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(decoders, const <String>['AMediaCodec', 'MediaCodec', 'FFmpeg']);
  });

  test(
      'resolveMdkPreferredVideoDecoders stays null when disabled or unsupported',
      () {
    expect(
      resolveMdkPreferredVideoDecoders(
        preferHardwareVideoDecoder: false,
        targetPlatform: TargetPlatform.android,
        isWeb: false,
      ),
      isNull,
    );
    expect(
      resolveMdkPreferredVideoDecoders(
        preferHardwareVideoDecoder: true,
        targetPlatform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isNull,
    );
  });

  test('isMdkTextureReleaseDetached treats cleared -1 result as benign', () {
    expect(
      isMdkTextureReleaseDetached(
        result: -1,
        activeTextureIdAfter: -1,
      ),
      isTrue,
    );
    expect(
      isMdkTextureReleaseDetached(
        result: -1,
        activeTextureIdAfter: null,
      ),
      isTrue,
    );
    expect(
      isMdkTextureReleaseDetached(
        result: -1,
        activeTextureIdAfter: 3,
      ),
      isFalse,
    );
    expect(
      isMdkTextureReleaseDetached(
        result: 0,
        activeTextureIdAfter: -1,
      ),
      isFalse,
    );
  });
}
