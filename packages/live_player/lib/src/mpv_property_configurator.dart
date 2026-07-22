part of 'mpv_player.dart';

class MpvPropertyConfigurator {
  const MpvPropertyConfigurator();

  MpvRuntimeConfiguration resolveRuntimeConfiguration({
    required bool enableHardwareAcceleration,
    required bool compatMode,
    required bool doubleBufferingEnabled,
    required bool customOutputEnabled,
    required String videoOutputDriver,
    required String audioOutputDriver,
    required String hardwareDecoder,
    required bool logEnabled,
    bool isAndroid = false,
    bool allowExternalNativeWindow = false,
  }) {
    return resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: enableHardwareAcceleration,
      compatMode: compatMode,
      doubleBufferingEnabled: doubleBufferingEnabled,
      customOutputEnabled: customOutputEnabled,
      videoOutputDriver: videoOutputDriver,
      audioOutputDriver: audioOutputDriver,
      hardwareDecoder: hardwareDecoder,
      logEnabled: logEnabled,
      isAndroid: isAndroid,
      allowExternalNativeWindow: allowExternalNativeWindow,
    );
  }

  Map<String, String> resolveSourcePlatformProperties({
    required PlaybackSource source,
    required bool doubleBufferingEnabled,
    String? hardwareDecoder,
    String? videoTrackSelection,
    bool isAndroid = false,
  }) {
    return resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: doubleBufferingEnabled,
      hardwareDecoder: hardwareDecoder,
      videoTrackSelection: videoTrackSelection,
      isAndroid: isAndroid,
    );
  }
}

extension MpvPlayerPropertyLifecycle on MpvPlayer {
  Future<bool> _configureSourceOptions(
    mk.Player player,
    PlaybackSource source,
  ) async {
    final dynamic platform = player.platform;
    if (platform == null) {
      return false;
    }
    final properties = resolveMpvSourcePlatformProperties(
      source: source,
      doubleBufferingEnabled: doubleBufferingEnabled,
      hardwareDecoder: _runtimeConfiguration?.controllerConfiguration.hwdec
          ?.trim(),
      videoTrackSelection: 'auto',
      isAndroid: isAndroid,
    );
    _logEvent(
      'source options '
      'hwdec=${properties['hwdec'] ?? 'inherit'} '
      'vid=${properties['vid'] ?? 'inherit'} '
      'cache=${properties['cache']} '
      'cache-secs=${properties['cache-secs']} '
      'demuxer-readahead-secs=${properties['demuxer-readahead-secs'] ?? 'inherit'} '
      'demuxer-max-bytes=${properties['demuxer-max-bytes'] ?? 'inherit'} '
      'hls-bitrate=${properties['hls-bitrate'] ?? 'inherit'} '
      'bufferProfile=${source.bufferProfile.name}',
    );
    var preloadedExternalAudioConfigured = false;
    for (final entry in properties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
        if (entry.key == 'audio-files' && entry.value.trim().isNotEmpty) {
          preloadedExternalAudioConfigured = true;
        }
      } catch (_) {
        // Older media_kit backends may not expose direct mpv property writes.
      }
    }
    return preloadedExternalAudioConfigured;
  }

  Future<void> _configurePlayerProperties(
    mk.Player player, {
    required Map<String, String> properties,
  }) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      return;
    }
    for (final entry in properties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        // Ignore unsupported native properties on older backends.
      }
    }
  }

  /// Tear down the independent VO window and leave vo=null while idle.
  Future<void> _parkExternalNativeWindow(mk.Player player) async {
    try {
      final platform = player.platform;
      if (platform is mk.NativePlayer) {
        await platform.setProperty('vo', 'null');
      }
    } catch (_) {
      // Best-effort park.
    }
    // Give X11/GLX time to finish X_GLXDestroyWindow before WebKit opens.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _logEvent('stop external-native-window parked vo=null');
  }

  /// Destroy the in-process libmpv handle so no GLX resources remain.
  ///
  /// Must only be called from the stop/dispose serialization path when
  /// [usesExternalNativeWindow] is true. Next [setSource] recreates it.
  Future<void> _teardownExternalNativeMediaKitPlayer() async {
    final player = _player;
    if (player == null) {
      return;
    }
    for (final subscription in List<StreamSubscription<dynamic>>.of(
      _subscriptions,
    )) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
    _player = null;
    _controller = null;
    _controllerNotifier.value = null;
    _initialized = false;
    _runtimeConfiguration = null;
    try {
      await player.dispose();
    } catch (error) {
      _logEvent('external-native-window dispose ignored error=$error');
    }
    // Extra settle: WebKit headless create races late GLX destroy callbacks.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _logEvent('external-native-window full teardown done');
  }

  /// Enable gpu-next/gpu only immediately before open() with real media.
  Future<void> _armExternalNativeWindowForPlayback(mk.Player player) async {
    if (_runtimeConfiguration?.usesExternalNativeWindow != true) {
      return;
    }
    final externalVo =
        _runtimeConfiguration?.externalNativeVideoOutputDriver ??
        kDefaultExternalNativeVideoOutputDriver;
    try {
      final platform = player.platform;
      if (platform is mk.NativePlayer) {
        await platform.setProperty('vo', externalVo);
        _logEvent('setSource external-native-window armed vo=$externalVo');
      }
    } catch (error) {
      _logEvent(
        'setSource external-native-window arm failed error=$error',
      );
    }
  }
}

