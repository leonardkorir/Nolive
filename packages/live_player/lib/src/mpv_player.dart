import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  static const Duration _androidStartupMediaSignalPollInterval = Duration(
    milliseconds: 100,
  );
  static const Duration _androidMediaCodecReinitClassificationThreshold =
      Duration(milliseconds: 50);
  static const String _fallbackVideoOutputDriver = 'gpu-next';
  static const String _fallbackHardwareDecoder = 'auto-safe';

  static bool _mediaKitInitialized = false;

  final bool enableHardwareAcceleration;
  final bool compatMode;
  final bool doubleBufferingEnabled;
  final bool customOutputEnabled;
  final String videoOutputDriver;
  final String audioOutputDriver;
  final String hardwareDecoder;
  final bool logEnabled;
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
      await _initializeInternal();
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
        'strategy=${openPlan.strategy}',
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
        mk.Media(
          openPlan.mediaUri.toString(),
          httpHeaders: openPlan.httpHeaders,
        ),
        play: false,
      );
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
      await player.stop();
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
      if (player == null) {
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
    if (!shouldStop) {
      return;
    }
    try {
      _logEvent('dispose graceful stop start');
      await player.stop();
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
    );
    _runtimeConfiguration = runtimeConfiguration;
    final player = mk.Player(
      configuration: mk.PlayerConfiguration(
        title: 'Nolive',
        logLevel: runtimeConfiguration.logLevel,
      ),
    );
    _player = player;
    _controller = VideoController(
      player,
      configuration: runtimeConfiguration.controllerConfiguration,
    );
    _controllerNotifier.value = _controller;
    await _configurePlayerProperties(
      player,
      properties: runtimeConfiguration.platformProperties,
    );
    _bindPlayer(player);
    _initialized = true;
    _emitDiagnostics(_freshDiagnostics());
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
    final controllerConfiguration =
        runtimeConfiguration.controllerConfiguration;
    _logEvent(
      'initialized vo=${controllerConfiguration.vo ?? 'platform-default'} '
      'hwdec=${controllerConfiguration.hwdec ?? 'platform-default'} '
      'attachAfterVideoParams='
      '${controllerConfiguration.androidAttachSurfaceAfterVideoParameters ?? 'platform-default'} '
      'doubleBuffering=$doubleBufferingEnabled logEnabled=$logEnabled '
      'androidOutputFallback=${runtimeConfiguration.androidOutputFallbackReason ?? '-'}',
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
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_isClosedForOperations ||
          _currentState.source != source ||
          _currentState.status == PlaybackStatus.error ||
          hasMpvStartupMediaSignal(
            state: _currentState,
            diagnostics: _currentDiagnostics,
          )) {
        return;
      }
      await Future<void>.delayed(_androidStartupMediaSignalPollInterval);
    }
    if (_isClosedForOperations ||
        _currentState.source != source ||
        _currentState.status == PlaybackStatus.error ||
        hasMpvStartupMediaSignal(
          state: _currentState,
          diagnostics: _currentDiagnostics,
        )) {
      return;
    }
    _logEvent(
      'startup health failed timeout=${timeout.inMilliseconds}ms '
      'error=$kMpvNoMediaTrackStartupError',
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
