import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import 'base_player.dart';
import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';

class MpvPlayer implements BasePlayer {
  MpvPlayer({
    this.enableHardwareAcceleration = true,
    this.compatMode = false,
    this.doubleBufferingEnabled = false,
    this.customOutputEnabled = false,
    this.videoOutputDriver = 'gpu-next',
    this.hardwareDecoder = 'auto-safe',
    this.logEnabled = false,
    this.eventLogger,
  });

  static const Duration _progressBroadcastStep = Duration(seconds: 1);
  static const Duration _bufferBroadcastStep = Duration(seconds: 1);
  static const Duration _disposeStopSettleDelay = Duration(milliseconds: 650);
  static const Duration _sourceSwitchStopSettleDelay =
      Duration(milliseconds: 650);
  static const Duration _initialAndroidOpenSettleDelay =
      Duration(milliseconds: 150);
  static const Duration _androidInitialEmbeddedViewMountReadyTimeout =
      Duration(milliseconds: 250);
  static const Duration _androidInitialEmbeddedPlatformReadyTimeout =
      Duration(milliseconds: 250);
  static const Duration _androidInitialEmbeddedSurfaceReadyBudget =
      Duration(milliseconds: 350);
  static const Duration _androidInitialEmbeddedSurfaceReadyPollInterval =
      Duration(milliseconds: 150);
  static const Duration _androidInitialEmbeddedSurfaceAttachStabilizeTimeout =
      Duration(milliseconds: 220);
  static const Duration _androidEmbeddedViewMountReadyTimeout =
      Duration(milliseconds: 250);
  static const Duration _androidEmbeddedPlatformReadyTimeout =
      Duration(milliseconds: 250);
  static const Duration _androidEmbeddedSurfaceReadyBudget =
      Duration(milliseconds: 350);
  static const Duration _androidEmbeddedSurfaceReadyPollInterval =
      Duration(milliseconds: 150);
  static const Duration _androidEmbeddedSurfaceAttachStabilizeTimeout =
      Duration(milliseconds: 220);
  static const Duration _androidReopenFreshSurfaceWaitBudget =
      Duration(milliseconds: 800);
  static const Duration _androidInitialEmbeddedPlaySurfaceReadyTimeout =
      Duration(milliseconds: 2200);
  static const Duration _androidInitialEmbeddedPlaySurfaceFallbackTimeout =
      Duration(milliseconds: 1000);
  static const Duration _androidEmbeddedHardwareDecoderReadyTimeout =
      Duration(milliseconds: 900);
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
  final String hardwareDecoder;
  final bool logEnabled;
  final void Function(String message)? eventLogger;
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
        isAndroid: Platform.isAndroid,
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
      await player.open(
        mk.Media(
          openPlan.mediaUri.toString(),
          httpHeaders: openPlan.httpHeaders,
        ),
        play: false,
      );
      if (androidOpenPreparation.deferPlayUntilSurfaceReady) {
        _pendingAndroidEmbeddedPlayGate = (
          generation: _androidEmbeddedPlayGateGeneration,
          previousSurface: androidOpenPreparation.previousSurface,
          isInitialOpen: !openPreparation.shouldStopBeforeOpen,
        );
      }
      if (openPlan.loadsAudioInsideMedia || preloadedExternalAudioConfigured) {
        await player.setAudioTrack(mk.AudioTrack.auto());
      } else if (source.externalAudio != null) {
        await player.setAudioTrack(
          mk.AudioTrack.uri(
            source.externalAudio!.url.toString(),
            title: source.externalAudio!.label,
          ),
        );
      } else {
        await player.setAudioTrack(mk.AudioTrack.auto());
      }
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.ready,
          source: source,
          clearErrorMessage: true,
        ),
      );
      await _deleteSyntheticPlaylistFile(
        previousSyntheticPlaylistFile,
        preserveIfSameAsActive: true,
      );
    });
  }

  Future<_MpvOpenPlan> _resolveOpenPlan(PlaybackSource source) async {
    if (shouldInlineSplitHlsAudioIntoSource(source)) {
      final resolvedMasterFile =
          await maybeWriteResolvedSplitHlsMasterPlaylistFile(source);
      if (resolvedMasterFile != null) {
        _activeSyntheticPlaylistFile = resolvedMasterFile;
        return _MpvOpenPlan(
          mediaUri: resolvedMasterFile.uri,
          httpHeaders:
              _sharedHttpHeadersForSplitHls(source) ?? const <String, String>{},
          loadsAudioInsideMedia: true,
          strategy: 'resolved-inline-hls-master',
        );
      }
      if (shouldFallbackToSyntheticSplitMaster(source)) {
        final file = await writeSplitHlsMasterPlaylistFile(source);
        _activeSyntheticPlaylistFile = file;
        return _MpvOpenPlan(
          mediaUri: file.uri,
          httpHeaders:
              _sharedHttpHeadersForSplitHls(source) ?? const <String, String>{},
          loadsAudioInsideMedia: true,
          strategy: 'inline-hls-master',
        );
      }
    }
    final rewrittenManifestFile =
        await maybeWriteResolvedSingleSourceHlsPlaylistFile(source);
    if (rewrittenManifestFile != null) {
      _activeSyntheticPlaylistFile = rewrittenManifestFile;
      return _MpvOpenPlan(
        mediaUri: rewrittenManifestFile.uri,
        httpHeaders: source.headers,
        loadsAudioInsideMedia: false,
        strategy: 'resolved-hls-manifest',
      );
    }
    _activeSyntheticPlaylistFile = null;
    return _MpvOpenPlan(
      mediaUri: source.url,
      httpHeaders: source.headers,
      loadsAudioInsideMedia: false,
      strategy:
          source.externalAudio == null ? 'single-source' : 'external-audio',
    );
  }

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
      hardwareDecoder:
          _runtimeConfiguration?.controllerConfiguration.hwdec?.trim(),
      videoTrackSelection: 'auto',
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

  @override
  Future<void> play() async {
    await _runSerialized('play', () async {
      final player = _player;
      if (player == null) {
        return;
      }
      await _awaitAndroidEmbeddedPlayGateIfNeeded();
      await player.play();
    });
  }

  Future<void> _awaitAndroidEmbeddedPlayGateIfNeeded() async {
    if (!Platform.isAndroid) {
      return;
    }
    final gate = _pendingAndroidEmbeddedPlayGate;
    if (gate == null) {
      return;
    }
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    final controller = _controller;
    final platform = controller?.notifier.value;
    if (controller == null || platform == null) {
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    _logEvent(
      'play gate wait-surface '
      'initial=${gate.isInitialOpen} '
      'wid-before=${gate.previousSurface.wid} '
      'texture-before=${gate.previousSurface.textureId}',
    );
    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: controller.id,
      previousSurface: gate.previousSurface,
      timeout: _androidInitialEmbeddedPlaySurfaceReadyTimeout,
      requireSurfaceHandle: true,
    );
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    if (refresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: _androidEmbeddedSurfaceAttachStabilizeTimeout,
      );
      await _awaitAndroidEmbeddedSurfaceFrames();
      _logEvent(
        'play gate surface-ready '
        'initial=${gate.isInitialOpen} '
        'wid=${refresh.currentSurface.wid} '
        'texture=${refresh.currentSurface.textureId}',
      );
      await _awaitAndroidEmbeddedHardwareDecoderReadyIfNeeded(
        surfaceReadyAt: DateTime.now(),
      );
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    final lateRefresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: controller.id,
      previousSurface: refresh.currentSurface,
      timeout: _androidInitialEmbeddedPlaySurfaceFallbackTimeout,
      requireSurfaceHandle: true,
    );
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    if (lateRefresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: _androidEmbeddedSurfaceAttachStabilizeTimeout,
      );
      await _awaitAndroidEmbeddedSurfaceFrames();
      _logEvent(
        'play gate surface-ready '
        'initial=${gate.isInitialOpen} '
        'wid=${lateRefresh.currentSurface.wid} '
        'texture=${lateRefresh.currentSurface.textureId} '
        'late=true',
      );
      await _awaitAndroidEmbeddedHardwareDecoderReadyIfNeeded(
        surfaceReadyAt: DateTime.now(),
      );
      _pendingAndroidEmbeddedPlayGate = null;
      return;
    }
    _logEvent(
      'play gate surface-timeout '
      'initial=${gate.isInitialOpen} '
      'wid=${lateRefresh.currentSurface.wid} '
      'texture=${lateRefresh.currentSurface.textureId}',
    );
    _logEvent(
        'player diagnostics decoder=software reason=surface-timeout-fallback');
    _pendingAndroidEmbeddedPlayGate = null;
  }

  Future<void> _awaitAndroidEmbeddedHardwareDecoderReadyIfNeeded({
    required DateTime surfaceReadyAt,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final controllerConfiguration =
        _runtimeConfiguration?.controllerConfiguration;
    final runtimeVideoOutput =
        controllerConfiguration?.vo?.trim().toLowerCase() ?? '';
    final runtimeHwdec = _effectiveAndroidRuntimeHardwareDecoder(
      _runtimeConfiguration,
    ).toLowerCase();
    if (!shouldWarmAndroidMediaCodecOpenPath(
      videoOutputDriver: runtimeVideoOutput,
      hardwareDecoder: runtimeHwdec,
      isAndroid: true,
    )) {
      return;
    }
    final existingReadyAt = _lastMediaCodecHardwareDecoderReadyAt;
    if (existingReadyAt != null) {
      final delta = resolveAndroidEmbeddedHardwareDecoderReadyDelta(
        surfaceReadyAt: surfaceReadyAt,
        hardwareDecoderReadyAt: existingReadyAt,
      );
      _logEvent(
        'play gate hw-ready delta=${delta.inMilliseconds}ms '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return;
    }
    final completer = Completer<DateTime>();
    _pendingMediaCodecHardwareDecoderReadyCompleter = completer;
    final lateReadyAt = _lastMediaCodecHardwareDecoderReadyAt;
    if (lateReadyAt != null && !completer.isCompleted) {
      completer.complete(lateReadyAt);
    }
    DateTime? readyAt;
    try {
      readyAt = await completer.future.timeout(
        _androidEmbeddedHardwareDecoderReadyTimeout,
      );
    } on TimeoutException {
      readyAt = null;
    } finally {
      if (identical(
        _pendingMediaCodecHardwareDecoderReadyCompleter,
        completer,
      )) {
        _pendingMediaCodecHardwareDecoderReadyCompleter = null;
      }
    }
    if (_isClosedForOperations) {
      return;
    }
    if (readyAt == null) {
      _logEvent(
        'play gate hw-ready timeout=${_androidEmbeddedHardwareDecoderReadyTimeout.inMilliseconds}ms '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return;
    }
    final delta = resolveAndroidEmbeddedHardwareDecoderReadyDelta(
      surfaceReadyAt: surfaceReadyAt,
      hardwareDecoderReadyAt: readyAt,
    );
    _logEvent(
      'play gate hw-ready delta=${delta.inMilliseconds}ms '
      'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
      'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
    );
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
        isAndroid: Platform.isAndroid,
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

  Future<Uint8List?> _captureScreenshotToTempFile(mk.Player player) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      return null;
    }
    final directory =
        await Directory.systemTemp.createTemp('nolive-mpv-screenshot-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}screenshot.png',
    );
    try {
      const attemptCommands = <List<String>>[
        <String>['screenshot-to-file', 'video'],
        <String>['screenshot-to-file'],
      ];
      for (final command in attemptCommands) {
        try {
          await platform.command(<String>[
            command.first,
            file.path,
            ...command.skip(1),
          ]);
        } catch (_) {
          continue;
        }
        final bytes = await waitForScreenshotFileBytes(file);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      }
      return null;
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup for temporary screenshot files.
      }
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup for temporary screenshot directories.
      }
    }
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
    await _runSerialized(
      'dispose',
      () async {
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
      },
      allowWhileClosing: true,
    );
  }

  Future<void> _deleteSyntheticPlaylistFile(
    File? file, {
    bool preserveIfSameAsActive = false,
  }) async {
    if (file == null) {
      return;
    }
    if (preserveIfSameAsActive &&
        _activeSyntheticPlaylistFile?.path == file.path) {
      return;
    }
    try {
      final parent = file.parent;
      if (await file.exists()) {
        await file.delete();
      }
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup for transient synthetic manifests.
    }
  }

  Future<void> _stopPlayerBeforeDispose(mk.Player player) async {
    final state = _currentState;
    final shouldStop = state.source != null ||
        switch (state.status) {
          PlaybackStatus.buffering ||
          PlaybackStatus.playing ||
          PlaybackStatus.paused ||
          PlaybackStatus.completed ||
          PlaybackStatus.error =>
            true,
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

  Future<AndroidOpenPreparationResult> _preparePlayerForNextOpen(
    mk.Player player, {
    required bool shouldStopBeforeOpen,
    required Duration barrierDuration,
    required bool isInitialOpen,
  }) async {
    final previousSurface = readAndroidSurfaceSnapshot(
      platform: _controller?.notifier.value,
      textureId: _controller?.id,
    );
    if (shouldStopBeforeOpen) {
      try {
        _logEvent('setSource source-switch stop start');
        await player.stop();
        _logEvent('setSource source-switch stop settle');
      } catch (error) {
        _logEvent('setSource source-switch stop ignored error=$error');
      }
    }
    if (barrierDuration > Duration.zero) {
      _logEvent('setSource open barrier ${barrierDuration.inMilliseconds}ms');
      await Future<void>.delayed(barrierDuration);
    }
    if (shouldStopBeforeOpen) {
      await _awaitAndroidEmbeddedSurfaceRefreshForReopen(
        previousSurface,
      );
    }
    var warmupResult = await _awaitAndroidEmbeddedSurfaceReadyForOpen(
      isInitialOpen: isInitialOpen,
    );
    final deferPlayUntilSurfaceReady =
        shouldDelayAndroidEmbeddedPlayUntilSurfaceReady(
      isInitialOpen: isInitialOpen,
      previousSurface: previousSurface,
      warmupResult: warmupResult,
    );
    if (deferPlayUntilSurfaceReady) {
      _logEvent(
        'setSource play-gate pending '
        'initial=$isInitialOpen wid-before=${previousSurface.wid} '
        'texture-before=${previousSurface.textureId} '
        'reason=surface-published-after-open',
      );
    }
    return (
      previousSurface: previousSurface,
      deferPlayUntilSurfaceReady: deferPlayUntilSurfaceReady,
      shouldStopBeforeOpen: shouldStopBeforeOpen,
    );
  }

  Future<AndroidSurfaceRefreshResult?>
      _awaitAndroidEmbeddedSurfaceRefreshForReopen(
    AndroidSurfaceSnapshot previousSurface,
  ) async {
    if (!Platform.isAndroid) {
      return null;
    }
    final controller = _controller;
    final controllerConfiguration =
        _runtimeConfiguration?.controllerConfiguration;
    if (controller == null || controllerConfiguration == null) {
      return null;
    }
    final runtimeVideoOutput =
        controllerConfiguration.vo?.trim().toLowerCase() ?? '';
    final runtimeHwdec = _effectiveAndroidRuntimeHardwareDecoder(
      _runtimeConfiguration,
    ).toLowerCase();
    if (!shouldWarmAndroidMediaCodecOpenPath(
      videoOutputDriver: runtimeVideoOutput,
      hardwareDecoder: runtimeHwdec,
      isAndroid: true,
    )) {
      return null;
    }
    await _awaitAndroidEmbeddedSurfaceFrames();
    final platformReady = await waitForVideoControllerPlatformReady(
      controller.notifier,
      timeout: _androidEmbeddedPlatformReadyTimeout,
    );
    if (!platformReady) {
      _logEvent(
        'setSource surface-refresh skipped platform-timeout '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return null;
    }
    final currentSurface = readAndroidSurfaceSnapshot(
      platform: controller.notifier.value,
      textureId: controller.id,
    );
    if (shouldReuseExistingAndroidSurfaceForReopen(
      previousSurface: previousSurface,
      currentSurface: currentSurface,
    )) {
      _logEvent(
        'setSource surface-refresh reopen '
        'wid-before=${previousSurface.wid} texture-before=${previousSurface.textureId} '
        'wid-after=${currentSurface.wid} texture-after=${currentSurface.textureId} '
        'wid-changed=false ready=true reuse=true '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return (
        currentSurface: currentSurface,
        changed: false,
        ready: true,
      );
    }
    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: controller.notifier.value,
      textureId: controller.id,
      previousSurface: previousSurface,
      timeout: _androidReopenFreshSurfaceWaitBudget,
      requireSurfaceHandle: true,
    );
    final refreshedSurface = refresh.currentSurface;
    _logEvent(
      'setSource surface-refresh reopen '
      'wid-before=${previousSurface.wid} texture-before=${previousSurface.textureId} '
      'wid-after=${refreshedSurface.wid} texture-after=${refreshedSurface.textureId} '
      'wid-changed=${refresh.changed} ready=${refresh.ready} '
      'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
      'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
    );
    return refresh;
  }

  Future<AndroidEmbeddedSurfaceWarmupResult?>
      _awaitAndroidEmbeddedSurfaceReadyForOpen({
    required bool isInitialOpen,
    AndroidEmbeddedSurfaceWarmupPolicy? warmupPolicy,
    String phase = 'warmup',
  }) async {
    if (!Platform.isAndroid) {
      return null;
    }
    final controller = _controller;
    final controllerConfiguration =
        _runtimeConfiguration?.controllerConfiguration;
    if (controller == null || controllerConfiguration == null) {
      return null;
    }
    final runtimeVideoOutput =
        controllerConfiguration.vo?.trim().toLowerCase() ?? '';
    final runtimeHwdec = _effectiveAndroidRuntimeHardwareDecoder(
      _runtimeConfiguration,
    ).toLowerCase();
    if (!shouldWarmAndroidMediaCodecOpenPath(
      videoOutputDriver: runtimeVideoOutput,
      hardwareDecoder: runtimeHwdec,
      isAndroid: true,
    )) {
      _logEvent(
        'setSource surface-ready skipped '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return null;
    }
    final policy = warmupPolicy ??
        resolveAndroidEmbeddedSurfaceWarmupPolicy(
          isInitialOpen: isInitialOpen,
        );
    final stopwatch = Stopwatch()..start();
    final mounted = await waitForValueListenableValue<bool>(
      _embeddedViewMounted,
      isReady: (value) => value,
      timeout: policy.viewMountTimeout,
    );
    var platformReady = false;
    var surfaceReady = false;
    var stabilized = false;
    var attempts = 0;
    if (mounted) {
      await _awaitAndroidEmbeddedSurfaceFrames();
      platformReady = await waitForVideoControllerPlatformReady(
        controller.notifier,
        timeout: policy.platformTimeout,
      );
      if (platformReady) {
        final deadline = DateTime.now().add(policy.surfaceReadyBudget);
        while (true) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) {
            break;
          }
          attempts += 1;
          final waitTimeout = remaining < policy.surfaceReadyPollInterval
              ? remaining
              : policy.surfaceReadyPollInterval;
          surfaceReady = await waitForVideoControllerSurfaceReady(
            controller: controller,
            timeout: waitTimeout,
          );
          if (!surfaceReady) {
            await _awaitAndroidEmbeddedSurfaceFrames();
            continue;
          }
          stabilized = await waitForAndroidSurfaceAttachStabilization(
            controller.notifier.value,
            timeout: policy.attachStabilizeTimeout,
          );
          if (stabilized) {
            break;
          }
          await _awaitAndroidEmbeddedSurfaceFrames();
        }
      }
    }
    stopwatch.stop();
    final currentWid = tryReadAndroidSurfaceHandle(
      controller.notifier.value,
    );
    final currentTextureId = controller.id.value;
    final result = (
      mounted: mounted,
      platformReady: platformReady,
      surfaceReady: surfaceReady,
      stabilized: stabilized,
      attempts: attempts,
      elapsed: stopwatch.elapsed,
      wid: currentWid,
      textureId: currentTextureId,
    );
    if (!mounted) {
      _logEvent(
        'setSource surface-ready $phase skipped view-not-mounted '
        'initial=$isInitialOpen elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return result;
    }
    if (!platformReady) {
      _logEvent(
        'setSource surface-ready $phase platform-timeout '
        'initial=$isInitialOpen elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return result;
    }
    if (isInitialOpen && !surfaceReady) {
      _logEvent(
        'setSource surface-ready $phase skipped '
        'reason=wid-pending initial=$isInitialOpen attempts=$attempts '
        'elapsed=${stopwatch.elapsedMilliseconds}ms '
        'budget=${policy.surfaceReadyBudget.inMilliseconds}ms '
        'wid=${currentWid ?? 0} texture=${currentTextureId ?? 0} '
        'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
        'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
      );
      return result;
    }
    _logEvent(
      'setSource surface-ready $phase '
      'mounted=$mounted platform=$platformReady '
      'surface=$surfaceReady stabilized=$stabilized '
      'initial=$isInitialOpen attempts=$attempts '
      'elapsed=${stopwatch.elapsedMilliseconds}ms '
      'budget=${policy.surfaceReadyBudget.inMilliseconds}ms '
      'wid=${currentWid ?? 0} texture=${currentTextureId ?? 0} '
      'runtime-vo=${runtimeVideoOutput.isEmpty ? 'platform-default' : runtimeVideoOutput} '
      'runtime-hwdec=${runtimeHwdec.isEmpty ? 'platform-default' : runtimeHwdec}',
    );
    return result;
  }

  Future<void> _awaitAndroidEmbeddedSurfaceFrames() async {
    final binding = WidgetsBinding.instance;
    if (!binding.hasScheduledFrame) {
      binding.scheduleFrame();
    }
    await binding.endOfFrame;
    if (!binding.hasScheduledFrame) {
      binding.scheduleFrame();
    }
    await binding.endOfFrame;
  }

  Future<void> _initializeInternal() async {
    if (_initialized || _isClosedForOperations) {
      return;
    }
    _emit(_currentState.copyWith(status: PlaybackStatus.initializing));
    if (!_mediaKitInitialized) {
      mk.MediaKit.ensureInitialized();
      _mediaKitInitialized = true;
    }

    final runtimeConfiguration = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: enableHardwareAcceleration,
      compatMode: compatMode,
      doubleBufferingEnabled: doubleBufferingEnabled,
      customOutputEnabled: customOutputEnabled,
      videoOutputDriver: videoOutputDriver,
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

  void _bindPlayer(mk.Player player) {
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (playing) {
          _logEvent('stream playing=true');
          _emit(_currentState.copyWith(status: PlaybackStatus.playing));
        } else if (_currentState.status == PlaybackStatus.playing) {
          _logEvent('stream playing=false');
          _emit(_currentState.copyWith(status: PlaybackStatus.paused));
        }
      }),
      player.stream.completed.listen((completed) {
        if (completed) {
          _logEvent('stream completed=true');
          _emit(_currentState.copyWith(status: PlaybackStatus.completed));
        }
      }),
      player.stream.position.listen((position) {
        final nextState = _currentState.copyWith(position: position);
        final shouldBroadcast = _shouldBroadcastProgress(
          previous: _lastBroadcastPosition,
          next: position,
          step: _progressBroadcastStep,
        );
        _emit(nextState, broadcast: shouldBroadcast);
        if (shouldBroadcast) {
          _lastBroadcastPosition = position;
        }
      }),
      player.stream.duration.listen((duration) {
        _emit(_currentState.copyWith(duration: duration));
      }),
      player.stream.volume.listen((volume) {
        _emit(_currentState.copyWith(volume: (volume / 100).clamp(0, 1)));
      }),
      player.stream.buffering.listen((buffering) {
        _logEvent('stream buffering=$buffering');
        _emitDiagnostics(_currentDiagnostics.copyWith(buffering: buffering));
        if (buffering) {
          _emit(_currentState.copyWith(status: PlaybackStatus.buffering));
          return;
        }
        if (_currentState.status == PlaybackStatus.buffering &&
            _currentState.source != null) {
          _emit(_currentState.copyWith(status: PlaybackStatus.ready));
        }
      }),
      player.stream.buffer.listen((buffered) {
        _emitDiagnostics(_currentDiagnostics.copyWith(buffered: buffered));
        final nextState = _currentState.copyWith(buffered: buffered);
        final shouldBroadcast = _shouldBroadcastProgress(
          previous: _lastBroadcastBuffered,
          next: buffered,
          step: _bufferBroadcastStep,
        );
        _emit(nextState, broadcast: shouldBroadcast);
        if (shouldBroadcast) {
          _lastBroadcastBuffered = buffered;
        }
      }),
      player.stream.error.listen((message) {
        if (message.isEmpty) {
          return;
        }
        if (_shouldIgnoreRuntimeMessage(message)) {
          _logEvent('stream warning ignored=$message');
          return;
        }
        _logEvent('stream error=$message');
        _emitDiagnostics(_currentDiagnostics.copyWith(error: message));
        _emit(
          _currentState.copyWith(
            status: PlaybackStatus.error,
            errorMessage: message,
          ),
        );
      }),
      player.stream.width.listen((width) {
        _emitDiagnostics(_currentDiagnostics.copyWith(width: width));
      }),
      player.stream.height.listen((height) {
        _emitDiagnostics(_currentDiagnostics.copyWith(height: height));
      }),
      player.stream.videoParams.listen((params) {
        _emitDiagnostics(
          _currentDiagnostics.copyWith(
            videoParams: _videoParamsToMap(params),
          ),
        );
      }),
      player.stream.audioParams.listen((params) {
        _emitDiagnostics(
          _currentDiagnostics.copyWith(
            audioParams: _audioParamsToMap(params),
          ),
        );
      }),
      if (logEnabled)
        player.stream.log.listen((entry) {
          final message = entry.text.trim();
          if (message.isEmpty) {
            return;
          }
          if (_shouldIgnoreRuntimeMessage(message)) {
            return;
          }
          final normalizedMessage = message.toLowerCase();
          if (normalizedMessage.contains('opening done:')) {
            _lastMpvOpeningDoneAt = DateTime.now();
          }
          if (normalizedMessage.contains(
            'using hardware decoding (mediacodec)',
          )) {
            final readyAt = DateTime.now();
            _lastMediaCodecHardwareDecoderReadyAt = readyAt;
            final completer = _pendingMediaCodecHardwareDecoderReadyCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete(readyAt);
            }
          }
          if (!_emittedMediaCodecDeviceFailureForSource &&
              normalizedMessage.contains('could not create device')) {
            _emittedMediaCodecDeviceFailureForSource = true;
            final failureTimestamp = DateTime.now();
            final failureReason = classifyAndroidMediaCodecDeviceFailureReason(
              lastOpeningDoneAt: _lastMpvOpeningDoneAt,
              failureTimestamp: failureTimestamp,
              reinitThreshold: _androidMediaCodecReinitClassificationThreshold,
            );
            final openingDoneDelta = _lastMpvOpeningDoneAt == null
                ? null
                : failureTimestamp.difference(_lastMpvOpeningDoneAt!);
            _logEvent(
              'player diagnostics decoder=software '
              'reason=$failureReason'
              '${openingDoneDelta == null ? '' : ' delta=${openingDoneDelta.inMilliseconds}ms'}',
            );
          }
          final nextEntry = '[${entry.level}] ${entry.prefix}: $message';
          _logEvent('mpv $nextEntry');
          final nextLogs = List<String>.from(_recentLogs)..add(nextEntry);
          while (nextLogs.length > 24) {
            nextLogs.removeAt(0);
          }
          _recentLogs
            ..clear()
            ..addAll(nextLogs);
          _emitDiagnostics(
            _currentDiagnostics.copyWith(
              recentLogs: List<String>.unmodifiable(nextLogs),
            ),
          );
        }),
    ]);
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

class _MpvOpenPlan {
  const _MpvOpenPlan({
    required this.mediaUri,
    required this.httpHeaders,
    required this.loadsAudioInsideMedia,
    required this.strategy,
  });

  final Uri mediaUri;
  final Map<String, String> httpHeaders;
  final bool loadsAudioInsideMedia;
  final String strategy;
}

@visibleForTesting
bool shouldForceSeekableForSource(PlaybackSource source) {
  if (source.url.host == '127.0.0.1' &&
      source.url.path.contains('/twitch-ad-guard/')) {
    return true;
  }
  return false;
}

@visibleForTesting
bool shouldInlineSplitHlsAudioIntoSource(PlaybackSource source) {
  // CB/mmcdn split LL-HLS is more stable when mpv demuxes audio + video inside
  // a single HLS session instead of attaching audio afterwards via audio-add.
  // This now applies to both legacy live-hls and v1/edge split LL-HLS, but we
  // keep single-source master localization restricted to true edge masters.
  return _looksLikeMmcdnSplitLowLatencyHlsSource(source) &&
      _sharedHttpHeadersForSplitHls(source) != null;
}

@visibleForTesting
bool shouldFallbackToSyntheticSplitMaster(PlaybackSource source) {
  // The simplified synthetic master drops LL-HLS attributes that the updated
  // /v1/edge streams depend on. Keep it only for older split-HLS layouts.
  return !_looksLikeMmcdnEdgeSplitHls(source.url);
}

@visibleForTesting
bool shouldUseAudioFilesPropertyForSource(PlaybackSource source) {
  // `audio-files` is a path-list option in mpv. Passing HTTPS URLs via the
  // string property API causes the URL to be tokenized as separate entries
  // (`https`, `//host/...`), which matches the "Can not open external file
  // https." failures seen in the latest Chaturbate logs. Keep split HLS audio
  // on either the synthetic master or runtime `audio-add` paths instead.
  return false;
}

Map<String, String>? _sharedHttpHeadersForSplitHls(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    return null;
  }
  if (source.headers.isEmpty && externalAudio.headers.isEmpty) {
    return const <String, String>{};
  }
  if (source.headers.isEmpty) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(externalAudio.headers),
    );
  }
  if (externalAudio.headers.isEmpty) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(source.headers),
    );
  }
  if (_sameHttpHeaders(source.headers, externalAudio.headers)) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(source.headers),
    );
  }
  return null;
}

