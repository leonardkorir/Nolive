import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import 'base_player.dart';
import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';

part 'mpv_android_surface_manager.dart';
part 'mpv_hls_manifest_service.dart';
part 'mpv_player_runtime_bindings.dart';
part 'mpv_property_configurator.dart';

const String _mediaKitNativeReferenceHolderPrefix =
    'com.alexmercerind.media_kit.NativeReferenceHolder.';
const String kMpvAndroidSurfaceTimeoutError =
    'MPV Android surface initialization timed out';
const String kMpvNoMediaTrackStartupError =
    'MPV did not expose audio/video tracks after startup';

/// ChromeOS ARC decode options.
///
/// Product rules (user-confirmed):
/// - Prefer **hardware decode** on Chromebook when it can work.
/// - **Any resolution** must play (720 / 1080 / 2K / …).
/// - Soft decode was already stable; it is a **fallback**, not a silent default.
///
/// geralt ARCVM evidence:
/// - [zeroCopy] needs Surface size == stream size; guessing size breaks other
///   resolutions (1080 failed when we forced a 2K prime).
/// - [mediaCodecCopy] hard decode without zero-copy Surface bind; works across
///   resolutions (brief black then play). Default production tier.
/// - [software] last resort if copy cannot produce A/V.
enum ArcMpvDecodeTier {
  /// Zero-copy Surface. Experimental only — not the ARC default.
  zeroCopy,

  /// Hard decode + copy into gpu VO — ARC **default** (resolution-agnostic).
  mediaCodecCopy,

  /// Software decode — fallback only when hard-copy fails.
  software,
}

/// Escalate toward safer tiers only. Default start is [mediaCodecCopy];
/// zerocopy is not on the automatic ladder (resolution/Surface-size traps).
ArcMpvDecodeTier? nextArcMpvDecodeTier(ArcMpvDecodeTier current) {
  return switch (current) {
    ArcMpvDecodeTier.zeroCopy => ArcMpvDecodeTier.mediaCodecCopy,
    ArcMpvDecodeTier.mediaCodecCopy => ArcMpvDecodeTier.software,
    ArcMpvDecodeTier.software => null,
  };
}

String arcMpvDecodeTierLabel(ArcMpvDecodeTier tier) {
  return switch (tier) {
    ArcMpvDecodeTier.zeroCopy => 'zerocopy',
    ArcMpvDecodeTier.mediaCodecCopy => 'mediacodec-copy',
    ArcMpvDecodeTier.software => 'software',
  };
}

/// Result of waiting for startup A/V after play (ARC ladder).
enum ArcStartupMediaPollOutcome {
  /// Width/params/buffer/position signal present — treat as playable.
  gotSignal,

  /// Player reported error before a media signal — demote tier, do not "succeed".
  failed,

  /// Wait budget elapsed with neither signal nor terminal error.
  timedOut,

  /// Source changed / player closed mid-wait — stop escalating.
  aborted,
}

Future<void>? _pendingAndroidDebugMediaKitReferenceCleanup;

@visibleForTesting
bool hasMpvStartupMediaSignal({
  required PlayerState state,
  required PlayerDiagnostics diagnostics,
}) {
  return (diagnostics.width ?? 0) > 0 ||
      (diagnostics.height ?? 0) > 0 ||
      diagnostics.videoParams.isNotEmpty ||
      diagnostics.audioParams.isNotEmpty ||
      state.position > Duration.zero ||
      state.buffered > Duration.zero ||
      diagnostics.buffered > Duration.zero;
}

@visibleForTesting
Duration resolveMpvStartupMediaSignalTimeout(PlaybackSource source) {
  // Twitch ad-guard Auto: multi-variant probe + first segment can exceed 10s
  // on phone nets (logs: 160→360→480 climb without tracks).
  final path = source.url.path.toLowerCase();
  if (path.contains('twitch-ad-guard') ||
      source.bufferProfile == PlaybackBufferProfile.desktopStableLive) {
    return MpvPlayer._androidStartupForeignLiveMediaSignalTimeout;
  }
  if (source.externalAudio != null ||
      source.masterPlaylistContent?.trim().isNotEmpty == true ||
      source.masterPlaylistUrl != null ||
      _looksLikeLiveHlsSource(source) ||
      source.url.host.contains('googlevideo.com')) {
    return MpvPlayer._androidStartupBufferedMediaSignalTimeout;
  }
  if (source.bufferProfile != PlaybackBufferProfile.defaultLowLatency) {
    return MpvPlayer._androidStartupBufferedMediaSignalTimeout;
  }
  return MpvPlayer._androidStartupMediaSignalTimeout;
}

/// Delays after `player.open` for sampling `hwdec-current` / logging
/// `hwdec-active`. Immediate open often still shows `current=-`.
@visibleForTesting
List<Duration> resolveMpvHwdecActiveSampleDelays() {
  return List<Duration>.unmodifiable(MpvPlayer._hwdecActiveSampleDelays);
}

/// First sample delay (compat for single-delay callers/tests).
@visibleForTesting
Duration resolveMpvHwdecActiveSampleDelay() {
  return MpvPlayer._hwdecActiveSampleDelays.first;
}

@visibleForTesting
bool looksLikeActiveHwdecCurrent(String hwdecCurrent) {
  return _looksLikeActiveHwdecCurrent(hwdecCurrent);
}

bool _looksLikeActiveHwdecCurrent(String hwdecCurrent) {
  final normalized = hwdecCurrent.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized == '-' ||
      normalized == 'no' ||
      normalized == 'none') {
    return false;
  }
  return true;
}

@visibleForTesting
bool isMediaKitNativeReferenceHolderPath(String filePath) {
  final name = filePath.split(Platform.pathSeparator).last;
  return name.startsWith(_mediaKitNativeReferenceHolderPrefix);
}

