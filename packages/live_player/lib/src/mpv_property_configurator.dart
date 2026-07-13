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
}

class MpvRuntimeConfiguration {
  const MpvRuntimeConfiguration({
    required this.controllerConfiguration,
    required this.logLevel,
    required this.platformProperties,
    this.androidOutputFallbackReason,
  });

  final VideoControllerConfiguration controllerConfiguration;
  final mk.MPVLogLevel logLevel;
  final Map<String, String> platformProperties;
  final String? androidOutputFallbackReason;
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
  if (source.bufferProfile ==
          PlaybackBufferProfile.chaturbateLlHlsProxyStable &&
      (normalized.contains('found duplicated moov atom') ||
          normalized.contains('audio device underrun'))) {
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
    properties['demuxer-lavf-o'] = _buildLavfOptionString(const {
      'live_start_index': '-1',
      'seg_max_retry': '3',
      'http_persistent': '1',
      'http_multiple': '0',
    });
    if (prefersChaturbateDirectStableFallback) {
      properties['demuxer-lavf-analyzeduration'] = '5';
      properties['demuxer-lavf-probesize'] = '5000000';
      properties['hwdec'] = 'auto-safe';
    } else {
      properties['demuxer-lavf-analyzeduration'] = '2';
      properties['demuxer-lavf-probesize'] = '500000';
    }
    properties['video-sync'] = 'audio';
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
    properties['demuxer-lavf-analyzeduration'] = '3';
    properties['demuxer-lavf-probesize'] = '500000';
    properties['video-sync'] = 'display-tempo';
  } else if (prefersStableBuffer) {
    final isFlv = _looksLikeLiveFlv(source.url);
    properties.addAll(<String, String>{
      'cache': 'yes',
      'cache-secs': '10',
      'demuxer-seekable-cache': isFlv ? 'no' : 'yes',
      'demuxer-donate-buffer': 'yes',
      'demuxer-max-back-bytes': '67108864',
      'demuxer-max-bytes': '67108864',
      'demuxer-readahead-secs': '10',
    });
  } else if (prefersLoopbackStableBuffer) {
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
      prefersLoopbackStableBuffer) {
    properties.remove('hls-bitrate');
  } else if (normalizedHlsBitrate.isNotEmpty) {
    properties['hls-bitrate'] = normalizedHlsBitrate;
  } else if (_looksLikeLiveHlsSource(source)) {
    properties['hls-bitrate'] = 'max';
  }
  if (shouldUseAudioFilesPropertyForSource(source)) {
    properties['audio-files'] = source.externalAudio!.url.toString();
  }
  return properties;
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

MpvRuntimeConfiguration resolveMpvRuntimeConfiguration({
  required bool enableHardwareAcceleration,
  required bool compatMode,
  required bool doubleBufferingEnabled,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool logEnabled,
  String audioOutputDriver = 'auto',
}) {
  final sanitizedVideoOutputDriver = videoOutputDriver.trim().isEmpty
      ? MpvPlayer._fallbackVideoOutputDriver
      : videoOutputDriver.trim();
  final sanitizedHardwareDecoder = hardwareDecoder.trim().isEmpty
      ? MpvPlayer._fallbackHardwareDecoder
      : hardwareDecoder.trim();
  final sanitizedAudioOutputDriver = audioOutputDriver.trim().isEmpty
      ? 'auto'
      : audioOutputDriver.trim();
  final attachAfterVideoParameters = _resolveAndroidAttachSurfaceTiming(
    compatMode: compatMode,
    customOutputEnabled: customOutputEnabled,
    videoOutputDriver: sanitizedVideoOutputDriver,
    enableHardwareAcceleration: enableHardwareAcceleration,
    hardwareDecoder: sanitizedHardwareDecoder,
  );
  final controllerConfiguration = customOutputEnabled
      ? VideoControllerConfiguration(
          vo: sanitizedVideoOutputDriver,
          hwdec: enableHardwareAcceleration ? sanitizedHardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        )
      : compatMode
      ? VideoControllerConfiguration(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          androidAttachSurfaceAfterVideoParameters: attachAfterVideoParameters,
        )
      : VideoControllerConfiguration(
          enableHardwareAcceleration: enableHardwareAcceleration,
          hwdec: enableHardwareAcceleration ? sanitizedHardwareDecoder : 'no',
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
    if (customOutputEnabled &&
        sanitizedAudioOutputDriver.isNotEmpty &&
        sanitizedAudioOutputDriver != 'auto')
      'ao': sanitizedAudioOutputDriver,
  };
  return MpvRuntimeConfiguration(
    controllerConfiguration: controllerConfiguration,
    logLevel: logEnabled ? mk.MPVLogLevel.debug : mk.MPVLogLevel.error,
    platformProperties: platformProperties,
    androidOutputFallbackReason: null,
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