bool _sameHttpHeaders(
  Map<String, String> left,
  Map<String, String> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
String buildSplitHlsMasterPlaylistContent(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    throw ArgumentError(
      'Split HLS master playlist requires an external audio source.',
    );
  }
  final audioLabel = _escapeHlsQuotedString(
    externalAudio.label?.trim().isNotEmpty == true
        ? externalAudio.label!.trim()
        : 'external',
  );
  final videoUrl = source.url.toString();
  final audioUrl = _escapeHlsQuotedString(externalAudio.url.toString());
  final bandwidth = _estimateSyntheticHlsBandwidth(source);
  return <String>[
    '#EXTM3U',
    '#EXT-X-VERSION:6',
    '#EXT-X-INDEPENDENT-SEGMENTS',
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="$audioLabel",DEFAULT=YES,AUTOSELECT=YES,URI="$audioUrl"',
    '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,AUDIO="audio"',
    videoUrl,
  ].join('\n');
}

@visibleForTesting
Future<File> writeSplitHlsMasterPlaylistFile(PlaybackSource source) async {
  final manifest = buildSplitHlsMasterPlaylistContent(source);
  return writeSyntheticHlsPlaylistFile(
    manifest,
    prefix: 'nolive-mpv-hls-',
    fileName: 'inline-master.m3u8',
  );
}