@visibleForTesting
Future<int> deleteMediaKitNativeReferenceHolderFilesInDirectory(
  Directory directory,
) async {
  if (!await directory.exists()) {
    return 0;
  }
  var deleted = 0;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !isMediaKitNativeReferenceHolderPath(entity.path)) {
      continue;
    }
    try {
      if (await entity.exists()) {
        await entity.delete();
        deleted += 1;
      }
    } catch (_) {
      // Best-effort cleanup for debug-only media_kit reference holder files.
    }
  }
  return deleted;
}

class MpvPlayer implements BasePlayer {
  MpvPlayer({
    this.enableHardwareAcceleration = true,
    this.compatMode = false,
    this.doubleBufferingEnabled = false,
    this.customOutputEnabled = false,
    this.videoOutputDriver = 'gpu-next',
    this.audioOutputDriver = 'auto',
    this.hardwareDecoder = 'auto-safe',
    this.logEnabled = false,
    this.allowExternalNativeWindow = false,
    this.eventLogger,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  static const Duration _progressBroadcastStep = Duration(seconds: 1);
  static const Duration _bufferBroadcastStep = Duration(seconds: 1);
  static const Duration _disposeStopSettleDelay = Duration(seconds: 1);
  static const Duration _sourceSwitchStopSettleDelay = Duration(seconds: 1);
  // Fresh open only needs a short settle; 150ms was pure dead wait after
  // loadRoom in device logs (loadRoom done → setSource delayed by barrier).
  static const Duration _initialAndroidOpenSettleDelay = Duration(
    milliseconds: 48,
  );
  static const Duration _androidInitialEmbeddedViewMountReadyTimeout = Duration(
    milliseconds: 250,
  );
  static const Duration _androidInitialEmbeddedPlatformReadyTimeout = Duration(
    milliseconds: 250,
  );
  static const Duration _androidInitialEmbeddedSurfaceReadyBudget = Duration(
    milliseconds: 800,
  );
  static const Duration _androidInitialEmbeddedSurfaceReadyPollInterval =
      Duration(milliseconds: 150);
  static const Duration _androidInitialEmbeddedSurfaceAttachStabilizeTimeout =
      Duration(milliseconds: 220);
  static const Duration _androidEmbeddedViewMountReadyTimeout = Duration(
    milliseconds: 250,
  );
  static const Duration _androidEmbeddedPlatformReadyTimeout = Duration(
    milliseconds: 250,
  );
  static const Duration _androidEmbeddedSurfaceReadyBudget = Duration(
    milliseconds: 350,
  );
  static const Duration _androidEmbeddedSurfaceReadyPollInterval = Duration(
    milliseconds: 150,
  );
  static const Duration _androidEmbeddedSurfaceAttachStabilizeTimeout =
      Duration(milliseconds: 220);
  static const Duration _androidReopenFreshSurfaceWaitBudget = Duration(
    milliseconds: 800,
  );
  static const Duration _androidInitialEmbeddedPlaySurfaceReadyTimeout =
      Duration(milliseconds: 1000);
  static const Duration _androidInitialEmbeddedPlaySurfaceFallbackTimeout =
      Duration(milliseconds: 500);
  static const Duration _androidEmbeddedHardwareDecoderReadyTimeout = Duration(
    milliseconds: 900,
  );
  static const Duration _androidStartupMediaSignalTimeout = Duration(
    milliseconds: 3500,
  );
  static const Duration _androidStartupBufferedMediaSignalTimeout = Duration(
    seconds: 10,
  );

  /// Phone Twitch/YouTube (desktopStableLive / ad-guard): allow proxy probe climb.
  static const Duration _androidStartupForeignLiveMediaSignalTimeout = Duration(
    seconds: 22,
  );

  /// Post-open delays before reading `hwdec-current`. Immediate open often
  /// still reports `current=-`; HLS/proxy rooms need multi-second samples.
  static const List<Duration> _hwdecActiveSampleDelays = <Duration>[
    Duration(milliseconds: 800),
    Duration(milliseconds: 2500),
    Duration(milliseconds: 6000),
  ];
  static const Duration _androidStartupMediaSignalPollInterval = Duration(
    milliseconds: 100,
  );
  static const Duration _androidMediaCodecReinitClassificationThreshold =
      Duration(milliseconds: 50);
  static const String _fallbackVideoOutputDriver = 'gpu-next';
  static const String _fallbackHardwareDecoder = 'auto-safe';

  /// Desktop/libmpv embed default when caller leaves decoder empty.
  static const String _fallbackHardwareDecoderDesktop = 'auto-copy';

  static bool _mediaKitInitialized = false;

  final bool enableHardwareAcceleration;
  final bool compatMode;
  final bool doubleBufferingEnabled;
  final bool customOutputEnabled;
  final String videoOutputDriver;
  final String audioOutputDriver;
  final String hardwareDecoder;
  final bool logEnabled;

  /// Desktop opt-in: open a real mpv VO window (gpu-next/gpu/...) instead of
  /// Flutter texture embed. Used to validate native playback smoothness.
  final bool allowExternalNativeWindow;
  final void Function(String message)? eventLogger;
  final bool isAndroid;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Queue<String> _recentLogs = ListQueue<String>();
  final ValueNotifier<bool> _embeddedViewMounted = ValueNotifier<bool>(false);
  final ValueNotifier<VideoController?> _controllerNotifier =
      ValueNotifier<VideoController?>(null);

  mk.Player? _player;
  VideoController? _controller;
  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);
  PlayerDiagnostics _currentDiagnostics = const PlayerDiagnostics(
    backend: PlayerBackend.mpv,
  );
  bool _initialized = false;
  bool _disposing = false;
  bool _disposed = false;
  bool _captureScreenshotInFlight = false;
  Duration _lastBroadcastPosition = Duration.zero;
  Duration _lastBroadcastBuffered = Duration.zero;
  Future<void> _operationChain = Future<void>.value();
  File? _activeSyntheticPlaylistFile;
  MpvRuntimeConfiguration? _runtimeConfiguration;
  int _androidEmbeddedPlayGateGeneration = 0;
  AndroidEmbeddedPlayGate? _pendingAndroidEmbeddedPlayGate;
  bool _emittedMediaCodecDeviceFailureForSource = false;
  DateTime? _lastMpvOpeningDoneAt;

  DateTime? _lastMediaCodecHardwareDecoderReadyAt;
  Completer<DateTime>? _pendingMediaCodecHardwareDecoderReadyCompleter;

  /// Active ARC decode tier. Default hard-copy (user wants HW decode; any
  /// resolution). Escalate to software only on failure. Phone never uses this.
  ArcMpvDecodeTier _arcDecodeTier = ArcMpvDecodeTier.mediaCodecCopy;

  /// Last ARC surface prime (for mismatch detect vs videoParams).
  ({int width, int height})? _arcLastSurfacePrimeSize;

  bool _arcPreemptiveEscalateInFlight = false;

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnosticsController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => true;

  @override
  Future<void> initialize() async {
    await _runSerialized('initialize', () async {
      await _initializeInternal();
    });
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    await _runSerialized('setSource', () async {
      // ARC: each room retries hard-copy first (not zerocopy, not sticky soft).
      // Soft is only reached via escalate after copy fails for this open.
      if (isAndroid &&
          looksLikeArcChromeOsRuntime() &&
          _arcDecodeTier != ArcMpvDecodeTier.mediaCodecCopy) {
        await _recreateMediaKitBackendForArcTier(
          ArcMpvDecodeTier.mediaCodecCopy,
        );
      } else {
        await _initializeInternal();
      }
      if (_player == null) {
        return;
      }
      await _openSourceUnlocked(source);
    });
  }

  @override
  Future<void> play() async {
    await _runSerialized('play', () async {
      final player = _player;
      if (player == null) {
        return;
      }
      final surfaceReady = await _awaitAndroidEmbeddedPlayGateIfNeeded();
      if (!surfaceReady) {
        return;
      }
      final source = _currentState.source;
      await player.play();
      await _awaitAndroidStartupMediaSignalAfterPlay(source);
      // Do NOT stall-escalate mediacodec-copy on estimated-vf-fps: ARC logs show
      // current=mediacodec-copy + videoParams while fps is empty/0 — demoting
      // recreated the whole player mid-watch and caused extra black/error loops.
      // Zero-copy experimental path may still use size-mismatch preempt only.
    });
  }

  Future<void> _addExternalAudioAfterOpen(
    mk.Player player,
    PlaybackSource source,
  ) async {
    final externalAudio = source.externalAudio;
    if (externalAudio == null) {
      await player.setAudioTrack(mk.AudioTrack.auto());
      return;
    }
    final platform = player.platform;
    if (platform is mk.NativePlayer) {
      await _configureExternalAudioHeaders(platform, externalAudio.headers);
      final title = externalAudio.label?.trim().isNotEmpty == true
          ? externalAudio.label!.trim()
          : 'external audio';
      try {
        await platform.command([
          'audio-add',
          externalAudio.url.toString(),
          'select',
          title,
        ], waitForInitialization: false);
        _logEvent(
          'external audio-add url=${_shortSourceDescriptor(externalAudio.url)} '
          'headers=${externalAudio.headers.keys.join(',')}',
        );
        return;
      } catch (error) {
        _logEvent('external audio-add failed error=$error');
      }
    }
    await player.setAudioTrack(
      mk.AudioTrack.uri(
        externalAudio.url.toString(),
        title: externalAudio.label,
      ),
    );
    _logEvent(
      'external audio-track uri url=${_shortSourceDescriptor(externalAudio.url)}',
    );
  }

  Future<void> _configureExternalAudioHeaders(
    mk.NativePlayer platform,
    Map<String, String> audioHeaders,
  ) async {
    final userAgent = audioHeaders['user-agent'] ?? audioHeaders['User-Agent'];
    if (userAgent != null) {
      try {
        await platform.setProperty('user-agent', userAgent);
      } catch (_) {}
    }
    final referer =
        audioHeaders['referer'] ??
        audioHeaders['Referer'] ??
        audioHeaders['referrer'] ??
        audioHeaders['Referrer'];
    if (referer != null) {
      try {
        await platform.setProperty('referrer', referer);
      } catch (_) {}
    }
    final cookie = audioHeaders['cookie'] ?? audioHeaders['Cookie'];
    if (cookie != null) {
      try {
        await platform.setProperty('cookies', cookie);
      } catch (_) {}
    }
    final customHeaders = audioHeaders.entries
        .where(
          (e) => ![
            'user-agent',
            'referer',
            'referrer',
            'cookie',
          ].contains(e.key.toLowerCase()),
        )
        .map((e) => '${e.key}: ${e.value}')
        .join(',');
    if (customHeaders.isNotEmpty) {
      try {
        await platform.setProperty('http-header-fields', customHeaders);
      } catch (_) {}
    }
  }

  @override
  Future<void> pause() async {
    await _runSerialized('pause', () async {
      final player = _player;
      if (player == null) {
        return;
      }
      await player.pause();
    });
  }

  @override
  Future<void> stop() async {
    await _runSerialized('stop', () async {
      final player = _player;
      if (player == null) {
        return;
      }
      _androidEmbeddedPlayGateGeneration += 1;
      _pendingAndroidEmbeddedPlayGate = null;
      _lastMediaCodecHardwareDecoderReadyAt = null;
      _pendingMediaCodecHardwareDecoderReadyCompleter = null;
      final externalNativeWindow =
          _runtimeConfiguration?.usesExternalNativeWindow == true;
      await player.stop();
      // External gpu-next shares the process X11 Display with WebKitGTK. Parking
      // vo=null is not enough — residual GLX state still races when Twitch /
      // YouTube create a headless webview. Fully destroy the libmpv instance
      // after stop; next setSource re-initializes a clean player.
      if (externalNativeWindow) {
        await _parkExternalNativeWindow(player);
        await _teardownExternalNativeMediaKitPlayer();
      }
      _lastBroadcastPosition = Duration.zero;
      _lastBroadcastBuffered = Duration.zero;
      _emitDiagnostics(_freshDiagnostics(clearRecentLogs: true));
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.ready,
          position: Duration.zero,
          buffered: Duration.zero,
          clearErrorMessage: true,
          clearSource: true,
        ),
      );
      await _deleteSyntheticPlaylistFile(_activeSyntheticPlaylistFile);
      _activeSyntheticPlaylistFile = null;
    });
  }

  @override
  Future<void> setVolume(double value) async {
    await _runSerialized('setVolume', () async {
      final player = _player;
      final normalized = value.clamp(0, 1).toDouble();
      // Skip redundant backend writes (session logs: 100+ setVolume/hour).
      if (player != null &&
          (normalized - _currentState.volume).abs() < 0.0005) {
        return;
      }
      if (player == null) {
        if ((normalized - _currentState.volume).abs() < 0.0005) {
          return;
        }
        _emit(_currentState.copyWith(volume: normalized));
        return;
      }
      await player.setVolume(normalized * 100);
      _emit(_currentState.copyWith(volume: normalized));
    });
  }

  @override
  Future<Uint8List?> captureScreenshot() async {
    return _runSerializedNullable<Uint8List>('captureScreenshot', () async {
      final player = _player;
      if (player == null) {
        return null;
      }
      final controllerConfiguration =
          _runtimeConfiguration?.controllerConfiguration;
      if (shouldBypassNativeMpvScreenshot(
        compatMode: false,
        customOutputEnabled: controllerConfiguration?.vo != null,
        videoOutputDriver: controllerConfiguration?.vo ?? videoOutputDriver,
        hardwareDecoder: controllerConfiguration?.hwdec ?? hardwareDecoder,
        isAndroid: isAndroid,
      )) {
        _logEvent(
          'captureScreenshot skip-native reason=android-surface-output',
        );
        return null;
      }
      try {
        _captureScreenshotInFlight = true;
        try {
          final raw = await player.screenshot(format: 'image/png');
          if (raw != null && raw.isNotEmpty) {
            return raw;
          }
        } catch (_) {
          // Fall through to the native temp-file command on platforms where
          // screenshot-raw returns an empty payload after software fallback.
        }
        try {
          return await _captureScreenshotToTempFile(player);
        } catch (_) {
          return null;
        }
      } finally {
        _captureScreenshotInFlight = false;
      }
    });
  }

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    if (_disposing || _disposed) {
      return SizedBox.expand(key: key);
    }
    final externalVo =
        _runtimeConfiguration?.externalNativeVideoOutputDriver ??
        (_runtimeConfiguration?.usesExternalNativeWindow == true
            ? kDefaultExternalNativeVideoOutputDriver
            : null);
    if (_runtimeConfiguration?.usesExternalNativeWindow == true) {
      return _MpvExternalNativeWindowPlaceholder(
        key: key,
        videoOutputDriver:
            externalVo ?? kDefaultExternalNativeVideoOutputDriver,
      );
    }
    return ValueListenableBuilder<VideoController?>(
      key: key,
      valueListenable: _controllerNotifier,
      builder: (context, controller, _) {
        if (_disposing || _disposed || controller == null) {
          return const SizedBox.expand();
        }
        return _MpvEmbeddedViewHost(
          mountedListenable: _embeddedViewMounted,
          child: Video(
            controller: controller,
            aspectRatio: aspectRatio,
            fit: fit,
            pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
            resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
            controls: NoVideoControls,
          ),
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposing || _disposed) {
      return;
    }
    _disposing = true;
    await _runSerialized('dispose', () async {
      final player = _player;
      if (player != null) {
        await _stopPlayerBeforeDispose(player);
      }
      _player = null;
      _controller = null;
      _controllerNotifier.value = null;
      _runtimeConfiguration = null;
      _androidEmbeddedPlayGateGeneration += 1;
      _pendingAndroidEmbeddedPlayGate = null;
      _initialized = false;
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      await player?.dispose();
      _disposed = true;
      await _deleteSyntheticPlaylistFile(_activeSyntheticPlaylistFile);
      _activeSyntheticPlaylistFile = null;
      await _stateController.close();
      await _diagnosticsController.close();
    }, allowWhileClosing: true);
  }

  Future<void> _stopPlayerBeforeDispose(mk.Player player) async {
    final state = _currentState;
    final shouldStop =
        state.source != null ||
        switch (state.status) {
          PlaybackStatus.buffering ||
          PlaybackStatus.playing ||
          PlaybackStatus.paused ||
          PlaybackStatus.completed ||
          PlaybackStatus.error => true,
          _ => false,
        };
    final externalNativeWindow =
        _runtimeConfiguration?.usesExternalNativeWindow == true;
    if (!shouldStop && !externalNativeWindow) {
      return;
    }
    try {
      _logEvent('dispose graceful stop start');
      if (shouldStop) {
        await player.stop();
      }
      if (externalNativeWindow) {
        await _parkExternalNativeWindow(player);
      }
      _lastBroadcastPosition = Duration.zero;
      _lastBroadcastBuffered = Duration.zero;
      _logEvent('dispose graceful stop settle');
      await Future<void>.delayed(_disposeStopSettleDelay);
      _logEvent('dispose graceful stop done');
    } catch (error) {
      _logEvent('dispose graceful stop ignored error=$error');
    }
  }

  Future<void> _initializeInternal() async {
    if (_initialized || _isClosedForOperations) {
      return;
    }
    _emit(_currentState.copyWith(status: PlaybackStatus.initializing));
    if (!_mediaKitInitialized) {
      await _sanitizeAndroidDebugMediaKitReferenceHolderFiles();
      mk.MediaKit.ensureInitialized();
      _mediaKitInitialized = true;
    }

    final runtimeConfiguration = resolveMpvRuntimeConfiguration(
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
      arcDecodeTier: _activeArcDecodeTierOrNull(),
    );
    _runtimeConfiguration = runtimeConfiguration;
    final player = mk.Player(
      configuration: mk.PlayerConfiguration(
        title: 'Nolive',
        logLevel: runtimeConfiguration.logLevel,
      ),
    );
    _player = player;
    // External native VO must not create media_kit VideoController: its native
    // render path requires vo=libmpv and would clobber gpu-next / gpu windows.
    if (runtimeConfiguration.usesExternalNativeWindow) {
      _controller = null;
      _controllerNotifier.value = null;
      // Start parked (vo=null): do not open an idle gpu-next window at init —
      // that window races WebKit headless views when the first room needs a
      // Twitch/YouTube bridge before any playback.
      final parkedProperties = Map<String, String>.from(
        runtimeConfiguration.platformProperties,
      )..['vo'] = 'null';
      await _configurePlayerProperties(player, properties: parkedProperties);
    } else {
      _controller = VideoController(
        player,
        configuration: runtimeConfiguration.controllerConfiguration,
      );
      _controllerNotifier.value = _controller;
      await _configurePlayerProperties(
        player,
        properties: runtimeConfiguration.platformProperties,
      );
    }
    _bindPlayer(player);
    _initialized = true;
    _emitDiagnostics(_freshDiagnostics());
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
    final controllerConfiguration =
        runtimeConfiguration.controllerConfiguration;
    _logEvent(
      'initialized vo=${controllerConfiguration.vo ?? 'platform-default'} '
      'hwdec=${controllerConfiguration.hwdec ?? 'platform-default'} '
      'externalNativeWindow=${runtimeConfiguration.usesExternalNativeWindow} '
      'externalVo=${runtimeConfiguration.externalNativeVideoOutputDriver ?? '-'} '
      'attachAfterVideoParams='
      '${controllerConfiguration.androidAttachSurfaceAfterVideoParameters ?? 'platform-default'} '
      'doubleBuffering=$doubleBufferingEnabled logEnabled=$logEnabled '
      'androidOutputFallback=${runtimeConfiguration.androidOutputFallbackReason ?? '-'} '
      'arcDecodeTier=${_activeArcDecodeTierOrNull() == null ? '-' : arcMpvDecodeTierLabel(_arcDecodeTier)}',
    );
  }

  ArcMpvDecodeTier? _activeArcDecodeTierOrNull() {
    if (!isAndroid || !looksLikeArcChromeOsRuntime()) {
      return null;
    }
    return _arcDecodeTier;
  }

  /// videoParams size != surface prime ⇒ media_kit will SetSurfaceSize and
  /// ARC V4L2 often freezes with false-positive hwdec. Escalate before freeze.
  void _maybePreemptArcEscalateOnVideoParams({
    required int streamWidth,
    required int streamHeight,
  }) {
    if (_arcPreemptiveEscalateInFlight) {
      return;
    }
    if (_activeArcDecodeTierOrNull() != ArcMpvDecodeTier.zeroCopy) {
      return;
    }
    final prime = _arcLastSurfacePrimeSize;
    if (prime == null) {
      return;
    }
    if (!arcSurfacePrimeMismatchesStream(
      primeWidth: prime.width,
      primeHeight: prime.height,
      streamWidth: streamWidth,
      streamHeight: streamHeight,
    )) {
      return;
    }
    final source = _currentState.source;
    if (source == null) {
      return;
    }
    _arcPreemptiveEscalateInFlight = true;
    _logEvent(
      'arc zerocopy preempt escalate reason=surface-size-mismatch '
      'prime=${prime.width}x${prime.height} stream=${streamWidth}x$streamHeight',
    );
    unawaited(
      _runSerialized('arcPreemptEscalate', () async {
        try {
          if (_isClosedForOperations ||
              _currentState.source != source ||
              _arcDecodeTier != ArcMpvDecodeTier.zeroCopy) {
            return;
          }
          final recovered = await _escalateArcDecodeTierAndReplay(
            source,
            reason: 'surface-size-mismatch',
          );
          if (!recovered) {
            _logEvent('arc zerocopy preempt escalate failed all tiers');
          }
        } catch (error) {
          _logEvent('arc zerocopy preempt escalate error=$error');
        } finally {
          _arcPreemptiveEscalateInFlight = false;
        }
      }),
    );
  }

  /// Tear down media_kit player/controller without closing this [MpvPlayer]
  /// shell, then re-init with the current ARC tier.
  /// Shorter than first-open health budget so leave/stop can run after failover.
  static const Duration _arcEscalateMediaSignalTimeout = Duration(seconds: 4);

  Future<void> _recreateMediaKitBackendForArcTier(ArcMpvDecodeTier tier) async {
    _logEvent(
      'arc decode tier recreate from=${arcMpvDecodeTierLabel(_arcDecodeTier)} '
      'to=${arcMpvDecodeTierLabel(tier)}',
    );
    _arcDecodeTier = tier;
    _arcLastSurfacePrimeSize = null;
    _arcPreemptiveEscalateInFlight = false;
    _androidEmbeddedPlayGateGeneration += 1;
    _pendingAndroidEmbeddedPlayGate = null;
    _emittedMediaCodecDeviceFailureForSource = false;
    _lastMpvOpeningDoneAt = null;
    _lastMediaCodecHardwareDecoderReadyAt = null;
    _pendingMediaCodecHardwareDecoderReadyCompleter = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _controller = null;
    _controllerNotifier.value = null;
    _runtimeConfiguration = null;
    _initialized = false;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
    await _initializeInternal();
    // Fresh media_kit player defaults volume to 100; restore session volume.
    final restoredVolume = (_currentState.volume.clamp(0, 1) * 100).toDouble();
    try {
      await _player?.setVolume(restoredVolume);
    } catch (error) {
      _logEvent('arc recreate restore volume failed error=$error');
    }
  }

  /// Poll outcome for ARC ladder decisions. Error is NOT success — otherwise
  /// decoder/device failures never demote copy → software.
  @visibleForTesting
  static ArcStartupMediaPollOutcome classifyArcStartupMediaPoll({
    required bool isClosed,
    required bool sourceStillActive,
    required PlaybackStatus status,
    required bool hasMediaSignal,
  }) {
    if (isClosed || !sourceStillActive) {
      return ArcStartupMediaPollOutcome.aborted;
    }
    if (hasMediaSignal) {
      return ArcStartupMediaPollOutcome.gotSignal;
    }
    if (status == PlaybackStatus.error) {
      return ArcStartupMediaPollOutcome.failed;
    }
    return ArcStartupMediaPollOutcome.timedOut;
  }

  Future<ArcStartupMediaPollOutcome> _pollAndroidStartupMediaSignal(
    PlaybackSource source, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final outcome = classifyArcStartupMediaPoll(
        isClosed: _isClosedForOperations,
        sourceStillActive: _currentState.source == source,
        status: _currentState.status,
        hasMediaSignal: hasMpvStartupMediaSignal(
          state: _currentState,
          diagnostics: _currentDiagnostics,
        ),
      );
      if (outcome != ArcStartupMediaPollOutcome.timedOut) {
        return outcome;
      }
      await Future<void>.delayed(_androidStartupMediaSignalPollInterval);
    }
    return classifyArcStartupMediaPoll(
      isClosed: _isClosedForOperations,
      sourceStillActive: _currentState.source == source,
      status: _currentState.status,
      hasMediaSignal: hasMpvStartupMediaSignal(
        state: _currentState,
        diagnostics: _currentDiagnostics,
      ),
    );
  }

  /// Escalate ARC decode tier and re-open [source] after hard-copy (or
  /// experimental zero-copy) fails. Must run inside an existing
  /// `_runSerialized` chain (no nested setSource/play serialization).
  Future<bool> _escalateArcDecodeTierAndReplay(
    PlaybackSource source, {
    String reason = 'no-media-signal',
  }) async {
    while (true) {
      if (_isClosedForOperations || _currentState.source != source) {
        return false;
      }
      final next = nextArcMpvDecodeTier(_arcDecodeTier);
      if (next == null) {
        return false;
      }
      _logEvent(
        'arc decode tier escalate reason=$reason '
        'next=${arcMpvDecodeTierLabel(next)}',
      );
      await _recreateMediaKitBackendForArcTier(next);
      final player = _player;
      if (player == null) {
        return false;
      }
      await _openSourceUnlocked(source);
      if (_isClosedForOperations || _currentState.source != source) {
        return false;
      }
      // Open-time hard error: try next tier without waiting full health budget.
      if (_currentState.status == PlaybackStatus.error) {
        continue;
      }
      await player.play();
      final outcome = await _pollAndroidStartupMediaSignal(
        source,
        timeout: _arcEscalateMediaSignalTimeout,
      );
      if (outcome == ArcStartupMediaPollOutcome.gotSignal) {
        _logEvent(
          'arc decode tier escalate recovered '
          'tier=${arcMpvDecodeTierLabel(_arcDecodeTier)}',
        );
        return true;
      }
      if (outcome == ArcStartupMediaPollOutcome.aborted) {
        return false;
      }
      // failed or timedOut → keep demoting
    }
  }

  /// Open [source] without taking the operation lock (caller holds it).
  Future<void> _openSourceUnlocked(PlaybackSource source) async {
    final player = _player;
    if (player == null) {
      return;
    }
    final previousState = _currentState;
    final openPreparation = resolveMpvOpenPreparation(
      previousState: previousState,
      isAndroid: isAndroid,
    );
    final previousSyntheticPlaylistFile = _activeSyntheticPlaylistFile;
    final openPlan = await _resolveOpenPlan(source);
    _androidEmbeddedPlayGateGeneration += 1;
    _pendingAndroidEmbeddedPlayGate = null;
    _emittedMediaCodecDeviceFailureForSource = false;
    _lastMpvOpeningDoneAt = null;
    _lastMediaCodecHardwareDecoderReadyAt = null;
    _pendingMediaCodecHardwareDecoderReadyCompleter = null;
    _logEvent(
      'setSource video=${_shortSourceDescriptor(source.url)} '
      'audio=${source.externalAudio == null ? '-' : _shortSourceDescriptor(source.externalAudio!.url)} '
      'audioHeaders=${source.externalAudio?.headers.keys.join(',') ?? '-'} '
      'strategy=${openPlan.strategy} '
      'arcTier=${_activeArcDecodeTierOrNull() == null ? '-' : arcMpvDecodeTierLabel(_arcDecodeTier)}',
    );
    _logEvent(
      'open plan strategy=${openPlan.strategy} '
      'media=${_shortSourceDescriptor(openPlan.mediaUri)} '
      'scheme=${openPlan.mediaUri.scheme.isEmpty ? '-' : openPlan.mediaUri.scheme} '
      'localFile=${openPlan.mediaUri.scheme == 'file'} '
      'loadsAudioInside=${openPlan.loadsAudioInsideMedia} '
      'master=${source.masterPlaylistUrl == null ? '-' : _shortSourceDescriptor(source.masterPlaylistUrl!)} '
      'embeddedMaster=${source.masterPlaylistContent?.trim().isNotEmpty == true} '
      'hlsBitrate=${source.hlsBitrate?.trim().isNotEmpty == true ? source.hlsBitrate : '-'}',
    );
    _emitDiagnostics(_freshDiagnostics(clearRecentLogs: true));
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.buffering,
        source: source,
        clearErrorMessage: true,
      ),
    );
    final androidOpenPreparation = await _preparePlayerForNextOpen(
      player,
      shouldStopBeforeOpen: openPreparation.shouldStopBeforeOpen,
      barrierDuration: openPreparation.barrierDuration,
      isInitialOpen: !openPreparation.shouldStopBeforeOpen,
    );
    _lastBroadcastPosition = Duration.zero;
    _lastBroadcastBuffered = Duration.zero;
    // Re-arm gpu-next/gpu only when actually opening media (window stays
    // closed while idle / during headless webview bootstrap).
    await _armExternalNativeWindowForPlayback(player);
    final preloadedExternalAudioConfigured = await _configureSourceOptions(
      player,
      source,
    );
    if (androidOpenPreparation.deferPlayUntilSurfaceReady) {
      final surfaceReadyBeforeOpen =
          await _waitForAndroidSurfaceBeforeInitialOpen(
            previousSurface: androidOpenPreparation.previousSurface,
          );
      if (!surfaceReadyBeforeOpen) {
        _pendingAndroidEmbeddedPlayGate = (
          generation: _androidEmbeddedPlayGateGeneration,
          previousSurface: androidOpenPreparation.previousSurface,
          isInitialOpen: !androidOpenPreparation.shouldStopBeforeOpen,
        );
        _logEvent(
          'setSource play-gate pending '
          'initial=${!androidOpenPreparation.shouldStopBeforeOpen} '
          'wid-before=${androidOpenPreparation.previousSurface.wid} '
          'texture-before=${androidOpenPreparation.previousSurface.textureId} '
          'reason=surface-published-after-open',
        );
      }
    }
    await player.open(
      mk.Media(openPlan.mediaUri.toString(), httpHeaders: openPlan.httpHeaders),
      play: false,
    );
    // Delay hwdec-active until decode can engage; immediate open often logs
    // current=- which is a false inactive signal.
    unawaited(_scheduleActiveHardwareDecodeLog(player));
    if (openPlan.loadsAudioInsideMedia || preloadedExternalAudioConfigured) {
      await player.setAudioTrack(mk.AudioTrack.auto());
    } else if (source.externalAudio != null) {
      await _addExternalAudioAfterOpen(player, source);
    } else {
      await player.setAudioTrack(mk.AudioTrack.auto());
    }
    if (_currentState.status == PlaybackStatus.error &&
        _currentState.source == source) {
      _logEvent(
        'setSource ready skipped current-error error=${_currentState.errorMessage ?? '-'}',
      );
    } else {
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.ready,
          source: source,
          clearErrorMessage: true,
        ),
      );
    }
    await _deleteSyntheticPlaylistFile(
      previousSyntheticPlaylistFile,
      preserveIfSameAsActive: true,
    );
  }

  bool _shouldBroadcastProgress({
    required Duration previous,
    required Duration next,
    required Duration step,
  }) {
    final delta = next - previous;
    return delta >= step || delta <= -step || next == Duration.zero;
  }

  void _emit(PlayerState state, {bool broadcast = true}) {
    _currentState = state.copyWith(backend: backend);
    if (broadcast && !_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }

  void _emitDiagnostics(PlayerDiagnostics diagnostics) {
    _currentDiagnostics = diagnostics.copyWith(backend: backend);
    if (!_diagnosticsController.isClosed) {
      _diagnosticsController.add(_currentDiagnostics);
    }
  }

  Future<void> _awaitAndroidStartupMediaSignalAfterPlay(
    PlaybackSource? source,
  ) async {
    if (!isAndroid || source == null) {
      return;
    }
    final timeout = resolveMpvStartupMediaSignalTimeout(source);
    final outcome = await _pollAndroidStartupMediaSignal(
      source,
      timeout: timeout,
    );
    if (outcome == ArcStartupMediaPollOutcome.gotSignal) {
      return;
    }
    if (outcome == ArcStartupMediaPollOutcome.aborted ||
        _isClosedForOperations ||
        _currentState.source != source) {
      return;
    }
    // ARC: demote on timeout OR stream/decoder error (error must not skip soft).
    if (_activeArcDecodeTierOrNull() != null) {
      final reason = outcome == ArcStartupMediaPollOutcome.failed
          ? 'startup-error'
          : 'no-media-signal';
      final recovered = await _escalateArcDecodeTierAndReplay(
        source,
        reason: reason,
      );
      if (recovered) {
        return;
      }
    }
    if (_currentState.status == PlaybackStatus.error) {
      return;
    }
    _logEvent(
      'startup health failed timeout=${timeout.inMilliseconds}ms '
      'error=$kMpvNoMediaTrackStartupError '
      'arcTier=${_activeArcDecodeTierOrNull() == null ? '-' : arcMpvDecodeTierLabel(_arcDecodeTier)}',
    );
    _emitDiagnostics(
      _currentDiagnostics.copyWith(error: kMpvNoMediaTrackStartupError),
    );
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.error,
        errorMessage: kMpvNoMediaTrackStartupError,
      ),
    );
  }

  PlayerDiagnostics _freshDiagnostics({bool clearRecentLogs = false}) {
    if (clearRecentLogs) {
      _recentLogs.clear();
    }
    return PlayerDiagnostics.empty(backend).copyWith(
      debugLogEnabled: logEnabled,
      recentLogs: logEnabled
          ? List<String>.unmodifiable(_recentLogs.toList(growable: false))
          : const <String>[],
    );
  }

  bool get _isClosedForOperations => _disposing || _disposed;

  Future<void> _runSerialized(
    String label,
    Future<void> Function() action, {
    bool allowWhileClosing = false,
  }) {
    final completer = Completer<void>();
    final run = _operationChain.then((_) async {
      if (_isClosedForOperations && !allowWhileClosing) {
        completer.complete();
        return;
      }
      _logEvent('operation $label start');
      try {
        await action();
        _logEvent('operation $label done');
        completer.complete();
      } catch (error, stackTrace) {
        _logEvent('operation $label failed error=$error');
        completer.completeError(error, stackTrace);
      }
    });
    _operationChain = run.catchError((Object _, StackTrace __) {});
    return completer.future;
  }

  Future<T?> _runSerializedNullable<T>(
    String label,
    Future<T?> Function() action,
  ) {
    final completer = Completer<T?>();
    final run = _operationChain.then((_) async {
      if (_isClosedForOperations) {
        completer.complete(null);
        return;
      }
      _logEvent('operation $label start');
      try {
        final result = await action();
        _logEvent('operation $label done');
        completer.complete(result);
      } catch (error, stackTrace) {
        _logEvent('operation $label failed error=$error');
        completer.completeError(error, stackTrace);
      }
    });
    _operationChain = run.catchError((Object _, StackTrace __) {});
    return completer.future;
  }

  void _logEvent(String message) {
    eventLogger?.call(message);
  }

  /// Observe active decode backend after open. Preference strings like
  /// `auto-safe` are not proof of hardware decode — `hwdec-current` is.
  /// Samples multiple times until a non-empty active current is seen (or delays
  /// exhaust) so HLS first-segment lag is not logged as permanent inactive.
  Future<void> _scheduleActiveHardwareDecodeLog(mk.Player player) async {
    final delays = resolveMpvHwdecActiveSampleDelays();
    var elapsed = Duration.zero;
    for (var i = 0; i < delays.length; i++) {
      final target = delays[i];
      final wait = target - elapsed;
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      elapsed = target;
      if (_isClosedForOperations || !identical(_player, player)) {
        return;
      }
      final active = await _logActiveHardwareDecodeState(
        player,
        sampleIndex: i + 1,
        sampleCount: delays.length,
      );
      if (active) {
        return;
      }
    }
  }

  /// Returns true when `hwdec-current` looks like an engaged backend.
  Future<bool> _logActiveHardwareDecodeState(
    mk.Player player, {
    int sampleIndex = 1,
    int sampleCount = 1,
  }) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      return false;
    }
    try {
      final hwdecCurrent = (await platform.getProperty('hwdec-current')).trim();
      final hwdec = (await platform.getProperty('hwdec')).trim();
      final vo = (await platform.getProperty('current-vo')).trim();
      _logEvent(
        'hwdec-active sample=$sampleIndex/$sampleCount '
        'requested=${hwdec.isEmpty ? '-' : hwdec} '
        'current=${hwdecCurrent.isEmpty ? '-' : hwdecCurrent} '
        'vo=${vo.isEmpty ? '-' : vo}',
      );
      return _looksLikeActiveHwdecCurrent(hwdecCurrent);
    } catch (error) {
      _logEvent('hwdec-active probe failed error=$error');
      return false;
    }
  }

  Future<void> _sanitizeAndroidDebugMediaKitReferenceHolderFiles() async {
    if (!kDebugMode || !isAndroid) {
      return;
    }
    final existing = _pendingAndroidDebugMediaKitReferenceCleanup;
    if (existing != null) {
      await existing;
      return;
    }
    final cleanup = () async {
      try {
        final supportDirectory = await getApplicationSupportDirectory();
        final deleted =
            await deleteMediaKitNativeReferenceHolderFilesInDirectory(
              supportDirectory,
            );
        _logEvent(
          'debug native-reference-holder cleanup deleted=$deleted '
          'dir=${supportDirectory.path}',
        );
      } catch (error) {
        _logEvent('debug native-reference-holder cleanup failed error=$error');
      }
    }();
    _pendingAndroidDebugMediaKitReferenceCleanup = cleanup;
    await cleanup;
  }

  bool _shouldIgnoreRuntimeMessage(String message) {
    if (_captureScreenshotInFlight &&
        looksLikeMpvScreenshotFailureMessage(message)) {
      return true;
    }
    return shouldIgnoreMpvErrorMessage(
      source: _currentState.source,
      message: message,
    );
  }

  Map<String, String> _videoParamsToMap(mk.VideoParams params) {
    return <String, String>{
      if (params.pixelformat != null) 'pixel_format': params.pixelformat!,
      if (params.hwPixelformat != null)
        'hw_pixel_format': params.hwPixelformat!,
      if (params.w != null) 'width': '${params.w}',
      if (params.h != null) 'height': '${params.h}',
      if (params.aspect != null) 'aspect': '${params.aspect}',
      if (params.rotate != null) 'rotate': '${params.rotate}',
      if (params.primaries != null) 'primaries': params.primaries!,
      if (params.gamma != null) 'gamma': params.gamma!,
    };
  }

  Map<String, String> _audioParamsToMap(mk.AudioParams params) {
    return <String, String>{
      if (params.format != null) 'format': params.format!,
      if (params.sampleRate != null) 'sample_rate': '${params.sampleRate}',
      if (params.channels != null) 'channels': params.channels!,
      if (params.channelCount != null)
        'channel_count': '${params.channelCount}',
      if (params.hrChannels != null) 'hr_channels': params.hrChannels!,
    };
  }

  String _shortSourceDescriptor(Uri uri) {
    if (uri.scheme == 'file') {
      final segments = uri.pathSegments;
      final fileName = segments.isEmpty ? uri.path : segments.last;
      final parent = segments.length > 1 ? segments[segments.length - 2] : '';
      return [
        'file',
        if (parent.isNotEmpty) parent,
        if (fileName.isNotEmpty) fileName,
      ].join(' ');
    }
    final itagMatch = RegExp(r'/itag/([^/]+)').firstMatch(uri.path);
    final idMatch = RegExp(r'/id/([^/]+)').firstMatch(uri.path);
    final parts = <String>[uri.host];
    if (itagMatch != null) {
      parts.add('itag=${itagMatch.group(1)}');
    }
    if (idMatch != null) {
      parts.add('id=${idMatch.group(1)}');
    }
    if (parts.length == 1) {
      parts.add(
        uri.path.split('/').where((item) => item.isNotEmpty).take(2).join('/'),
      );
    }
    return parts.join(' ');
  }
}

/// In-app stand-in while video is shown in an independent mpv VO window.
class _MpvExternalNativeWindowPlaceholder extends StatelessWidget {
  const _MpvExternalNativeWindowPlaceholder({
    super.key,
    required this.videoOutputDriver,
  });

  final String videoOutputDriver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '独立原生 MPV 窗口播放中',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'vo=$videoOutputDriver\n'
                '画面在系统独立窗口，不走 Flutter Texture。\n'
                '用于验证原生播放流畅度；关闭设置项后恢复内嵌。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