class MpvRuntimeConfiguration {
  const MpvRuntimeConfiguration({
    required this.controllerConfiguration,
    required this.logLevel,
    required this.platformProperties,
    this.androidOutputFallbackReason,
    this.usesExternalNativeWindow = false,
    this.externalNativeVideoOutputDriver,
  });

  final VideoControllerConfiguration controllerConfiguration;
  final mk.MPVLogLevel logLevel;
  final Map<String, String> platformProperties;
  final String? androidOutputFallbackReason;

  /// When true, video is rendered by mpv's own VO window (gpu-next/gpu/...).
  /// Flutter embed texture / VideoController must not be created.
  final bool usesExternalNativeWindow;

  /// Effective external VO (e.g. gpu-next). Null when embed path is used.
  final String? externalNativeVideoOutputDriver;
}

Future<Uint8List?> waitForScreenshotFileBytes(
  File file, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 40),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        return bytes;
      }
    }
    await Future<void>.delayed(pollInterval);
  }
  return null;
}

bool shouldIgnoreMpvErrorMessage({
  required PlaybackSource? source,
  required String message,
}) {
  final normalized = message.toLowerCase();
  if (normalized.contains("could not set avoption tls_verify='0'")) {
    return true;
  }
  if (normalized.contains('failed to create file cache')) {
    return true;
  }
  if (source == null) {
    return normalized.contains('mbedtls_ssl_read returned -0x0');
  }
  final isLiveSource =
      _looksLikeLiveFlv(source.url) || _looksLikeLiveHlsSource(source);
  if (normalized.contains('mbedtls_ssl_read returned -0x0') && isLiveSource) {
    return true;
  }
  if (isLiveSource &&
      (normalized.contains('invalid nal unit size') ||
          normalized.contains('missing picture in access unit'))) {
    return true;
  }
  // Stripchat / CB local LL-HLS fMP4: intermittent AAC decode glitches during
  // ABR / sliding-window refresh must not hard-fail the room (Android keeps
  // playing; desktop libmpv surfaces "Error decoding audio" as stream.error).
  if ((source.bufferProfile == PlaybackBufferProfile.loopbackStableHls ||
          source.bufferProfile ==
              PlaybackBufferProfile.chaturbateLlHlsProxyStable) &&
      (normalized.contains('found duplicated moov atom') ||
          normalized.contains('audio device underrun') ||
          normalized.contains('error decoding audio') ||
          normalized.contains('invalid audio pts'))) {
    return true;
  }
  final isSeekabilityWarning =
      normalized.contains('cannot seek in this stream') ||
      normalized.contains('force-seekable=yes');
  if (!isSeekabilityWarning) {
    return false;
  }
  return shouldForceSeekableForSource(source) ||
      _looksLikeLiveFlv(source.url) ||
      _looksLikeLiveHlsSource(source);
}

bool looksLikeMpvScreenshotFailureMessage(String message) {
  final normalized = message.trim().toLowerCase();
  return normalized.contains('taking screenshot failed') ||
      normalized.contains(
        'error running command _command(screenshot-to-file',
      ) ||
      normalized.contains('error running command event:');
}

bool shouldBypassNativeMpvScreenshot({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool isAndroid,
}) {
  if (!isAndroid) {
    return false;
  }
  final normalizedVideoOutput = videoOutputDriver.trim().toLowerCase();
  final normalizedHardwareDecoder = hardwareDecoder.trim().toLowerCase();
  if (compatMode) {
    return true;
  }
  if (customOutputEnabled &&
      (normalizedVideoOutput.contains('mediacodec') ||
          normalizedHardwareDecoder.startsWith('mediacodec'))) {
    return true;
  }
  return false;
}