@visibleForTesting
Future<File?> maybeWriteResolvedSplitHlsMasterPlaylistFile(
  PlaybackSource source,
) async {
  final masterPlaylistUrl = source.masterPlaylistUrl;
  if (masterPlaylistUrl == null || source.externalAudio == null) {
    return null;
  }
  final embeddedManifest = source.masterPlaylistContent?.trim() ?? '';
  if (embeddedManifest.isNotEmpty) {
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: masterPlaylistUrl,
      manifest: embeddedManifest,
    );
    if (!rewritten.contains('#EXT-X-STREAM-INF:')) {
      return null;
    }
    final selectedManifest = buildResolvedSelectedSplitHlsMasterPlaylistContent(
      source: source,
      manifest: rewritten,
    );
    return writeSyntheticHlsPlaylistFile(
      selectedManifest,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-inline-master.m3u8',
    );
  }
  try {
    final manifest = await _fetchHlsManifest(
      masterPlaylistUrl,
      headers: _sharedHttpHeadersForSplitHls(source) ?? source.headers,
    );
    if (!manifest.contains('#EXT-X-STREAM-INF:')) {
      return null;
    }
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: masterPlaylistUrl,
      manifest: manifest,
    );
    final selectedManifest = buildResolvedSelectedSplitHlsMasterPlaylistContent(
      source: source,
      manifest: rewritten,
    );
    return writeSyntheticHlsPlaylistFile(
      selectedManifest,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-inline-master.m3u8',
    );
  } catch (_) {
    return null;
  }
}

