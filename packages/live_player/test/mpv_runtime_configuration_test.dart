import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

class _FakeAndroidSurfacePlatform {
  _FakeAndroidSurfacePlatform(
    this.wid, {
    this.lock,
    Rect? rect,
    String? vo,
  })  : rect = ValueNotifier<Rect?>(rect),
        configuration = _FakeAndroidSurfaceConfiguration(vo);

  final ValueNotifier<int?> wid;
  final Object? lock;
  final ValueNotifier<Rect?> rect;
  final _FakeAndroidSurfaceConfiguration configuration;
  final List<MapEntry<String, String>> propertyWrites =
      <MapEntry<String, String>>[];

  Future<void> setProperty(String key, String value) async {
    propertyWrites.add(MapEntry<String, String>(key, value));
  }
}

class _FakeAndroidSurfaceConfiguration {
  const _FakeAndroidSurfaceConfiguration(this.vo);

  final String? vo;
}

class _FakeAsyncLock {
  Future<T> synchronized<T>(Future<T> Function() action) {
    return action();
  }
}

void main() {
  test('resolveMpvRuntimeConfiguration sanitizes empty custom output values',
      () {
    final config = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: false,
      doubleBufferingEnabled: false,
      customOutputEnabled: true,
      videoOutputDriver: '   ',
      hardwareDecoder: '',
      logEnabled: false,
    );

    expect(config.controllerConfiguration.vo, 'gpu-next');
    expect(config.controllerConfiguration.hwdec, 'auto-safe');
    expect(config.platformProperties['cache'], 'yes');
    expect(config.platformProperties['cache-secs'], '2');
    expect(config.platformProperties['demuxer-max-back-bytes'], '16777216');
    expect(config.platformProperties['demuxer-max-bytes'], '16777216');
    expect(config.platformProperties['demuxer-readahead-secs'], '2');
    expect(config.platformProperties['cache-pause'], 'no');
    expect(config.platformProperties['cache-pause-wait'], '1');
    expect(config.platformProperties['cache-pause-initial'], 'no');
  });

  test(
      'resolveMpvRuntimeConfiguration keeps Android attach timing on platform default path',
      () {
    final config = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: false,
      doubleBufferingEnabled: false,
      customOutputEnabled: false,
      videoOutputDriver: 'gpu-next',
      hardwareDecoder: 'auto-safe',
      logEnabled: false,
    );

    expect(
      config.controllerConfiguration.androidAttachSurfaceAfterVideoParameters,
      isNull,
    );
    expect(config.controllerConfiguration.hwdec, 'auto-safe');
  });

  test(
      'resolveMpvRuntimeConfiguration preserves explicit Android embedded mediacodec output',
      () {
    final customOutputConfig = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: false,
      doubleBufferingEnabled: false,
      customOutputEnabled: true,
      videoOutputDriver: 'mediacodec_embed',
      hardwareDecoder: 'mediacodec',
      logEnabled: false,
    );
    expect(
      customOutputConfig.controllerConfiguration.vo,
      'mediacodec_embed',
    );
    expect(
      customOutputConfig.controllerConfiguration.hwdec,
      'mediacodec',
    );
    expect(
      customOutputConfig
          .controllerConfiguration.androidAttachSurfaceAfterVideoParameters,
      isFalse,
    );
    expect(customOutputConfig.androidOutputFallbackReason, isNull);

    final compatConfig = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: true,
      doubleBufferingEnabled: false,
      customOutputEnabled: false,
      videoOutputDriver: 'gpu-next',
      hardwareDecoder: 'auto-safe',
      logEnabled: false,
    );
    expect(
      compatConfig.controllerConfiguration.vo,
      'mediacodec_embed',
    );
    expect(
      compatConfig.controllerConfiguration.hwdec,
      'mediacodec',
    );
    expect(
      compatConfig
          .controllerConfiguration.androidAttachSurfaceAfterVideoParameters,
      isFalse,
    );
    expect(compatConfig.androidOutputFallbackReason, isNull);
  });

  test(
      'shouldAwaitAndroidEmbeddedSurfaceBeforeOpen tracks Android mediacodec warm paths',
      () {
    expect(
      shouldAwaitAndroidEmbeddedSurfaceBeforeOpen(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldAwaitAndroidEmbeddedSurfaceBeforeOpen(
        compatMode: true,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
        hardwareDecoder: 'auto-safe',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldAwaitAndroidEmbeddedSurfaceBeforeOpen(
        compatMode: false,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
        hardwareDecoder: 'mediacodec',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldAwaitAndroidEmbeddedSurfaceBeforeOpen(
        compatMode: false,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
        hardwareDecoder: 'auto-safe',
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      shouldAwaitAndroidEmbeddedSurfaceBeforeOpen(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        isAndroid: false,
      ),
      isFalse,
    );
  });

  test(
      'resolveAndroidEmbeddedSurfaceWarmupPolicy keeps initial and reopen on the same short budget',
      () {
    final initial = resolveAndroidEmbeddedSurfaceWarmupPolicy(
      isInitialOpen: true,
    );
    final reuse = resolveAndroidEmbeddedSurfaceWarmupPolicy(
      isInitialOpen: false,
    );

    expect(
      initial.surfaceReadyBudget,
      reuse.surfaceReadyBudget,
    );
    expect(
      initial.viewMountTimeout,
      reuse.viewMountTimeout,
    );
    expect(
      initial.platformTimeout,
      reuse.platformTimeout,
    );
    expect(
      initial.surfaceReadyBudget,
      const Duration(milliseconds: 350),
    );
    expect(
      initial.surfaceReadyPollInterval,
      const Duration(milliseconds: 150),
    );
    expect(
      reuse.surfaceReadyBudget,
      const Duration(milliseconds: 350),
    );
  });

  test('shouldFallbackToSafeAndroidVideoOutput only targets embedded output',
      () {
    expect(
      shouldFallbackToSafeAndroidVideoOutput(
        compatMode: true,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
      ),
      isFalse,
    );
    expect(
      shouldFallbackToSafeAndroidVideoOutput(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'mediacodec_embed',
      ),
      isFalse,
    );
    expect(
      shouldFallbackToSafeAndroidVideoOutput(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'gpu-next',
      ),
      isFalse,
    );
    expect(
      shouldFallbackToSafeAndroidVideoOutput(
        compatMode: false,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
      ),
      isFalse,
    );
  });

  test('usesEmbeddedAndroidMediaCodecOutput only matches embedded output', () {
    expect(
      usesEmbeddedAndroidMediaCodecOutput(
        compatMode: true,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
      ),
      isTrue,
    );
    expect(
      usesEmbeddedAndroidMediaCodecOutput(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'mediacodec_embed',
      ),
      isTrue,
    );
    expect(
      usesEmbeddedAndroidMediaCodecOutput(
        compatMode: false,
        customOutputEnabled: true,
        videoOutputDriver: 'gpu-next',
      ),
      isFalse,
    );
  });

  test('shouldWarmAndroidMediaCodecOpenPath tracks mediacodec runtime paths',
      () {
    expect(
      shouldWarmAndroidMediaCodecOpenPath(
        videoOutputDriver: 'gpu',
        hardwareDecoder: 'mediacodec',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldWarmAndroidMediaCodecOpenPath(
        videoOutputDriver: 'mediacodec_embed',
        hardwareDecoder: 'no',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldWarmAndroidMediaCodecOpenPath(
        videoOutputDriver: 'gpu-next',
        hardwareDecoder: 'auto-safe',
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      shouldWarmAndroidMediaCodecOpenPath(
        videoOutputDriver: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        isAndroid: false,
      ),
      isFalse,
    );
  });

  test('waitForVideoControllerTextureReady resolves once a texture id appears',
      () async {
    final textureId = ValueNotifier<int?>(null);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        textureId.value = 9;
      }),
    );

    final ready = await waitForVideoControllerTextureReady(
      textureId,
      timeout: const Duration(milliseconds: 200),
    );

    expect(ready, isTrue);
  });

  test('waitForVideoControllerTextureReady times out for a missing texture',
      () async {
    final textureId = ValueNotifier<int?>(null);

    final ready = await waitForVideoControllerTextureReady(
      textureId,
      timeout: const Duration(milliseconds: 20),
    );

    expect(ready, isFalse);
  });

  test('waitForVideoControllerPlatformReady resolves once controller attaches',
      () async {
    final notifier = ValueNotifier<Object?>(null);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        notifier.value = Object();
      }),
    );

    final ready = await waitForVideoControllerPlatformReady(
      notifier,
      timeout: const Duration(milliseconds: 200),
    );

    expect(ready, isTrue);
  });

  test('waitForVideoControllerPlatformReady times out when attach is missing',
      () async {
    final notifier = ValueNotifier<Object?>(null);

    final ready = await waitForVideoControllerPlatformReady(
      notifier,
      timeout: const Duration(milliseconds: 20),
    );

    expect(ready, isFalse);
  });

  test('tryGetAndroidSurfaceHandleListenable returns wid notifier when present',
      () {
    final wid = ValueNotifier<int?>(null);
    final listenable = tryGetAndroidSurfaceHandleListenable(
      _FakeAndroidSurfacePlatform(wid),
    );

    expect(listenable, same(wid));
  });

  test('tryGetAndroidSurfaceHandleListenable ignores non-android controllers',
      () {
    expect(
      tryGetAndroidSurfaceHandleListenable(Object()),
      isNull,
    );
  });

  test('readAndroidSurfaceSnapshot captures wid and texture ids', () {
    final textureId = ValueNotifier<int?>(14);

    final snapshot = readAndroidSurfaceSnapshot(
      platform: _FakeAndroidSurfacePlatform(ValueNotifier<int?>(9)),
      textureId: textureId,
    );

    expect(snapshot.wid, 9);
    expect(snapshot.textureId, 14);
  });

  test('isAndroidSurfaceSnapshotReadyForMediaCodec requires wid publication',
      () {
    expect(
      isAndroidSurfaceSnapshotReadyForMediaCodec((wid: 0, textureId: 5)),
      isFalse,
    );
    expect(
      isAndroidSurfaceSnapshotReadyForMediaCodec((wid: 12, textureId: 0)),
      isTrue,
    );
  });

  test('waitForFreshAndroidSurfacePublication resolves on fresh wid change',
      () async {
    final wid = ValueNotifier<int?>(0);
    final textureId = ValueNotifier<int?>(0);
    final platform = _FakeAndroidSurfacePlatform(wid);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        wid.value = 18;
        textureId.value = 7;
      }),
    );

    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: textureId,
      previousSurface: (wid: 0, textureId: 0),
      timeout: const Duration(milliseconds: 200),
    );

    expect(refresh.changed, isTrue);
    expect(refresh.ready, isTrue);
    expect(refresh.currentSurface.wid, 18);
    expect(refresh.currentSurface.textureId, anyOf(0, 7));
  });

  test(
      'waitForFreshAndroidSurfacePublication requiring surface handle ignores texture-only publication',
      () async {
    final wid = ValueNotifier<int?>(0);
    final textureId = ValueNotifier<int?>(0);
    final platform = _FakeAndroidSurfacePlatform(wid);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        textureId.value = 9;
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 40), () {
        wid.value = 18;
      }),
    );

    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: textureId,
      previousSurface: (wid: 0, textureId: 0),
      timeout: const Duration(milliseconds: 200),
      requireSurfaceHandle: true,
    );

    expect(refresh.changed, isTrue);
    expect(refresh.ready, isTrue);
    expect(refresh.currentSurface.wid, 18);
    expect(refresh.currentSurface.textureId, 9);
  });

  test('waitForFreshAndroidSurfacePublication times out on stale surface',
      () async {
    final wid = ValueNotifier<int?>(8);
    final textureId = ValueNotifier<int?>(3);
    final platform = _FakeAndroidSurfacePlatform(wid);

    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: textureId,
      previousSurface: (wid: 8, textureId: 3),
      timeout: const Duration(milliseconds: 40),
    );

    expect(refresh.changed, isFalse);
    expect(refresh.ready, isFalse);
    expect(refresh.currentSurface.wid, 8);
    expect(refresh.currentSurface.textureId, 3);
  });

  test('waitForValueListenableValue resolves via predicate', () async {
    final notifier = ValueNotifier<int>(0);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        notifier.value = 3;
      }),
    );

    final ready = await waitForValueListenableValue<int>(
      notifier,
      isReady: (value) => value >= 3,
      timeout: const Duration(milliseconds: 200),
    );

    expect(ready, isTrue);
  });

  test('waitForAndroidSurfaceAttachStabilization waits for controller lock',
      () async {
    final lock = _FakeAsyncLock();
    final platform = _FakeAndroidSurfacePlatform(
      ValueNotifier<int?>(8),
      lock: lock,
    );

    final ready = await waitForAndroidSurfaceAttachStabilization(
      platform,
      timeout: const Duration(milliseconds: 50),
    );

    expect(ready, isTrue);
  });

  test('rebindAndroidVideoControllerSurface reapplies wid and vo ordering',
      () async {
    final platform = _FakeAndroidSurfacePlatform(
      ValueNotifier<int?>(8),
      lock: _FakeAsyncLock(),
      rect: const Rect.fromLTWH(0, 0, 1920, 1080),
      vo: 'mediacodec_embed',
    );

    final rebound = await rebindAndroidVideoControllerSurface(
      platform,
      timeout: const Duration(milliseconds: 50),
    );

    expect(rebound, isTrue);
    expect(
      platform.propertyWrites
          .map((entry) => '${entry.key}=${entry.value}')
          .toList(growable: false),
      const <String>[
        'vo=null',
        'android-surface-size=1920x1080',
        'wid=8',
        'vo=mediacodec_embed',
        'vid=auto',
      ],
    );
  });

  test(
      'waitForEitherValueListenableValue resolves when the secondary listenable becomes ready',
      () async {
    final primary = ValueNotifier<int?>(null);
    final secondary = ValueNotifier<int?>(null);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        secondary.value = 11;
      }),
    );

    final ready = await waitForEitherValueListenableValue<int?>(
      primary: primary,
      secondary: secondary,
      isReady: (value) => value != null && value > 0,
      timeout: const Duration(milliseconds: 200),
    );

    expect(ready, isTrue);
  });

  test(
      'shouldDelayAndroidEmbeddedPlayUntilSurfaceReady gates only incomplete initial opens',
      () {
    expect(
      shouldDelayAndroidEmbeddedPlayUntilSurfaceReady(
        isInitialOpen: true,
        previousSurface: (wid: 0, textureId: 0),
        warmupResult: (
          mounted: true,
          platformReady: true,
          surfaceReady: false,
          stabilized: false,
          attempts: 8,
          elapsed: const Duration(milliseconds: 1481),
          wid: 0,
          textureId: 4,
        ),
      ),
      isTrue,
    );
    expect(
      shouldDelayAndroidEmbeddedPlayUntilSurfaceReady(
        isInitialOpen: true,
        previousSurface: (wid: 0, textureId: 0),
        warmupResult: (
          mounted: true,
          platformReady: true,
          surfaceReady: true,
          stabilized: true,
          attempts: 1,
          elapsed: const Duration(milliseconds: 33),
          wid: 21,
          textureId: 5,
        ),
      ),
      isFalse,
    );
    expect(
      shouldDelayAndroidEmbeddedPlayUntilSurfaceReady(
        isInitialOpen: false,
        previousSurface: (wid: 19, textureId: 4),
        warmupResult: (
          mounted: true,
          platformReady: true,
          surfaceReady: true,
          stabilized: true,
          attempts: 1,
          elapsed: const Duration(milliseconds: 32),
          wid: 19,
          textureId: 4,
        ),
      ),
      isFalse,
    );
  });

  test('shouldReuseExistingAndroidSurfaceForReopen reuses a stable valid wid',
      () {
    expect(
      shouldReuseExistingAndroidSurfaceForReopen(
        previousSurface: (wid: 19, textureId: 4),
        currentSurface: (wid: 19, textureId: 4),
      ),
      isTrue,
    );
    expect(
      shouldReuseExistingAndroidSurfaceForReopen(
        previousSurface: (wid: 19, textureId: 4),
        currentSurface: (wid: 27, textureId: 9),
      ),
      isFalse,
    );
    expect(
      shouldReuseExistingAndroidSurfaceForReopen(
        previousSurface: (wid: 19, textureId: 4),
        currentSurface: (wid: 0, textureId: 4),
      ),
      isFalse,
    );
  });

  test(
      'classifyAndroidMediaCodecDeviceFailureReason distinguishes reinit noise',
      () {
    final openingDoneAt = DateTime(2026, 4, 24, 1, 14, 4, 525);

    expect(
      classifyAndroidMediaCodecDeviceFailureReason(
        lastOpeningDoneAt: openingDoneAt,
        failureTimestamp: openingDoneAt.add(const Duration(milliseconds: 12)),
      ),
      'mediacodec-device-creation-failed',
    );
    expect(
      classifyAndroidMediaCodecDeviceFailureReason(
        lastOpeningDoneAt: openingDoneAt,
        failureTimestamp: openingDoneAt.add(const Duration(milliseconds: 191)),
      ),
      'mpv-vd-reinit',
    );
  });

  test(
      'resolveAndroidEmbeddedHardwareDecoderReadyDelta clamps negative skew and reports positive lag',
      () {
    final surfaceReadyAt = DateTime(2026, 4, 24, 1, 35, 23, 622);

    expect(
      resolveAndroidEmbeddedHardwareDecoderReadyDelta(
        surfaceReadyAt: surfaceReadyAt,
        hardwareDecoderReadyAt:
            surfaceReadyAt.subtract(const Duration(milliseconds: 12)),
      ),
      Duration.zero,
    );
    expect(
      resolveAndroidEmbeddedHardwareDecoderReadyDelta(
        surfaceReadyAt: surfaceReadyAt,
        hardwareDecoderReadyAt:
            surfaceReadyAt.add(const Duration(milliseconds: 184)),
      ),
      const Duration(milliseconds: 184),
    );
  });

  test('shouldStopBeforeOpeningNextSource only blocks active sessions', () {
    expect(
      shouldStopBeforeOpeningNextSource(
        const PlayerState(status: PlaybackStatus.ready),
      ),
      isFalse,
    );
    expect(
      shouldStopBeforeOpeningNextSource(
        PlayerState(
          status: PlaybackStatus.ready,
          source:
              PlaybackSource(url: Uri.parse('https://example.com/live.flv')),
        ),
      ),
      isTrue,
    );
    expect(
      shouldStopBeforeOpeningNextSource(
        const PlayerState(status: PlaybackStatus.playing),
      ),
      isTrue,
    );
  });

  test(
      'resolveAndroidMpvOpenBarrierDuration differentiates first open and switch',
      () {
    expect(
      resolveAndroidMpvOpenBarrierDuration(
        isAndroid: false,
        hasPreviousSource: true,
      ),
      Duration.zero,
    );
    expect(
      resolveAndroidMpvOpenBarrierDuration(
        isAndroid: true,
        hasPreviousSource: false,
      ),
      const Duration(milliseconds: 150),
    );
    expect(
      resolveAndroidMpvOpenBarrierDuration(
        isAndroid: true,
        hasPreviousSource: true,
      ),
      const Duration(milliseconds: 650),
    );
  });

  test('resolveMpvOpenPreparation derives barrier from previous state only',
      () {
    final freshOpen = resolveMpvOpenPreparation(
      previousState: const PlayerState(status: PlaybackStatus.ready),
      isAndroid: true,
    );
    expect(freshOpen.shouldStopBeforeOpen, isFalse);
    expect(freshOpen.barrierDuration, const Duration(milliseconds: 150));

    final sourceSwitch = resolveMpvOpenPreparation(
      previousState: PlayerState(
        status: PlaybackStatus.ready,
        source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
      ),
      isAndroid: true,
    );
    expect(sourceSwitch.shouldStopBeforeOpen, isTrue);
    expect(sourceSwitch.barrierDuration, const Duration(milliseconds: 650));
  });

  test('shouldForceSeekableForSource keeps twitch ad-guard proxy seekable', () {
    final source = PlaybackSource(
      url: Uri.parse('http://127.0.0.1:19190/twitch-ad-guard/master.m3u8'),
    );

    expect(shouldForceSeekableForSource(source), isTrue);
  });

  test('shouldForceSeekableForSource leaves split ll-hls playback linear', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(shouldForceSeekableForSource(source), isFalse);
  });

  test(
      'shouldInlineSplitHlsAudioIntoSource uses synthetic master for mmcdn ll-hls with shared headers',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      headers: const {'referer': 'https://example.com/room'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        label: 'English',
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://example.com/room'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    expect(shouldInlineSplitHlsAudioIntoSource(source), isTrue);
  });

  test('buildSplitHlsMasterPlaylistContent composes a synthetic master', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        label: 'English',
        mimeType: 'application/x-mpegURL',
      ),
    );

    final manifest = buildSplitHlsMasterPlaylistContent(source);

    expect(
      manifest,
      contains(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,AUTOSELECT=YES,URI="https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8"',
      ),
    );
    expect(
      manifest,
      contains(
        '#EXT-X-STREAM-INF:BANDWIDTH=1324000,AUDIO="audio"',
      ),
    );
    expect(
      manifest,
      contains(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
    );
  });

  test(
      'maybeWriteResolvedSplitHlsMasterPlaylistFile preserves master metadata and rewrites relative split ll-hls uris',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const manifest = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_128",NAME="Audio_1_1_6",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test"
#EXT-X-STREAM-INF:BANDWIDTH=5128000,RESOLUTION=1920x1080,FRAME-RATE=30.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio_aac_128"
/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test
''';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write(manifest);
      await request.response.close();
    });
    final masterUrl = Uri.parse(
      'http://${server.address.host}:${server.port}/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
    );
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      masterPlaylistUrl: masterUrl,
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final file = await maybeWriteResolvedSplitHlsMasterPlaylistFile(source);

    expect(file, isNotNull);
    final rewritten = await file!.readAsString();
    expect(
      rewritten,
      contains(
        'URI="http://${server.address.host}:${server.port}/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test"',
      ),
    );
    expect(
      rewritten,
      contains(
        'http://${server.address.host}:${server.port}/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test',
      ),
    );
    expect(
      rewritten,
      contains('CODECS="avc1.640028,mp4a.40.2",AUDIO="audio_aac_128"'),
    );

    await server.close(force: true);
    await file.parent.delete(recursive: true);
  });

  test(
      'maybeWriteResolvedSplitHlsMasterPlaylistFile prefers embedded master content without refetching network',
      () async {
    const masterUrl =
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test';
    const embeddedManifest = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_128",NAME="Audio_1_1_6",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test"
#EXT-X-STREAM-INF:BANDWIDTH=5128000,RESOLUTION=1920x1080,FRAME-RATE=30.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio_aac_128"
/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test
''';

    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      masterPlaylistUrl: Uri.parse(masterUrl),
      masterPlaylistContent: embeddedManifest,
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final file = await maybeWriteResolvedSplitHlsMasterPlaylistFile(source);

    expect(file, isNotNull);
    final rewritten = await file!.readAsString();
    expect(
      rewritten,
      contains(
        'URI="https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test"',
      ),
    );
    expect(
      rewritten,
      contains(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test',
      ),
    );

    await file.parent.delete(recursive: true);
  });

  test(
      'buildResolvedSelectedSplitHlsMasterPlaylistContent keeps only the selected video and audio entries',
      () {
    const manifest = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_128",NAME="Audio 128",DEFAULT=YES,AUTOSELECT=YES,URI="http://127.0.0.1:9000/v1/edge/streams/origin.demo/chunklist_5_audio_llhls.m3u8?session=test"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio 96",DEFAULT=YES,AUTOSELECT=YES,URI="http://127.0.0.1:9000/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test"
#EXT-X-STREAM-INF:BANDWIDTH=1296000,RESOLUTION=854x480,AUDIO="audio_aac_128"
http://127.0.0.1:9000/v1/edge/streams/origin.demo/chunklist_1_video_llhls.m3u8?session=test
#EXT-X-STREAM-INF:BANDWIDTH=2096000,RESOLUTION=960x540,AUDIO="audio_aac_96"
http://127.0.0.1:9000/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test
''';
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    final selectedMaster = buildResolvedSelectedSplitHlsMasterPlaylistContent(
      source: source,
      manifest: manifest,
    );

    expect(
      selectedMaster,
      contains('GROUP-ID="audio_aac_96"'),
    );
    expect(
      selectedMaster,
      contains(
        '#EXT-X-STREAM-INF:BANDWIDTH=2096000,RESOLUTION=960x540,AUDIO="audio_aac_96"',
      ),
    );
    expect(
      selectedMaster,
      contains(
        'http://127.0.0.1:9000/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
      ),
    );
    expect(
      selectedMaster,
      isNot(contains('chunklist_1_video_llhls.m3u8')),
    );
    expect(
      selectedMaster,
      isNot(contains('chunklist_5_audio_llhls.m3u8')),
    );
  });

  test('shouldInlineSplitHlsAudioIntoSource stays off for non-ll split hls',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://video.example.com/live/video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://video.example.com/live/audio.m3u8',
        ),
        label: 'English',
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(shouldInlineSplitHlsAudioIntoSource(source), isFalse);
  });

  test('shouldUseAudioFilesPropertyForSource stays off for url-based ll-hls',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      headers: const {'referer': 'https://example.com/room'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://example.com/room'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    expect(shouldUseAudioFilesPropertyForSource(source), isFalse);
  });

  test(
      'shouldInlineSplitHlsAudioIntoSource uses resolved master for mmcdn v1 edge split ll-hls with shared headers',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.tootightwithbra.demo/chunklist_4_video_923524453125307562_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.tootightwithbra.demo/chunklist_6_audio_923524453125307562_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
    );
    expect(shouldInlineSplitHlsAudioIntoSource(source), isTrue);
  });

  test(
      'shouldFallbackToSyntheticSplitMaster stays off for mmcdn v1 edge split ll-hls',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_923524453125307562_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_923524453125307562_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
    );

    expect(shouldFallbackToSyntheticSplitMaster(source), isFalse);
  });

  test(
      'resolveMpvSourcePlatformProperties keeps mmcdn edge ll-hls master on buffered resolved-master path',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?session=test',
      ),
      masterPlaylistUrl: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?session=test',
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '8');
    expect(properties['demuxer-seekable-cache'], 'no');
    expect(properties['cache-pause'], 'yes');
    expect(properties['cache-pause-wait'], '2');
    expect(properties['cache-pause-initial'], 'yes');
    expect(properties['audio-buffer'], '0.4');
    expect(properties['demuxer-max-back-bytes'], '67108864');
    expect(
      properties['demuxer-lavf-o'],
      'protocol_whitelist=[file,crypto,data,http,https,tcp,tls],live_start_index=-1,seg_max_retry=3,http_persistent=1,http_multiple=0',
    );
    expect(properties['demuxer-lavf-analyzeduration'], '3');
    expect(properties['demuxer-lavf-probesize'], '500000');
    expect(properties['video-sync'], 'audio');
  });

  test(
      'maybeWriteResolvedSingleSourceHlsPlaylistFile still localizes mmcdn edge master when manifest already uses absolute uris',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const manifest = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-STREAM-INF:BANDWIDTH=5128000,RESOLUTION=1920x1080
https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test
''';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write(manifest);
      await request.response.close();
    });
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
      masterPlaylistUrl: Uri.parse(
        'http://${server.address.host}:${server.port}/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final file = await maybeWriteResolvedSingleSourceHlsPlaylistFile(source);

    expect(file, isNotNull);
    expect(
      await file!.readAsString(),
      contains(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test',
      ),
    );

    await server.close(force: true);
    await file.parent.delete(recursive: true);
  });

  test(
      'resolveMpvSourcePlatformProperties keeps split ll-hls on buffered resolved-master path',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_923524453125307562_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_923524453125307562_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '10');
    expect(properties['cache-on-disk'], 'no');
    expect(properties['cache-pause'], 'yes');
    expect(properties['cache-pause-wait'], '4');
    expect(properties['cache-pause-initial'], 'yes');
    expect(properties['audio-buffer'], '0.6');
    expect(
      properties['demuxer-lavf-o'],
      'protocol_whitelist=[file,crypto,data,http,https,tcp,tls],live_start_index=-1,seg_max_retry=3,http_persistent=1,http_multiple=0',
    );
    expect(properties['demuxer-lavf-analyzeduration'], '3');
    expect(properties['demuxer-lavf-probesize'], '500000');
    expect(properties['video-sync'], 'audio');
    expect(properties['demuxer-max-back-bytes'], '100663296');
    expect(properties.containsKey('audio-files'), isFalse);
    expect(properties['load-unsafe-playlists'], 'yes');
  });

  test(
      'resolveMpvSourcePlatformProperties uses a safer resolved-master profile for split ll-hls with master metadata',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_923524453125307562_llhls.m3u8?session=test',
      ),
      headers: const {'referer': 'https://chaturbate.com/'},
      masterPlaylistUrl: Uri.parse(
        'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?session=test',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge4-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_923524453125307562_llhls.m3u8?session=test',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://chaturbate.com/'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '8');
    expect(properties['cache-on-disk'], 'no');
    expect(properties['cache-pause'], 'yes');
    expect(properties['cache-pause-wait'], '2');
    expect(properties['cache-pause-initial'], 'yes');
    expect(properties['audio-buffer'], '0.4');
    expect(properties['demuxer-max-back-bytes'], '67108864');
    expect(
      properties['demuxer-lavf-o'],
      'protocol_whitelist=[file,crypto,data,http,https,tcp,tls],live_start_index=-1,seg_max_retry=3,http_persistent=1,http_multiple=0',
    );
    expect(properties['demuxer-lavf-analyzeduration'], '3');
    expect(properties['demuxer-lavf-probesize'], '500000');
    expect(properties['video-sync'], 'audio');
    expect(properties.containsKey('audio-files'), isFalse);
    expect(properties['load-unsafe-playlists'], 'yes');
    expect(properties.containsKey('hls-bitrate'), isFalse);
  });

  test(
      'resolveMpvSourcePlatformProperties clears source-scoped playlist overrides for plain streams',
      () {
    final source = PlaybackSource(
      url: Uri.parse('https://hw1a.douyucdn2.cn/live/demo.flv'),
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['demuxer-lavf-o'], isEmpty);
    expect(properties.containsKey('audio-files'), isFalse);
    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '2');
    expect(properties['cache-pause'], 'no');
    expect(properties['cache-pause-wait'], '1');
    expect(properties['cache-pause-initial'], 'no');
    expect(properties['demuxer-max-back-bytes'], '16777216');
    expect(properties['demuxer-max-bytes'], '16777216');
    expect(properties['demuxer-readahead-secs'], '2');
    expect(properties['audio-buffer'], '0.2');
    expect(properties['load-unsafe-playlists'], 'no');
    expect(properties.containsKey('vid'), isFalse);
    // Non-LL-HLS sources must NOT use audio-clock sync (it causes A/V drift
    // on display-synced streams like FLV/RTMP).
    expect(properties['video-sync'], 'display-tempo');
    // libmpv rejects runtime probesize writes below 32 even though
    // `mpv --list-options` prints a displayed default of 0. Keep the
    // writable FFmpeg default here so plain streams do not raise a
    // player error while still clearing LL-HLS-specific overrides.
    expect(properties['demuxer-lavf-analyzeduration'], '0');
    expect(properties['demuxer-lavf-probesize'], '5000000');
  });

  test(
      'shouldInlineSplitHlsAudioIntoSource stays off for non-ll split hls even when headers match',
      () {
    final source = PlaybackSource(
      url: Uri.parse('https://video.example.com/live/video.m3u8'),
      headers: const {'referer': 'https://example.com/room'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://video.example.com/live/audio.m3u8'),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://example.com/room'},
      ),
    );

    expect(shouldInlineSplitHlsAudioIntoSource(source), isFalse);
  });

  test(
      'shouldInlineSplitHlsAudioIntoSource stays off when split ll-hls headers differ',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      headers: const {'referer': 'https://example.com/room'},
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://example.com/other-room'},
      ),
    );

    expect(shouldInlineSplitHlsAudioIntoSource(source), isFalse);
  });

  test(
      'shouldUseAudioFilesPropertyForSource stays off when only audio headers exist',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
        headers: const {'referer': 'https://example.com/room'},
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    expect(shouldUseAudioFilesPropertyForSource(source), isFalse);
  });

  test('shouldForceSeekableForSource leaves generic hls live playback linear',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:edithgalpin/master.m3u8',
      ),
    );

    expect(shouldForceSeekableForSource(source), isFalse);
  });

  test('shouldForceSeekableForSource leaves flv live playback linear', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://pull-flv-q11.douyincdn.com/thirdgame/stream-407383673798656830.flv',
      ),
    );

    expect(shouldForceSeekableForSource(source), isFalse);
  });

  test('shouldIgnoreMpvErrorMessage filters tls_verify noise', () {
    final source = PlaybackSource(
      url: Uri.parse('https://pull-flv.example.com/live/demo.flv'),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: "ffmpeg: Could not set AVOption tls_verify='0'",
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage filters file cache noise', () {
    final source = PlaybackSource(
      url: Uri.parse('https://pull-flv.example.com/live/demo.flv'),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'ffmpeg: Failed to create file cache.',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage filters benign tls eof noise', () {
    final source = PlaybackSource(
      url: Uri.parse('https://hw3.douyucdn2.cn/live/demo.flv'),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'ffmpeg: tls: mbedtls_ssl_read returned -0x0',
      ),
      isTrue,
    );
  });

  test(
      'shouldIgnoreMpvErrorMessage filters benign tls eof noise without source',
      () {
    expect(
      shouldIgnoreMpvErrorMessage(
        source: null,
        message: 'ffmpeg: tls: mbedtls_ssl_read returned -0x0',
      ),
      isTrue,
    );
  });

  test(
      'shouldIgnoreMpvErrorMessage filters recoverable live nal corruption noise',
      () {
    final source = PlaybackSource(
      url: Uri.parse('https://al.flv.huya.com/src/demo.flv'),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'ffmpeg: NULL: Invalid NAL unit size (7113 > 4288).',
      ),
      isTrue,
    );
    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'ffmpeg: NULL: missing picture in access unit with size 4304',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage filters chaturbate benign mp4 warnings',
      () {
    final source = PlaybackSource(
      url:
          Uri.parse('http://127.0.0.1:18080/chaturbate-llhls/demo/stream.m3u8'),
      bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'ffmpeg/demuxer: mov,mp4,m4a,3gp,3g2,mj2: Found duplicated MOOV Atom. Skipped it',
      ),
      isTrue,
    );
    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'cplayer: Audio device underrun detected.',
      ),
      isTrue,
    );
  });

  test('shouldForceSeekableForSource keeps split dash playback untouched', () {
    final source = PlaybackSource(
      url: Uri.parse('https://rr1---sn.example.googlevideo.com/videoplayback'),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://rr1---sn.example.googlevideo.com/audio'),
        mimeType: 'audio/mp4',
      ),
    );

    expect(shouldForceSeekableForSource(source), isFalse);
  });

  test('shouldIgnoreMpvErrorMessage ignores ll-hls seekability warnings', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage ignores flv live seekability warnings', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://pull-flv-q11.douyincdn.com/thirdgame/stream-407383673798656830.flv',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test(
      'shouldIgnoreMpvErrorMessage ignores generic hls live seekability warnings',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:edithgalpin/master.m3u8',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage keeps other mpv errors visible', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'HTTP 403 while opening segment',
      ),
      isFalse,
    );
  });

  test('resolveMpvSourcePlatformProperties keeps split ll-hls low latency', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b5128000_video_llhls.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio_llhls.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
      bufferProfile: PlaybackBufferProfile.edgeLowLatencyHls,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '10');
    expect(properties['cache-on-disk'], 'no');
    expect(properties['cache-pause'], 'yes');
    expect(properties['cache-pause-wait'], '4');
    expect(properties['cache-pause-initial'], 'yes');
    expect(properties['audio-buffer'], '0.6');
    expect(properties['demuxer-max-back-bytes'], '100663296');
    expect(
      properties['demuxer-lavf-o'],
      'protocol_whitelist=[file,crypto,data,http,https,tcp,tls],live_start_index=-1,seg_max_retry=3,http_persistent=1,http_multiple=0',
    );
    expect(properties['demuxer-lavf-analyzeduration'], '3');
    expect(properties['demuxer-lavf-probesize'], '500000');
    expect(properties['video-sync'], 'audio');
    expect(properties.containsKey('hwdec'), isFalse);
    expect(properties['load-unsafe-playlists'], 'yes');
    expect(properties['hls-bitrate'], 'max');
  });

  test(
      'resolveMpvSourcePlatformProperties rewrites hwdec when runtime decoder is provided',
      () {
    final source = PlaybackSource(
      url: Uri.parse('https://hw1a.douyucdn2.cn/live/demo.flv'),
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
      hardwareDecoder: 'mediacodec',
    );

    expect(properties['hwdec'], 'mediacodec');
  });

  test('resolveMpvSourcePlatformProperties caps heavy stable stream buffers',
      () {
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/live.flv'),
      bufferProfile: PlaybackBufferProfile.heavyStreamStable,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '10');
    expect(properties['demuxer-max-back-bytes'], '67108864');
    expect(properties['demuxer-max-bytes'], '67108864');
    expect(properties['demuxer-readahead-secs'], '10');
  });

  test(
      'resolveMpvSourcePlatformProperties uses stable buffered profile for chaturbate loopback proxy',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'http://127.0.0.1:9999/chaturbate-llhls/session/stream.m3u8',
      ),
      bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['cache'], 'yes');
    expect(properties['cache-secs'], '10');
    expect(properties['cache-pause'], 'no');
    expect(properties['cache-pause-wait'], '1');
    expect(properties['cache-pause-initial'], 'no');
    expect(properties['audio-buffer'], '1.2');
    expect(properties['demuxer-seekable-cache'], 'no');
    expect(properties['demuxer-donate-buffer'], 'no');
    expect(properties['demuxer-max-back-bytes'], '33554432');
    expect(properties['demuxer-max-bytes'], '33554432');
    expect(properties['demuxer-readahead-secs'], '10');
    expect(
      properties['demuxer-lavf-o'],
      'live_start_index=-1,seg_max_retry=3,http_persistent=1,http_multiple=0',
    );
    expect(properties['demuxer-lavf-analyzeduration'], '2');
    expect(properties['demuxer-lavf-probesize'], '500000');
    expect(properties['video-sync'], 'audio');
    expect(properties['load-unsafe-playlists'], 'no');
    expect(properties.containsKey('hls-bitrate'), isFalse);
  });

  test('resolveMpvSourcePlatformProperties hardens chaturbate direct fallback',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge6-phx.live.mmcdn.com/live-hls/amlst:demo-sd/playlist.m3u8',
      ),
      bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
      hardwareDecoder: 'mediacodec',
    );

    expect(properties['hwdec'], 'auto-safe');
    expect(properties['demuxer-lavf-analyzeduration'], '5');
    expect(properties['demuxer-lavf-probesize'], '5000000');
    expect(properties['video-sync'], 'audio');
    expect(properties['load-unsafe-playlists'], 'yes');
  });

  test(
      'resolveMpvSourcePlatformProperties forwards preferred master hls bitrate',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
      hlsBitrate: '5128000',
    );

    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: false,
    );

    expect(properties['hls-bitrate'], '5128000');
  });

  test('shouldAllowUnsafePlaylistsForSource targets mmcdn hls playlists', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
    );

    expect(shouldAllowUnsafePlaylistsForSource(source), isTrue);
  });

  test('shouldBypassNativeMpvScreenshot skips Android embedded surface mode',
      () {
    expect(
      shouldBypassNativeMpvScreenshot(
        compatMode: true,
        customOutputEnabled: false,
        videoOutputDriver: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldBypassNativeMpvScreenshot(
        compatMode: false,
        customOutputEnabled: false,
        videoOutputDriver: 'gpu-next',
        hardwareDecoder: 'auto-safe',
        isAndroid: false,
      ),
      isFalse,
    );
  });

  test('shouldRewriteSingleSourceHlsManifest targets mmcdn edge master hls',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
    );

    expect(shouldRewriteSingleSourceHlsManifest(source), isTrue);
  });

  test('shouldRewriteSingleSourceHlsManifest stays off for mmcdn chunklists',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge17-phx.live.mmcdn.com/live-hls/amlst:emersoncane-sd-demo/chunklist_w1832301664_b2796000_tdemo.m3u8',
      ),
    );

    expect(shouldRewriteSingleSourceHlsManifest(source), isFalse);
  });

  test('rewriteHlsManifestWithAbsoluteUris resolves relative hls references',
      () {
    final manifest = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: Uri.parse(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      ),
      manifest: '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="/v1/edge/streams/origin.demo/chunklist_audio.m3u8?session=test"
#EXT-X-STREAM-INF:BANDWIDTH=3296000,AUDIO="audio"
/v1/edge/streams/origin.demo/chunklist_video.m3u8?session=test
segment_00001.ts
''',
    );

    expect(
      manifest,
      contains(
        'URI="https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_audio.m3u8?session=test"',
      ),
    );
    expect(
      manifest,
      contains(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_video.m3u8?session=test',
      ),
    );
    expect(
      manifest,
      contains(
        'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/segment_00001.ts',
      ),
    );
  });
}