Map<String, String> resolveMpvSourcePlatformProperties({
  required PlaybackSource source,
  required bool doubleBufferingEnabled,
  String? hardwareDecoder,
  String? videoTrackSelection,
  bool isAndroid = false,
}) {
  final prefersChaturbateProxyStableBuffer =
      source.bufferProfile == PlaybackBufferProfile.chaturbateLlHlsProxyStable;
  final prefersLoopbackStableBuffer =
      source.bufferProfile == PlaybackBufferProfile.loopbackStableHls;
  final prefersDesktopStableLive =
      source.bufferProfile == PlaybackBufferProfile.desktopStableLive;
  final prefersChaturbateDirectStableFallback =
      prefersChaturbateProxyStableBuffer &&
      !_looksLikeChaturbateLoopbackProxySource(source);
  final prefersEdgeLowLatencyHls =
      source.bufferProfile == PlaybackBufferProfile.edgeLowLatencyHls;
  final prefersStableSplitEdgeHls =
      prefersEdgeLowLatencyHls &&
      _looksLikeMmcdnSplitLowLatencyHlsSource(source);
  final prefersLocalizedSplitEdgeMaster =
      prefersStableSplitEdgeHls &&
      shouldInlineSplitHlsAudioIntoSource(source) &&
      (source.masterPlaylistUrl != null ||
          (source.masterPlaylistContent?.trim().isNotEmpty ?? false));
  final prefersStableMasterEdgeHls =
      prefersEdgeLowLatencyHls &&
      _isSingleSourceLocalizedLowLatencyMaster(source);
  final prefersStripchatLoopbackStableMaster =
      prefersEdgeLowLatencyHls &&
      _looksLikeStripchatLoopbackProxySource(source);
  final prefersYoutubeLocalizedHlsMaster =
      _hasEmbeddedGooglevideoMasterPlaylist(source);
  final inlinesStableSplitEdgeHls =
      prefersStableSplitEdgeHls && shouldInlineSplitHlsAudioIntoSource(source);
  final prefersStableBuffer =
      source.bufferProfile == PlaybackBufferProfile.heavyStreamStable;
  final normalizedHardwareDecoder = hardwareDecoder?.trim() ?? '';
  final normalizedVideoTrackSelection = videoTrackSelection?.trim() ?? '';
  final properties = <String, String>{
    'force-seekable':
        shouldForceSeekableForSource(source, isAndroid: isAndroid)
        ? 'yes'
        : 'no',
    'demuxer-lavf-o': '',
    // Reset per-source lavf probe limits for the next source. `mpv` reports
    // a displayed default of `0` for demuxer-lavf-probesize, but libmpv
    // rejects runtime writes below 32. Use FFmpeg's writable default probe
    // size instead so plain FLV/HLS rooms do not trip a player error.
    'demuxer-lavf-analyzeduration': '0',
    'demuxer-lavf-probesize': '5000000',
    'cache-on-disk': 'no',
    // Keep these runtime knobs explicitly reset so a Chaturbate-specific
    // buffering profile cannot leak into the next room/source.
    'cache-pause': 'yes',
    'cache-pause-wait': '1',
    'cache-pause-initial': 'no',
    'audio-buffer': '0.2',
    // Default: use display-tempo for non-LL-HLS; overridden to `audio` below
    // for split LL-HLS where PTS discontinuities between the separate video
    // and audio chunklists would otherwise cause A/V desynchronisation.
    'video-sync': 'display-tempo',
    // Desktop: drop late frames at VO when the embed texture cannot keep up
    // (S/W upload path). Prefer this over time-throttling the texture thread.
    if (!isAndroid) 'framedrop': 'vo',
    if (normalizedVideoTrackSelection.isNotEmpty)
      'vid': normalizedVideoTrackSelection,
    if (normalizedHardwareDecoder.isNotEmpty)
      'hwdec': normalizedHardwareDecoder,
  };
  if (prefersChaturbateProxyStableBuffer) {
    properties.addAll(const <String, String>{
      'cache': 'yes',
      'cache-secs': '10',
      'demuxer-seekable-cache': 'no',
      'demuxer-donate-buffer': 'no',
      'demuxer-max-back-bytes': '33554432',
      'demuxer-max-bytes': '33554432',
      'demuxer-readahead-secs': '10',
      'cache-pause': 'no',
      'cache-pause-wait': '1',
      'cache-pause-initial': 'no',
      'audio-buffer': '1.2',
    });
    // Desktop: slightly thicker demuxer headroom for 1080p LL-HLS quality switches.
    if (!isAndroid) {
      properties['cache-secs'] = '12';
      properties['demuxer-readahead-secs'] = '12';
      properties['demuxer-max-back-bytes'] = '50331648';
      properties['demuxer-max-bytes'] = '50331648';
      properties['audio-buffer'] = '1.4';
    }
    properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
      'live_start_index': '-1',
      'seg_max_retry': '3',
      'http_persistent': '1',
      'http_multiple': '0',
    });
    if (prefersChaturbateDirectStableFallback) {
      properties['demuxer-lavf-analyzeduration'] = '5';
      properties['demuxer-lavf-probesize'] = '5000000';
      // Do not force hwdec=auto-safe here: on desktop libmpv embed that
      // overrides the shared runtime decoder (auto-copy) and often leaves
      // hwdec-current inactive. Preserve the runtime/normalized hwdec set above
      // so Linux VAAPI/NVDEC stay engaged for Chaturbate like every other site.
    } else {
      properties['demuxer-lavf-analyzeduration'] = '2';
      properties['demuxer-lavf-probesize'] = '500000';
    }
    // Desktop: display-tempo reduces visible tear vs audio-clock frame timing
    // on S/W texture upload; Android keeps audio for split LL-HLS A/V glue.
    properties['video-sync'] = isAndroid ? 'audio' : 'display-tempo';
  } else if (prefersDesktopStableLive) {
    // Foreign live (Twitch / YouTube): multi-second cache on desktop; Android
    // phone/tablet/ChromeOS use a middle band (~48MB / 16s) — softer than
    // desktop 128MB, larger than the prior 32MB/10s underrun-prone floor.
    // Android keeps video-sync=audio for MediaCodec A/V glue.
    properties.addAll(<String, String>{
      'cache': 'yes',
      'cache-secs': isAndroid ? '16' : '22',
      'demuxer-seekable-cache': 'no',
      'demuxer-donate-buffer': 'no',
      'demuxer-max-back-bytes': isAndroid ? '50331648' : '134217728',
      'demuxer-max-bytes': isAndroid ? '50331648' : '134217728',
      'demuxer-readahead-secs': isAndroid ? '16' : '22',
      'cache-pause': 'yes',
      // Shorter pause-wait: long freezes felt like "卡" even with large buffer.
      'cache-pause-wait': isAndroid ? '2' : '5',
      'cache-pause-initial': 'yes',
      'audio-buffer': isAndroid ? '0.8' : '1.4',
      'video-sync': isAndroid ? 'audio' : 'display-tempo',
    });
    properties['demuxer-lavf-o'] = _buildLavfOptionString({
      if (prefersYoutubeLocalizedHlsMaster)
        'protocol_whitelist': 'file,crypto,data,http,https,tcp,tls',
      // Keep a few segments of headroom against proxy/CDN RTT spikes.
      'live_start_index': isAndroid ? '-3' : '-3',
      'seg_max_retry': '10',
      'http_persistent': '1',
      // Parallel local-proxy GETs reduce underrun when warm is still filling.
      'http_multiple': '1',
    });
    properties['demuxer-lavf-analyzeduration'] = '3';
    properties['demuxer-lavf-probesize'] = '500000';
  } else if (prefersEdgeLowLatencyHls) {
    if (prefersStripchatLoopbackStableMaster) {
      properties.addAll(const <String, String>{
        'cache': 'yes',
        'cache-secs': '3',
        'demuxer-seekable-cache': 'no',
        'demuxer-donate-buffer': 'no',
        'demuxer-max-back-bytes': '25165824',
        'demuxer-max-bytes': '25165824',
        'demuxer-readahead-secs': '3',
        'cache-pause': 'no',
        'cache-pause-wait': '1',
        'cache-pause-initial': 'no',
        'audio-buffer': '0.2',
      });
      properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
        'protocol_whitelist': 'file,crypto,data,http,https,tcp,tls',
        'live_start_index': '-2',
        'seg_max_retry': '6',
        'http_persistent': '1',
        'http_multiple': '1',
      });
      properties['demuxer-lavf-analyzeduration'] = '2';
      properties['demuxer-lavf-probesize'] = '500000';
      properties['video-sync'] = 'audio';
    } else if (prefersStableSplitEdgeHls || prefersStableMasterEdgeHls) {
      // Split LL-HLS on mmcdn becomes unstable when mpv hugs the live edge
      // too tightly. When we can localize a real master for the split stream,
      // reuse the buffered edge-master startup profile instead of the tighter
      // split profile so playback starts far enough behind the live window.
      properties.addAll(
        prefersLocalizedSplitEdgeMaster
            ? const <String, String>{
                'cache': 'yes',
                'cache-secs': '8',
                'demuxer-seekable-cache': 'no',
                'demuxer-donate-buffer': 'no',
                'demuxer-max-back-bytes': '67108864',
                'demuxer-max-bytes': '67108864',
                'demuxer-readahead-secs': '8',
                'cache-pause': 'yes',
                'cache-pause-wait': '2',
                'cache-pause-initial': 'yes',
                'audio-buffer': '0.4',
              }
            : (prefersStableMasterEdgeHls ||
                  prefersStripchatLoopbackStableMaster)
            ? const <String, String>{
                'cache': 'yes',
                'cache-secs': '8',
                'demuxer-seekable-cache': 'no',
                'demuxer-donate-buffer': 'no',
                'demuxer-max-back-bytes': '67108864',
                'demuxer-max-bytes': '67108864',
                'demuxer-readahead-secs': '8',
                'cache-pause': 'yes',
                'cache-pause-wait': '2',
                'cache-pause-initial': 'yes',
                'audio-buffer': '0.4',
              }
            : const <String, String>{
                'cache': 'yes',
                'cache-secs': '10',
                'demuxer-seekable-cache': 'no',
                'demuxer-donate-buffer': 'no',
                'demuxer-max-back-bytes': '100663296',
                'demuxer-max-bytes': '100663296',
                'demuxer-readahead-secs': '10',
                'cache-pause': 'yes',
                'cache-pause-wait': '4',
                'cache-pause-initial': 'yes',
                'audio-buffer': '0.6',
              },
      );
      properties['demuxer-lavf-o'] = _buildLavfOptionString({
        if (inlinesStableSplitEdgeHls || prefersStableMasterEdgeHls)
          'protocol_whitelist': 'file,crypto,data,http,https,tcp,tls',
        'live_start_index': '-1',
        'seg_max_retry': '3',
        'http_persistent': '1',
        'http_multiple': '0',
      });
      // Cap avformat_find_stream_info() at 3 seconds.
      // IMPORTANT: demuxer-lavf-analyzeduration unit is SECONDS (not µs).
      // Passing 3000000 (µs equivalent) is out-of-range and triggers a
      // player error which causes a black-screen / restart loop. Use 3.
      properties['demuxer-lavf-analyzeduration'] = '3';
      // demuxer-lavf-probesize unit is bytes; 500000 = 500 KB, which is fine.
      properties['demuxer-lavf-probesize'] = '500000';
      // Use audio clock as the synchronisation reference for split LL-HLS.
      // Without this, PTS discontinuities between the separate video and
      // audio chunklists cause repeated `Invalid audio PTS` / underrun
      // / `Audio/Video desynchronisation` events.
      properties['video-sync'] = 'audio';
    } else {
      properties.addAll(const <String, String>{
        'cache': 'yes',
        'cache-secs': '3',
        'demuxer-seekable-cache': 'no',
        'demuxer-donate-buffer': 'no',
        'demuxer-max-back-bytes': '16777216',
        'demuxer-max-bytes': '16777216',
        'demuxer-readahead-secs': '3',
        'cache-pause': 'no',
        'cache-pause-wait': '1',
        'cache-pause-initial': 'no',
      });
      properties['demuxer-lavf-o'] =
          'live_start_index=-1,seg_max_retry=6,http_persistent=1,http_multiple=1';
    }
  } else if (prefersYoutubeLocalizedHlsMaster) {
    properties.addAll(const <String, String>{
      'cache': 'yes',
      'cache-secs': '6',
      'demuxer-seekable-cache': 'no',
      'demuxer-donate-buffer': 'no',
      'demuxer-max-back-bytes': '50331648',
      'demuxer-max-bytes': '50331648',
      'demuxer-readahead-secs': '6',
      'cache-pause': 'yes',
      'cache-pause-wait': '2',
      'cache-pause-initial': 'yes',
      'audio-buffer': '0.4',
    });
    properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
      'protocol_whitelist': 'file,crypto,data,http,https,tcp,tls',
      'live_start_index': '-1',
      'seg_max_retry': '3',
      'http_persistent': '1',
      'http_multiple': '0',
    });
    properties['demuxer-lavf-analyzeduration'] = '3';
    properties['demuxer-lavf-probesize'] = '500000';
  } else if (prefersLoopbackStableBuffer) {
    // Android baseline for StripchatLlHlsProxy (shared cache numbers).
    // Desktop-only deltas for AES LL-HLS + proxy tax:
    // - thicker multi-second readahead / demuxer caps (AES + short segments)
    // - no cache-pause-initial (libmpv stall)
    // - video-sync=audio + lavf live edge opts (reduce A/V thrash)
    properties.addAll(const <String, String>{
      'cache': 'yes',
      'cache-secs': '8',
      'demuxer-seekable-cache': 'no',
      'demuxer-donate-buffer': 'no',
      'demuxer-max-back-bytes': '67108864',
      'demuxer-max-bytes': '67108864',
      'demuxer-readahead-secs': '8',
      'cache-pause': 'yes',
      'cache-pause-wait': '2',
      'cache-pause-initial': 'yes',
      'audio-buffer': '0.4',
    });
    if (!isAndroid) {
      // Desktop AES LL-HLS (Stripchat): proxy + mouflon decrypt is the bottleneck.
      // Glamorous retest 15:43: publishedMedia=8 still mid-play buffering —
      // keep thick readahead, but resume faster after underrun and allow the
      // demuxer to pull multiple proxy assets in parallel.
      // 154803: Source mid rebuf with thick playlist — give demuxer more runway
      // and more parallel local-proxy pulls without demoting quality.
      properties['cache-secs'] = '40';
      properties['demuxer-max-back-bytes'] = '268435456';
      properties['demuxer-max-bytes'] = '268435456';
      properties['demuxer-readahead-secs'] = '40';
      properties['cache-pause'] = 'yes';
      // Brief pause absorbs proxy AES lag without long freezes.
      properties['cache-pause-wait'] = '3';
      // Still pause at open so first frames are not empty, but do not over-wait.
      properties['cache-pause-initial'] = 'yes';
      properties['audio-buffer'] = '2.0';
      // Prefer display-tempo on native VO so late segments do not yank A/V with
      // the audio clock as hard (less "hitchy" feel than video-sync=audio).
      properties['video-sync'] = 'display-tempo';
      properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
        'live_start_index': '-4',
        'seg_max_retry': '16',
        'http_persistent': '1',
        // Parallel segment GETs into local proxy (catch-up after underrun).
        'http_multiple': '1',
      });
      properties['demuxer-lavf-analyzeduration'] = '2';
      properties['demuxer-lavf-probesize'] = '500000';
    } else {
      // Android SC loopback: middle band (~48MB / 16s) — below desktop 256MB
      // PSS blow-up, above prior 32MB/10s underrun floor.
      properties['cache-secs'] = '16';
      properties['demuxer-readahead-secs'] = '16';
      properties['demuxer-max-back-bytes'] = '50331648';
      properties['demuxer-max-bytes'] = '50331648';
      properties['cache-pause-wait'] = '2';
      properties['audio-buffer'] = '0.6';
      properties['video-sync'] = 'audio';
      properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
        'live_start_index': '-3',
        'seg_max_retry': '10',
        'http_persistent': '1',
        'http_multiple': '1',
      });
      properties['demuxer-lavf-analyzeduration'] = '3';
      properties['demuxer-lavf-probesize'] = '500000';
    }
  } else if (prefersStableBuffer) {
    final isFlv = _looksLikeLiveFlv(source.url);
    properties.addAll(<String, String>{
      'cache': 'yes',
      'cache-secs': isAndroid ? '8' : '10',
      'demuxer-seekable-cache': isFlv ? 'no' : 'yes',
      'demuxer-donate-buffer': 'yes',
      'demuxer-max-back-bytes': isAndroid ? '33554432' : '67108864',
      'demuxer-max-bytes': isAndroid ? '33554432' : '67108864',
      'demuxer-readahead-secs': isAndroid ? '8' : '10',
    });
    // Desktop high-FPS game FLV (60fps 1080p/1440p): display clock + vo drop
    // reduces "game stream feels juddery" under embed texture path.
    if (!isAndroid) {
      properties['video-sync'] = 'display-tempo';
      properties['audio-buffer'] = '0.3';
      properties['cache-pause'] = 'no';
      properties['cache-pause-initial'] = 'no';
    }
  } else if (doubleBufferingEnabled) {
    final isFlv = _looksLikeLiveFlv(source.url);
    properties.addAll(<String, String>{
      'cache': 'yes',
      'cache-secs': '3',
      'demuxer-seekable-cache': isFlv ? 'no' : 'yes',
      'demuxer-donate-buffer': 'yes',
      'demuxer-max-back-bytes': '33554432',
      'demuxer-max-bytes': '33554432',
      'demuxer-readahead-secs': '3',
    });
  } else {
    // Ordinary live streams: low-latency demuxer posture.
    properties.addAll(const <String, String>{
      'cache': 'no',
      'cache-secs': '0',
      'demuxer-seekable-cache': 'no',
      'demuxer-donate-buffer': 'no',
      'demuxer-max-back-bytes': '0',
      'demuxer-max-bytes': '16777216',
      'demuxer-readahead-secs': '1',
      'cache-pause': 'no',
      'cache-pause-wait': '1',
      'cache-pause-initial': 'no',
    });
  }
  properties['load-unsafe-playlists'] =
      shouldAllowUnsafePlaylistsForSource(source) ? 'yes' : 'no';
  final normalizedHlsBitrate = source.hlsBitrate?.trim() ?? '';
  if (prefersChaturbateProxyStableBuffer ||
      prefersLocalizedSplitEdgeMaster ||
      prefersStableMasterEdgeHls ||
      prefersYoutubeLocalizedHlsMaster ||
      prefersStripchatLoopbackStableMaster ||
      prefersLoopbackStableBuffer ||
      prefersDesktopStableLive) {
    properties.remove('hls-bitrate');
  } else if (normalizedHlsBitrate.isNotEmpty) {
    properties['hls-bitrate'] = normalizedHlsBitrate;
  } else if (_looksLikeLiveHlsSource(source)) {
    properties['hls-bitrate'] = 'max';
  }
  if (shouldUseAudioFilesPropertyForSource(source)) {
    properties['audio-files'] = source.externalAudio!.url.toString();
  }
  // Final guard: any Android path (phone, tablet, ChromeOS ARC) must stay in
  // the mobile-safe demux/cache band. Linux desktop never sets isAndroid.
  if (isAndroid) {
    applyAndroidMobileLiveBufferBudget(properties);
  }
  return properties;
}