@visibleForTesting
bool shouldRewriteSingleSourceHlsManifest(PlaybackSource source) {
  if (source.externalAudio != null || !_looksLikeHlsPlaylist(source.url)) {
    return false;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  return _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url) ||
      _looksLikeMmcdnEdgeLowLatencyMasterUri(manifestUri);
}

@visibleForTesting
String rewriteHlsManifestWithAbsoluteUris({
  required Uri playlistUri,
  required String manifest,
}) {
  return manifest
      .split('\n')
      .map((line) => _rewriteHlsManifestLine(
            playlistUri: playlistUri,
            line: line,
          ))
      .join('\n');
}

@visibleForTesting
String buildResolvedSelectedSplitHlsMasterPlaylistContent({
  required PlaybackSource source,
  required String manifest,
}) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    throw ArgumentError(
      'Resolved split HLS master playlist requires an external audio source.',
    );
  }
  final lines = manifest.split('\n');
  String? versionLine;
  var hasIndependentSegments = false;
  final audioLinesByGroupId = <String, String>{};
  String? matchedAudioLine;
  String? matchedStreamInfLine;
  String? matchedVideoUri;
  String? matchedAudioGroupId;

  for (var index = 0; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (versionLine == null && trimmed.startsWith('#EXT-X-VERSION:')) {
      versionLine = trimmed;
      continue;
    }
    if (trimmed == '#EXT-X-INDEPENDENT-SEGMENTS') {
      hasIndependentSegments = true;
      continue;
    }
    if (trimmed.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
      final audioGroupId =
          _extractHlsAttributeValue(trimmed, 'GROUP-ID')?.trim();
      if (audioGroupId != null && audioGroupId.isNotEmpty) {
        audioLinesByGroupId[audioGroupId] = trimmed;
      }
      final audioUri = _extractHlsAttributeValue(trimmed, 'URI');
      if (_hlsUrisMatch(audioUri, externalAudio.url.toString())) {
        matchedAudioLine = trimmed;
      }
      continue;
    }
    if (trimmed.startsWith('#EXT-X-STREAM-INF:')) {
      final videoUri = _nextHlsUriLine(lines, startIndex: index + 1);
      if (!_hlsUrisMatch(videoUri, source.url.toString())) {
        continue;
      }
      matchedStreamInfLine = trimmed;
      matchedVideoUri = videoUri;
      final audioGroupId = _extractHlsAttributeValue(trimmed, 'AUDIO')?.trim();
      if (audioGroupId != null && audioGroupId.isNotEmpty) {
        matchedAudioGroupId = audioGroupId;
      }
    }
  }

  if (matchedAudioGroupId != null && matchedAudioGroupId.isNotEmpty) {
    matchedAudioLine =
        audioLinesByGroupId[matchedAudioGroupId] ?? matchedAudioLine;
  }

  if (matchedAudioLine == null ||
      matchedStreamInfLine == null ||
      matchedVideoUri == null) {
    return buildSplitHlsMasterPlaylistContent(source);
  }

  return <String>[
    '#EXTM3U',
    versionLine ?? '#EXT-X-VERSION:6',
    if (hasIndependentSegments) '#EXT-X-INDEPENDENT-SEGMENTS',
    matchedAudioLine,
    matchedStreamInfLine,
    matchedVideoUri,
  ].join('\n');
}

@visibleForTesting
Future<File> writeSyntheticHlsPlaylistFile(
  String manifest, {
  required String prefix,
  required String fileName,
}) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(
    manifest,
    encoding: utf8,
    flush: true,
  );
  return file;
}

Future<File?> maybeWriteResolvedSingleSourceHlsPlaylistFile(
  PlaybackSource source,
) async {
  if (!shouldRewriteSingleSourceHlsManifest(source)) {
    return null;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  try {
    final manifest = await _fetchHlsManifest(
      manifestUri,
      headers: source.headers,
    );
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: manifestUri,
      manifest: manifest,
    );
    if (rewritten == manifest &&
        !shouldAlwaysLocalizeSingleSourceHlsManifest(source)) {
      return null;
    }
    return writeSyntheticHlsPlaylistFile(
      rewritten,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-master.m3u8',
    );
  } catch (_) {
    return null;
  }
}

@visibleForTesting
bool shouldAlwaysLocalizeSingleSourceHlsManifest(PlaybackSource source) {
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  return _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url) ||
      _looksLikeMmcdnEdgeLowLatencyMasterUri(manifestUri);
}

Future<String> _fetchHlsManifest(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Unexpected HLS manifest status ${response.statusCode}',
        uri: uri,
      );
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

const _hlsUriAttributePattern = r'URI=("([^"]*)"|([^,]+))';

String? _extractHlsAttributeValue(String line, String attribute) {
  final match = RegExp('$attribute=("([^"]*)"|([^,]+))').firstMatch(line);
  if (match == null) {
    return null;
  }
  return match.group(2) ?? match.group(3);
}

String? _nextHlsUriLine(List<String> lines, {required int startIndex}) {
  for (var index = startIndex; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    return trimmed;
  }
  return null;
}

bool _hlsUrisMatch(String? left, String? right) {
  final normalizedLeft = left?.trim() ?? '';
  final normalizedRight = right?.trim() ?? '';
  if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
    return false;
  }
  if (normalizedLeft == normalizedRight) {
    return true;
  }
  final leftKey = _canonicalHlsUriMatchKey(normalizedLeft);
  final rightKey = _canonicalHlsUriMatchKey(normalizedRight);
  if (leftKey != null && leftKey == rightKey) {
    return true;
  }
  final leftLeaf = _hlsUriLeafName(normalizedLeft);
  final rightLeaf = _hlsUriLeafName(normalizedRight);
  return leftLeaf.isNotEmpty && leftLeaf == rightLeaf;
}

String? _canonicalHlsUriMatchKey(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  final normalizedPairs = <String>[];
  final keys = uri.queryParametersAll.keys.toList()..sort();
  for (final key in keys) {
    final values = [...?uri.queryParametersAll[key]]..sort();
    if (values.isEmpty) {
      normalizedPairs.add(key);
      continue;
    }
    for (final value in values) {
      normalizedPairs.add('$key=$value');
    }
  }
  return '${uri.path}?${normalizedPairs.join('&')}';
}

String _hlsUriLeafName(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }
  final index = raw.lastIndexOf('/');
  if (index >= 0 && index + 1 < raw.length) {
    return raw.substring(index + 1);
  }
  return raw;
}

String _rewriteHlsManifestLine({
  required Uri playlistUri,
  required String line,
}) {
  final replacedAttributes = line.replaceAllMapped(
    RegExp(_hlsUriAttributePattern),
    (match) {
      final raw = match.group(2) ?? match.group(3) ?? '';
      if (raw.isEmpty) {
        return match.group(0) ?? '';
      }
      final resolved = playlistUri.resolve(raw).toString();
      if (match.group(2) != null) {
        return 'URI="${_escapeHlsQuotedString(resolved)}"';
      }
      return 'URI=$resolved';
    },
  );
  final trimmed = replacedAttributes.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return replacedAttributes;
  }
  return playlistUri.resolve(trimmed).toString();
}

@visibleForTesting
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

@visibleForTesting
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

@visibleForTesting
bool looksLikeMpvScreenshotFailureMessage(String message) {
  final normalized = message.trim().toLowerCase();
  return normalized.contains('taking screenshot failed') ||
      normalized
          .contains('error running command _command(screenshot-to-file') ||
      normalized.contains('error running command event:');
}

@visibleForTesting
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

@visibleForTesting
bool shouldStopBeforeOpeningNextSource(PlayerState state) {
  if (state.source != null) {
    return true;
  }
  return switch (state.status) {
    PlaybackStatus.buffering ||
    PlaybackStatus.playing ||
    PlaybackStatus.paused ||
    PlaybackStatus.completed ||
    PlaybackStatus.error =>
      true,
    _ => false,
  };
}

@visibleForTesting
({bool shouldStopBeforeOpen, Duration barrierDuration})
    resolveMpvOpenPreparation({
  required PlayerState previousState,
  required bool isAndroid,
}) {
  final shouldStopBeforeOpen = shouldStopBeforeOpeningNextSource(previousState);
  return (
    shouldStopBeforeOpen: shouldStopBeforeOpen,
    barrierDuration: resolveAndroidMpvOpenBarrierDuration(
      isAndroid: isAndroid,
      hasPreviousSource: shouldStopBeforeOpen,
    ),
  );
}

@visibleForTesting
Duration resolveAndroidMpvOpenBarrierDuration({
  required bool isAndroid,
  required bool hasPreviousSource,
}) {
  if (!isAndroid) {
    return Duration.zero;
  }
  return hasPreviousSource
      ? MpvPlayer._sourceSwitchStopSettleDelay
      : MpvPlayer._initialAndroidOpenSettleDelay;
}

@visibleForTesting
bool usesEmbeddedAndroidMediaCodecOutput({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
}) {
  final normalizedVideoOutput = videoOutputDriver.trim().toLowerCase();
  return compatMode ||
      (customOutputEnabled && normalizedVideoOutput == 'mediacodec_embed');
}

@visibleForTesting
bool shouldWarmAndroidMediaCodecOpenPath({
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool isAndroid,
}) {
  if (!isAndroid) {
    return false;
  }
  final normalizedVideoOutput = videoOutputDriver.trim().toLowerCase();
  final normalizedHardwareDecoder = hardwareDecoder.trim().toLowerCase();
  return normalizedHardwareDecoder.startsWith('mediacodec') ||
      normalizedVideoOutput == 'mediacodec_embed';
}