/// Mobile-safe live demux/cache budget for Android-class runtimes.
///
/// Caps demuxer byte budgets to 64MB and cache/readahead to 16s so ChromeOS
/// tablets and phones never inherit desktop 96–256MB profiles, while allowing
/// a middle band (~48MB/16s) for Twitch/YouTube/SC loopback. Call only when
/// [isAndroid] is true; Linux desktop resolution must not use this helper.
@visibleForTesting
void applyAndroidMobileLiveBufferBudget(Map<String, String> properties) {
  const maxDemuxerBytes = 64 * 1024 * 1024; // 67108864
  const maxCacheSecs = 16;
  for (final key in const <String>[
    'demuxer-max-bytes',
    'demuxer-max-back-bytes',
  ]) {
    final raw = properties[key];
    if (raw == null) {
      continue;
    }
    final value = int.tryParse(raw);
    if (value != null && value > maxDemuxerBytes) {
      properties[key] = '$maxDemuxerBytes';
    }
  }
  for (final key in const <String>['cache-secs', 'demuxer-readahead-secs']) {
    final raw = properties[key];
    if (raw == null) {
      continue;
    }
    final value = int.tryParse(raw);
    if (value != null && value > maxCacheSecs) {
      properties[key] = '$maxCacheSecs';
    }
  }
}