typedef AndroidEmbeddedSurfaceWarmupPolicy = ({
  Duration viewMountTimeout,
  Duration platformTimeout,
  Duration surfaceReadyBudget,
  Duration surfaceReadyPollInterval,
  Duration attachStabilizeTimeout,
});

typedef AndroidEmbeddedSurfaceWarmupResult = ({
  bool mounted,
  bool platformReady,
  bool surfaceReady,
  bool stabilized,
  int attempts,
  Duration elapsed,
  int? wid,
  int? textureId,
});

typedef AndroidSurfaceSnapshot = ({
  int wid,
  int textureId,
});

typedef AndroidSurfaceRefreshResult = ({
  AndroidSurfaceSnapshot currentSurface,
  bool changed,
  bool ready,
});

typedef AndroidOpenPreparationResult = ({
  AndroidSurfaceSnapshot previousSurface,
  bool deferPlayUntilSurfaceReady,
  bool shouldStopBeforeOpen,
});

typedef AndroidEmbeddedPlayGate = ({
  int generation,
  AndroidSurfaceSnapshot previousSurface,
  bool isInitialOpen,
});

@visibleForTesting
AndroidEmbeddedSurfaceWarmupPolicy resolveAndroidEmbeddedSurfaceWarmupPolicy({
  required bool isInitialOpen,
}) {
  return (
    viewMountTimeout: isInitialOpen
        ? MpvPlayer._androidInitialEmbeddedViewMountReadyTimeout
        : MpvPlayer._androidEmbeddedViewMountReadyTimeout,
    platformTimeout: isInitialOpen
        ? MpvPlayer._androidInitialEmbeddedPlatformReadyTimeout
        : MpvPlayer._androidEmbeddedPlatformReadyTimeout,
    surfaceReadyBudget: isInitialOpen
        ? MpvPlayer._androidInitialEmbeddedSurfaceReadyBudget
        : MpvPlayer._androidEmbeddedSurfaceReadyBudget,
    surfaceReadyPollInterval: isInitialOpen
        ? MpvPlayer._androidInitialEmbeddedSurfaceReadyPollInterval
        : MpvPlayer._androidEmbeddedSurfaceReadyPollInterval,
    attachStabilizeTimeout: isInitialOpen
        ? MpvPlayer._androidInitialEmbeddedSurfaceAttachStabilizeTimeout
        : MpvPlayer._androidEmbeddedSurfaceAttachStabilizeTimeout,
  );
}

@visibleForTesting
Future<bool> waitForVideoControllerTextureReady(
  ValueListenable<int?> textureId, {
  Duration timeout = const Duration(milliseconds: 350),
}) async {
  return waitForValueListenableValue<int?>(
    textureId,
    isReady: (value) => value != null && value > 0,
    timeout: timeout,
  );
}

@visibleForTesting
Future<bool> waitForVideoControllerPlatformReady(
  ValueListenable<Object?> platformNotifier, {
  Duration timeout = const Duration(milliseconds: 350),
}) {
  return waitForValueListenableValue<Object?>(
    platformNotifier,
    isReady: (value) => value != null,
    timeout: timeout,
  );
}

@visibleForTesting
ValueListenable<int?>? tryGetAndroidSurfaceHandleListenable(Object? platform) {
  if (platform == null) {
    return null;
  }
  try {
    final dynamic dynamicPlatform = platform;
    final candidate = dynamicPlatform.wid;
    if (candidate is ValueListenable<int?>) {
      return candidate;
    }
  } catch (_) {
    // Non-Android platform controllers do not expose `wid`.
  }
  return null;
}

@visibleForTesting
int? tryReadAndroidSurfaceHandle(Object? platform) {
  return tryGetAndroidSurfaceHandleListenable(platform)?.value;
}

@visibleForTesting
AndroidSurfaceSnapshot readAndroidSurfaceSnapshot({
  required Object? platform,
  ValueListenable<int?>? textureId,
}) {
  return (
    wid: tryReadAndroidSurfaceHandle(platform) ?? 0,
    textureId: textureId?.value ?? 0,
  );
}

@visibleForTesting
bool isAndroidSurfaceSnapshotReady(AndroidSurfaceSnapshot snapshot) {
  return snapshot.wid > 0 || snapshot.textureId > 0;
}

@visibleForTesting
bool isAndroidSurfaceSnapshotReadyForMediaCodec(
    AndroidSurfaceSnapshot snapshot) {
  return snapshot.wid > 0;
}

@visibleForTesting
bool didAndroidSurfaceSnapshotChange({
  required AndroidSurfaceSnapshot previous,
  required AndroidSurfaceSnapshot current,
}) {
  return previous.wid != current.wid || previous.textureId != current.textureId;
}

@visibleForTesting
Future<bool> waitForVideoControllerSurfaceReady({
  required VideoController controller,
  Duration timeout = const Duration(milliseconds: 350),
}) {
  final androidSurfaceHandle =
      tryGetAndroidSurfaceHandleListenable(controller.notifier.value);
  if (androidSurfaceHandle != null) {
    return waitForEitherValueListenableValue<int?>(
      primary: androidSurfaceHandle,
      secondary: controller.id,
      isReady: (value) => value != null && value > 0,
      timeout: timeout,
    );
  }
  return waitForVideoControllerTextureReady(
    controller.id,
    timeout: timeout,
  );
}

@visibleForTesting
Future<bool> waitForEitherValueListenableValue<T>({
  required ValueListenable<T> primary,
  required ValueListenable<T> secondary,
  required bool Function(T value) isReady,
  Duration timeout = const Duration(milliseconds: 350),
}) async {
  if (isReady(primary.value) || isReady(secondary.value)) {
    return true;
  }
  final completer = Completer<bool>();

  void tryComplete() {
    if (completer.isCompleted) {
      return;
    }
    if (isReady(primary.value) || isReady(secondary.value)) {
      completer.complete(true);
    }
  }

  primary.addListener(tryComplete);
  secondary.addListener(tryComplete);
  try {
    tryComplete();
    if (completer.isCompleted) {
      return true;
    }
    return await completer.future.timeout(timeout, onTimeout: () => false);
  } finally {
    primary.removeListener(tryComplete);
    secondary.removeListener(tryComplete);
  }
}

@visibleForTesting
Future<AndroidSurfaceRefreshResult> waitForFreshAndroidSurfacePublication({
  required Object? platform,
  required ValueListenable<int?> textureId,
  required AndroidSurfaceSnapshot previousSurface,
  Duration timeout = const Duration(milliseconds: 800),
  bool requireSurfaceHandle = false,
}) async {
  final widListenable = tryGetAndroidSurfaceHandleListenable(platform);
  final readinessPredicate = requireSurfaceHandle
      ? isAndroidSurfaceSnapshotReadyForMediaCodec
      : isAndroidSurfaceSnapshotReady;
  final currentSurface = readAndroidSurfaceSnapshot(
    platform: platform,
    textureId: textureId,
  );
  if (readinessPredicate(currentSurface) &&
      didAndroidSurfaceSnapshotChange(
        previous: previousSurface,
        current: currentSurface,
      )) {
    return (
      currentSurface: currentSurface,
      changed: true,
      ready: true,
    );
  }
  final completer = Completer<AndroidSurfaceRefreshResult>();

  void tryComplete() {
    if (completer.isCompleted) {
      return;
    }
    final nextSurface = readAndroidSurfaceSnapshot(
      platform: platform,
      textureId: textureId,
    );
    final changed = didAndroidSurfaceSnapshotChange(
      previous: previousSurface,
      current: nextSurface,
    );
    final ready = readinessPredicate(nextSurface);
    if (changed && ready) {
      completer.complete(
        (
          currentSurface: nextSurface,
          changed: changed,
          ready: ready,
        ),
      );
    }
  }

  widListenable?.addListener(tryComplete);
  textureId.addListener(tryComplete);
  try {
    tryComplete();
    if (completer.isCompleted) {
      return completer.future;
    }
    return await completer.future.timeout(
      timeout,
      onTimeout: () => (
        currentSurface: readAndroidSurfaceSnapshot(
          platform: platform,
          textureId: textureId,
        ),
        changed: false,
        ready: false,
      ),
    );
  } finally {
    widListenable?.removeListener(tryComplete);
    textureId.removeListener(tryComplete);
  }
}

@visibleForTesting
Future<bool> waitForAndroidSurfaceAttachStabilization(
  Object? platform, {
  Duration timeout = const Duration(milliseconds: 350),
}) async {
  if (platform == null) {
    return true;
  }
  try {
    final dynamic dynamicPlatform = platform;
    final dynamic lock = dynamicPlatform.lock;
    final result = lock.synchronized(() async {});
    if (result is Future) {
      await result.timeout(timeout);
    }
    return true;
  } on TimeoutException {
    return false;
  } catch (_) {
    return true;
  }
}

@visibleForTesting
Rect? tryReadAndroidSurfaceRect(Object? platform) {
  if (platform == null) {
    return null;
  }
  try {
    final dynamic dynamicPlatform = platform;
    final candidate = dynamicPlatform.rect;
    if (candidate is ValueListenable<Rect?>) {
      return candidate.value;
    }
    if (candidate is ValueListenable) {
      final value = candidate.value;
      if (value is Rect) {
        return value;
      }
    }
  } catch (_) {
    // Non-Android platform controllers may not expose `rect`.
  }
  return null;
}

@visibleForTesting
String? tryReadAndroidConfiguredVideoOutput(Object? platform) {
  if (platform == null) {
    return null;
  }
  try {
    final dynamic dynamicPlatform = platform;
    final configuration = dynamicPlatform.configuration;
    final candidate = configuration?.vo;
    if (candidate is String) {
      final trimmed = candidate.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
  } catch (_) {
    // Non-Android platform controllers may not expose `configuration.vo`.
  }
  return null;
}

String _effectiveAndroidRuntimeHardwareDecoder(
  MpvRuntimeConfiguration? runtimeConfiguration,
) {
  return runtimeConfiguration?.controllerConfiguration.hwdec?.trim() ?? '';
}

AndroidSurfaceSnapshot _surfaceSnapshotFromWarmupResult(
  AndroidEmbeddedSurfaceWarmupResult? result,
) {
  return (
    wid: result?.wid ?? 0,
    textureId: result?.textureId ?? 0,
  );
}

@visibleForTesting
bool shouldDelayAndroidEmbeddedPlayUntilSurfaceReady({
  required bool isInitialOpen,
  required AndroidSurfaceSnapshot previousSurface,
  required AndroidEmbeddedSurfaceWarmupResult? warmupResult,
}) {
  if (!isInitialOpen || warmupResult == null) {
    return false;
  }
  final currentSurface = _surfaceSnapshotFromWarmupResult(warmupResult);
  if (isAndroidSurfaceSnapshotReadyForMediaCodec(currentSurface)) {
    return false;
  }
  return !isAndroidSurfaceSnapshotReadyForMediaCodec(previousSurface);
}

@visibleForTesting
bool shouldReuseExistingAndroidSurfaceForReopen({
  required AndroidSurfaceSnapshot previousSurface,
  required AndroidSurfaceSnapshot currentSurface,
}) {
  if (!isAndroidSurfaceSnapshotReadyForMediaCodec(previousSurface)) {
    return false;
  }
  return !didAndroidSurfaceSnapshotChange(
        previous: previousSurface,
        current: currentSurface,
      ) &&
      isAndroidSurfaceSnapshotReadyForMediaCodec(currentSurface);
}

@visibleForTesting
String classifyAndroidMediaCodecDeviceFailureReason({
  required DateTime? lastOpeningDoneAt,
  required DateTime failureTimestamp,
  Duration reinitThreshold = const Duration(milliseconds: 50),
}) {
  if (lastOpeningDoneAt == null) {
    return 'mediacodec-device-creation-failed';
  }
  final delta = failureTimestamp.difference(lastOpeningDoneAt);
  if (delta > reinitThreshold) {
    return 'mpv-vd-reinit';
  }
  return 'mediacodec-device-creation-failed';
}

@visibleForTesting
Duration resolveAndroidEmbeddedHardwareDecoderReadyDelta({
  required DateTime surfaceReadyAt,
  required DateTime hardwareDecoderReadyAt,
}) {
  final delta = hardwareDecoderReadyAt.difference(surfaceReadyAt);
  return delta.isNegative ? Duration.zero : delta;
}

@visibleForTesting
Future<bool> rebindAndroidVideoControllerSurface(
  Object? platform, {
  Duration timeout = const Duration(milliseconds: 500),
}) async {
  if (platform == null) {
    return false;
  }
  final wid = tryReadAndroidSurfaceHandle(platform);
  final rect = tryReadAndroidSurfaceRect(platform);
  final configuredVo =
      tryReadAndroidConfiguredVideoOutput(platform)?.trim().toLowerCase() ??
          'null';
  final width = rect?.width.toInt() ?? 1;
  final height = rect?.height.toInt() ?? 1;
  final widValue = (wid ?? 0).toString();
  final voValue = widValue == '0' ? 'null' : configuredVo;
  final vidValue = widValue == '0' ? 'no' : 'auto';
  Future<void> apply(dynamic dynamicPlatform) async {
    await dynamicPlatform.setProperty('vo', 'null');
    await dynamicPlatform.setProperty(
      'android-surface-size',
      '${width}x$height',
    );
    await dynamicPlatform.setProperty('wid', widValue);
    await dynamicPlatform.setProperty('vo', voValue);
    if (configuredVo == 'mediacodec_embed') {
      await dynamicPlatform.setProperty('vid', vidValue);
    }
  }

  try {
    final dynamic dynamicPlatform = platform;
    final dynamic lock = dynamicPlatform.lock;
    if (lock != null) {
      final result = lock.synchronized(() => apply(dynamicPlatform));
      if (result is Future) {
        await result.timeout(timeout);
      }
    } else {
      await apply(dynamicPlatform).timeout(timeout);
    }
    return true;
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
Future<bool> waitForValueListenableValue<T>(
  ValueListenable<T> listenable, {
  required bool Function(T value) isReady,
  Duration timeout = const Duration(milliseconds: 350),
}) async {
  final current = listenable.value;
  if (isReady(current)) {
    return true;
  }
  final completer = Completer<bool>();
  void listener() {
    final value = listenable.value;
    if (isReady(value) && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  listenable.addListener(listener);
  try {
    final refreshed = listenable.value;
    if (isReady(refreshed)) {
      return true;
    }
    return await completer.future.timeout(timeout, onTimeout: () => false);
  } finally {
    listenable.removeListener(listener);
  }
}

@visibleForTesting
Map<String, String> resolveMpvSourcePlatformProperties({
  required PlaybackSource source,
  required bool doubleBufferingEnabled,
  String? hardwareDecoder,
  String? videoTrackSelection,
}) {
  final prefersChaturbateProxyStableBuffer =
      source.bufferProfile == PlaybackBufferProfile.chaturbateLlHlsProxyStable;
  final prefersChaturbateDirectStableFallback =
      prefersChaturbateProxyStableBuffer &&
          !_looksLikeChaturbateLoopbackProxySource(source);
  final prefersEdgeLowLatencyHls =
      source.bufferProfile == PlaybackBufferProfile.edgeLowLatencyHls;
  final prefersStableSplitEdgeHls = prefersEdgeLowLatencyHls &&
      _looksLikeMmcdnSplitLowLatencyHlsSource(source);
  final prefersLocalizedSplitEdgeMaster = prefersStableSplitEdgeHls &&
      shouldInlineSplitHlsAudioIntoSource(source) &&
      (source.masterPlaylistUrl != null ||
          (source.masterPlaylistContent?.trim().isNotEmpty ?? false));
  final prefersStableMasterEdgeHls = prefersEdgeLowLatencyHls &&
      source.externalAudio == null &&
      _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url);
  final inlinesStableSplitEdgeHls =
      prefersStableSplitEdgeHls && shouldInlineSplitHlsAudioIntoSource(source);
  final prefersStableBuffer =
      source.bufferProfile == PlaybackBufferProfile.heavyStreamStable;
  final normalizedHardwareDecoder = hardwareDecoder?.trim() ?? '';
  final normalizedVideoTrackSelection = videoTrackSelection?.trim() ?? '';
  final properties = <String, String>{
    'force-seekable': shouldForceSeekableForSource(source) ? 'yes' : 'no',
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
    if (prefersStableSplitEdgeHls || prefersStableMasterEdgeHls) {
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
            : prefersStableMasterEdgeHls
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
        // Start from the very last segment (live_start_index=-1) to avoid
        // starting too far behind the live edge, which causes a cascade of
        // `expired from playlists` skips and PTS discontinuities.
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
  } else if (prefersStableBuffer) {
    properties.addAll(const <String, String>{
      'cache': 'yes',
      'cache-secs': '10',
      'demuxer-seekable-cache': 'yes',
      'demuxer-donate-buffer': 'yes',
      'demuxer-max-back-bytes': '67108864',
      'demuxer-max-bytes': '67108864',
      'demuxer-readahead-secs': '10',
    });
  } else {
    properties.addAll(<String, String>{
      'cache': 'yes',
      'cache-secs': doubleBufferingEnabled ? '3' : '2',
      'demuxer-seekable-cache': doubleBufferingEnabled ? 'yes' : 'no',
      'demuxer-donate-buffer': doubleBufferingEnabled ? 'yes' : 'no',
      'demuxer-max-back-bytes':
          doubleBufferingEnabled ? '33554432' : '16777216',
      'demuxer-max-bytes': doubleBufferingEnabled ? '33554432' : '16777216',
      'demuxer-readahead-secs': doubleBufferingEnabled ? '3' : '2',
      if (!doubleBufferingEnabled) 'cache-pause': 'no',
      if (!doubleBufferingEnabled) 'cache-pause-wait': '1',
      if (!doubleBufferingEnabled) 'cache-pause-initial': 'no',
    });
  }
  properties['load-unsafe-playlists'] =
      shouldAllowUnsafePlaylistsForSource(source) ? 'yes' : 'no';
  final normalizedHlsBitrate = source.hlsBitrate?.trim() ?? '';
  if (prefersChaturbateProxyStableBuffer || prefersLocalizedSplitEdgeMaster) {
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

@visibleForTesting
MpvRuntimeConfiguration resolveMpvRuntimeConfiguration({
  required bool enableHardwareAcceleration,
  required bool compatMode,
  required bool doubleBufferingEnabled,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  required String hardwareDecoder,
  required bool logEnabled,
}) {
  final sanitizedVideoOutputDriver = videoOutputDriver.trim().isEmpty
      ? MpvPlayer._fallbackVideoOutputDriver
      : videoOutputDriver.trim();
  final sanitizedHardwareDecoder = hardwareDecoder.trim().isEmpty
      ? MpvPlayer._fallbackHardwareDecoder
      : hardwareDecoder.trim();
  final attachAfterVideoParameters = _resolveAndroidAttachSurfaceTiming(
    compatMode: compatMode,
    customOutputEnabled: customOutputEnabled,
    videoOutputDriver: sanitizedVideoOutputDriver,
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
              androidAttachSurfaceAfterVideoParameters:
                  attachAfterVideoParameters,
            )
          : VideoControllerConfiguration(
              enableHardwareAcceleration: enableHardwareAcceleration,
              hwdec:
                  enableHardwareAcceleration ? sanitizedHardwareDecoder : 'no',
            );
  final platformProperties = <String, String>{
    'cache': 'yes',
    'cache-secs': doubleBufferingEnabled ? '3' : '2',
    'demuxer-seekable-cache': doubleBufferingEnabled ? 'yes' : 'no',
    'demuxer-donate-buffer': doubleBufferingEnabled ? 'yes' : 'no',
    'demuxer-max-back-bytes': doubleBufferingEnabled ? '33554432' : '16777216',
    'demuxer-max-bytes': doubleBufferingEnabled ? '33554432' : '16777216',
    'demuxer-readahead-secs': doubleBufferingEnabled ? '3' : '2',
    'cache-on-disk': 'no',
    if (!doubleBufferingEnabled) 'cache-pause': 'no',
    if (!doubleBufferingEnabled) 'cache-pause-wait': '1',
    if (!doubleBufferingEnabled) 'cache-pause-initial': 'no',
  };
  return MpvRuntimeConfiguration(
    controllerConfiguration: controllerConfiguration,
    logLevel: logEnabled ? mk.MPVLogLevel.debug : mk.MPVLogLevel.error,
    platformProperties: platformProperties,
    androidOutputFallbackReason: null,
  );
}

@visibleForTesting
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

@visibleForTesting
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

bool _looksLikeHlsPlaylist(Uri uri) {
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.contains('chunklist_')) {
    return true;
  }
  return uri.queryParameters.values.any(
    (value) => value.toLowerCase().contains('.m3u8'),
  );
}

bool _looksLikeLiveHlsSource(PlaybackSource source) {
  if (_looksLikeHlsPlaylist(source.url)) {
    return true;
  }
  final externalAudio = source.externalAudio;
  return externalAudio != null && _looksLikeHlsPlaylist(externalAudio.url);
}

bool _isMmcdnHlsUri(Uri uri) {
  return uri.host.toLowerCase().endsWith('live.mmcdn.com') &&
      _looksLikeHlsPlaylist(uri);
}

bool _looksLikeMmcdnEdgeSplitHls(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.contains('/v1/edge/streams/') &&
      path.contains('chunklist_') &&
      path.endsWith('.m3u8');
}

bool _looksLikeMmcdnLowLatencyHlsUri(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  if (path.contains('/v1/edge/streams/')) {
    return path.contains('llhls') || path.endsWith('/llhls.m3u8');
  }
  if (path.contains('/live-hls/amlst:')) {
    return _looksLikeLowLatencyChunklist(uri);
  }
  return false;
}

class _MpvEmbeddedViewHost extends StatefulWidget {
  const _MpvEmbeddedViewHost({
    required this.mountedListenable,
    required this.child,
  });

  final ValueNotifier<bool> mountedListenable;
  final Widget child;

  @override
  State<_MpvEmbeddedViewHost> createState() => _MpvEmbeddedViewHostState();
}

class _MpvEmbeddedViewHostState extends State<_MpvEmbeddedViewHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.mountedListenable.value = true;
    });
  }

  @override
  void dispose() {
    widget.mountedListenable.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

bool _looksLikeChaturbateLoopbackProxySource(PlaybackSource source) {
  final uri = source.url;
  final host = uri.host.toLowerCase();
  final isLoopback = host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';
  return isLoopback && uri.path.contains('/chaturbate-llhls/');
}

bool _looksLikeMmcdnEdgeLowLatencyMasterUri(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.contains('/v1/edge/streams/') && path.endsWith('/llhls.m3u8');
}

bool _looksLikeMmcdnSplitLowLatencyHlsSource(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    return false;
  }
  return _looksLikeMmcdnLowLatencyHlsUri(source.url) &&
      _looksLikeMmcdnLowLatencyHlsUri(externalAudio.url) &&
      _looksLikeLowLatencyChunklist(source.url) &&
      _looksLikeLowLatencyChunklist(externalAudio.url);
}

@visibleForTesting
bool shouldAllowUnsafePlaylistsForSource(PlaybackSource source) {
  if (_isMmcdnHlsUri(source.url)) {
    return true;
  }
  final externalAudio = source.externalAudio;
  return externalAudio != null && _isMmcdnHlsUri(externalAudio.url);
}

bool _looksLikeLiveFlv(Uri uri) {
  final path = uri.path.toLowerCase();
  if (path.endsWith('.flv') || path.contains('/live-bvc/')) {
    return true;
  }
  return uri.queryParameters.values.any(
    (value) => value.toLowerCase().contains('.flv'),
  );
}

bool _looksLikeLowLatencyChunklist(Uri uri) {
  final path = uri.path.toLowerCase();
  if (path.contains('chunklist_') || path.contains('llhls')) {
    return true;
  }
  return uri.queryParameters.keys.any(
        (key) => key.toLowerCase().contains('llhls'),
      ) ||
      uri.queryParameters.values.any(
        (value) => value.toLowerCase().contains('llhls'),
      );
}

int _estimateSyntheticHlsBandwidth(PlaybackSource source) {
  final candidates = <int>[
    _extractBandwidthFromUri(source.url),
    if (source.externalAudio != null)
      _extractBandwidthFromUri(source.externalAudio!.url),
  ].where((item) => item > 0);
  final total = candidates.fold<int>(0, (sum, item) => sum + item);
  return total > 0 ? total : 1;
}

int _extractBandwidthFromUri(Uri uri) {
  final queryBandwidth = int.tryParse(uri.queryParameters['bandwidth'] ?? '') ??
      int.tryParse(uri.queryParameters['bw'] ?? '');
  if (queryBandwidth != null && queryBandwidth > 0) {
    return queryBandwidth;
  }
  final path = uri.path.toLowerCase();
  final match = RegExp(r'(?:^|[_-])b(\d+)(?:[_-]|$)').firstMatch(path);
  final pathBandwidth = int.tryParse(match?.group(1) ?? '');
  return pathBandwidth != null && pathBandwidth > 0 ? pathBandwidth : 0;
}

String _escapeHlsQuotedString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