String _buildLavfOptionString(Map<String, String> options) {
  return options.entries
      .map((entry) => '${entry.key}=${_quoteLavfOptionValue(entry.value)}')
      .join(',');
}

String _quoteLavfOptionValue(String value) {
  if (!value.contains(',')) {
    return value;
  }
  return '[${value.replaceAll(']', r'\]')}]';
}

/// Desktop VO values that open a separate window (not embeddable by media_kit).
const Set<String> kDesktopWindowOpeningVos = <String>{
  'gpu',
  'gpu-next',
  'sdl',
  'vaapi',
  'dmabuf-wayland',
  'direct3d',
  'xv',
  'x11',
  'wayland',
};

/// Default VO when the user opts into the independent native mpv window path.
const String kDefaultExternalNativeVideoOutputDriver = 'gpu-next';

bool isDesktopWindowOpeningMpvVo(String videoOutputDriver) {
  return kDesktopWindowOpeningVos.contains(
    videoOutputDriver.trim().toLowerCase(),
  );
}

MpvRuntimeConfiguration resolveMpvRuntimeConfiguration({
  required bool enableHardwareAcceleration,
  required bool compatMode,
  required bool doubleBufferingEnabled,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool logEnabled,
  String audioOutputDriver = 'auto',
  bool isAndroid = false,
  bool allowExternalNativeWindow = false,
  /// When non-null, force the ARC decode ladder tier (tests / runtime escalate).
  /// Production MpvPlayer passes the active tier when [looksLikeArcChromeOsRuntime].
  ArcMpvDecodeTier? arcDecodeTier,
}) {
  // ChromeOS ARC: production default is mediacodec-copy (HW decode, any
  // resolution, no zero-copy Surface size guess). software = fallback only.
  // Phone firmwares never match R###-… (path stays null).
  final activeArcTier = arcDecodeTier;
  var effectiveEnableHardwareAcceleration = enableHardwareAcceleration;
  var effectiveCompatMode = compatMode;
  var effectiveCustomOutputEnabled = customOutputEnabled;
  var effectiveHardwareDecoder = hardwareDecoder;
  var effectiveVideoOutputDriver = videoOutputDriver;
  if (activeArcTier != null) {
    effectiveCompatMode = false;
    switch (activeArcTier) {
      case ArcMpvDecodeTier.zeroCopy:
        effectiveEnableHardwareAcceleration = true;
        effectiveCustomOutputEnabled = true;
        effectiveVideoOutputDriver = 'mediacodec_embed';
        effectiveHardwareDecoder = 'mediacodec';
      case ArcMpvDecodeTier.mediaCodecCopy:
        effectiveEnableHardwareAcceleration = true;
        effectiveCustomOutputEnabled = true;
        effectiveVideoOutputDriver = 'gpu';
        effectiveHardwareDecoder = 'mediacodec-copy';
      case ArcMpvDecodeTier.software:
        effectiveEnableHardwareAcceleration = false;
        effectiveCustomOutputEnabled = false;
        effectiveHardwareDecoder = 'no';
    }
  }

  var sanitizedVideoOutputDriver = effectiveVideoOutputDriver.trim().isEmpty
      ? MpvPlayer._fallbackVideoOutputDriver
      : effectiveVideoOutputDriver.trim();
  final wantsExternalNativeWindow = !isAndroid && allowExternalNativeWindow;
  // Opt-in A/B path: keep (or promote to) a real window-opening VO and skip
  // Flutter texture embed. Default remains embed-safe libmpv.
  if (wantsExternalNativeWindow) {
    if (!isDesktopWindowOpeningMpvVo(sanitizedVideoOutputDriver)) {
      sanitizedVideoOutputDriver = kDefaultExternalNativeVideoOutputDriver;
    }
  } else if (!isAndroid &&
      effectiveCustomOutputEnabled &&
      isDesktopWindowOpeningMpvVo(sanitizedVideoOutputDriver)) {
    // Desktop + custom output without external opt-in: never pass
    // window-opening VOs — orphan external windows cannot be closed cleanly.
    sanitizedVideoOutputDriver = 'libmpv';
  }
  if (activeArcTier == ArcMpvDecodeTier.zeroCopy) {
    sanitizedVideoOutputDriver = 'mediacodec_embed';
  } else if (activeArcTier == ArcMpvDecodeTier.mediaCodecCopy) {
    sanitizedVideoOutputDriver = 'gpu';
  }
  var sanitizedHardwareDecoder = effectiveHardwareDecoder.trim().isEmpty
      ? (isAndroid
            ? MpvPlayer._fallbackHardwareDecoder
            : MpvPlayer._fallbackHardwareDecoderDesktop)
      : effectiveHardwareDecoder.trim();
  // Desktop libmpv embed: auto-safe rarely activates VAAPI/NVDEC; auto-copy is
  // the reliable "hardware decode is actually used" default for all providers.
  if (!isAndroid &&
      (sanitizedHardwareDecoder == 'auto-safe' ||
          sanitizedHardwareDecoder == 'auto')) {
    sanitizedHardwareDecoder = MpvPlayer._fallbackHardwareDecoderDesktop;
  }
  if (activeArcTier == ArcMpvDecodeTier.zeroCopy) {
    sanitizedHardwareDecoder = 'mediacodec';
  } else if (activeArcTier == ArcMpvDecodeTier.mediaCodecCopy) {
    sanitizedHardwareDecoder = 'mediacodec-copy';
  } else if (activeArcTier == ArcMpvDecodeTier.software) {
    sanitizedHardwareDecoder = 'no';
  }
  final sanitizedAudioOutputDriver = audioOutputDriver.trim().isEmpty
      ? 'auto'
      : audioOutputDriver.trim();
  final usesExternalNativeWindow =
      wantsExternalNativeWindow &&
      isDesktopWindowOpeningMpvVo(sanitizedVideoOutputDriver);
  final attachAfterVideoParameters = _resolveAndroidAttachSurfaceTiming(
    compatMode: effectiveCompatMode,
    customOutputEnabled: effectiveCustomOutputEnabled,
    videoOutputDriver: sanitizedVideoOutputDriver,
    enableHardwareAcceleration: effectiveEnableHardwareAcceleration,
    hardwareDecoder: sanitizedHardwareDecoder,
  );
  // External window mode still records the intended vo/hwdec for diagnostics,
  // but MpvPlayer must not construct VideoController (media_kit render path
  // forces libmpv and fights the independent VO).
  final controllerConfiguration = usesExternalNativeWindow
      ? VideoControllerConfiguration(
          vo: sanitizedVideoOutputDriver,
          hwdec: effectiveEnableHardwareAcceleration
              ? sanitizedHardwareDecoder
              : 'no',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        )
      : effectiveCustomOutputEnabled
      ? VideoControllerConfiguration(
          vo: sanitizedVideoOutputDriver,
          hwdec: effectiveEnableHardwareAcceleration
              ? sanitizedHardwareDecoder
              : 'no',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        )
      : effectiveCompatMode
      ? VideoControllerConfiguration(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        )
      : VideoControllerConfiguration(
          enableHardwareAcceleration: effectiveEnableHardwareAcceleration,
          hwdec: effectiveEnableHardwareAcceleration
              ? sanitizedHardwareDecoder
              : 'no',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        );
  // Live default: disable demuxer playback cache unless the
  // user opts into double buffering. Site-specific source profiles may still
  // widen cache for LL-HLS / proxy paths when binding a source.
  final platformProperties = <String, String>{
    ...doubleBufferingEnabled
        ? const <String, String>{
            'cache': 'yes',
            'cache-secs': '3',
            'demuxer-seekable-cache': 'yes',
            'demuxer-donate-buffer': 'yes',
            'demuxer-max-back-bytes': '33554432',
            'demuxer-max-bytes': '33554432',
            'demuxer-readahead-secs': '3',
            'cache-on-disk': 'no',
          }
        : const <String, String>{
            'cache': 'no',
            'cache-secs': '0',
            'demuxer-seekable-cache': 'no',
            'demuxer-donate-buffer': 'no',
            'demuxer-max-back-bytes': '0',
            'demuxer-max-bytes': '16777216',
            'demuxer-readahead-secs': '1',
            'cache-on-disk': 'no',
            'cache-pause': 'no',
            'cache-pause-wait': '1',
            'cache-pause-initial': 'no',
          },
    if (usesExternalNativeWindow) ...<String, String>{
      'vo': sanitizedVideoOutputDriver,
      'hwdec': effectiveEnableHardwareAcceleration
          ? sanitizedHardwareDecoder
          : 'no',
      // Do NOT force video-sync here — foreign HLS profiles set display-tempo
      // or audio per-source. A global audio clock overrode Twitch/SC profiles
      // and amplified underrun hitching on the independent VO window.
    },
    if ((effectiveCustomOutputEnabled || usesExternalNativeWindow) &&
        sanitizedAudioOutputDriver.isNotEmpty &&
        sanitizedAudioOutputDriver != 'auto')
      'ao': sanitizedAudioOutputDriver,
  };
  return MpvRuntimeConfiguration(
    controllerConfiguration: controllerConfiguration,
    logLevel: logEnabled ? mk.MPVLogLevel.debug : mk.MPVLogLevel.error,
    platformProperties: platformProperties,
    androidOutputFallbackReason: switch (activeArcTier) {
      ArcMpvDecodeTier.zeroCopy => 'arc-chromeos-zerocopy-surface',
      ArcMpvDecodeTier.mediaCodecCopy => 'arc-chromeos-mediacodec-copy',
      ArcMpvDecodeTier.software => 'arc-chromeos-software-decode',
      null => null,
    },
    usesExternalNativeWindow: usesExternalNativeWindow,
    externalNativeVideoOutputDriver:
        usesExternalNativeWindow ? sanitizedVideoOutputDriver : null,
  );
}

bool shouldFallbackToSafeAndroidVideoOutput({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
}) {
  // Keep this hook for future targeted fallbacks, but do not override the
  // user's explicit Android MediaCodec path. Reference projects keep
  // `mediacodec` meaningful by preserving the runtime hwdec selection and
  // letting media_kit_video's Android controller manage `vo/wid/vid`.
  return false;
}

bool? _resolveAndroidAttachSurfaceTiming({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required bool enableHardwareAcceleration,
  required String hardwareDecoder,
}) {
  if (shouldFallbackToSafeAndroidVideoOutput(
    compatMode: compatMode,
    customOutputEnabled: customOutputEnabled,
    videoOutputDriver: videoOutputDriver,
  )) {
    return null;
  }
  if (!usesEmbeddedAndroidMediaCodecOutput(
    compatMode: compatMode,
    customOutputEnabled: customOutputEnabled,
    videoOutputDriver: videoOutputDriver,
    enableHardwareAcceleration: enableHardwareAcceleration,
    hardwareDecoder: hardwareDecoder,
  )) {
    return null;
  }
  // Fresh opens now wait for the embedded view + platform + surface handle
  // before calling `open()`. Forcing `attachAfterVideoParams=true` makes that
  // surface handle unavailable until *after* demux/decoder init, which matches
  // the latest domestic-platform regression: deterministic `surface-ready
  // timeout`, 3-5s black screen, then `Could not create device` and software
  // fallback. Keep the Android surface attached up-front for embedded
  // MediaCodec output so `open()` starts with a real target surface.
  return false;
}

bool shouldAwaitAndroidEmbeddedSurfaceBeforeOpen({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool isAndroid,
}) {
  final effectiveVideoOutput = compatMode
      ? 'mediacodec_embed'
      : customOutputEnabled
      ? videoOutputDriver
      : '';
  return shouldWarmAndroidMediaCodecOpenPath(
    videoOutputDriver: effectiveVideoOutput,
    hardwareDecoder: hardwareDecoder,
    isAndroid: isAndroid,
  );
}
