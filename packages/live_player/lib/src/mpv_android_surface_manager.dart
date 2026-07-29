part of 'mpv_player.dart';

const MethodChannel _androidVideoOutputChannel = MethodChannel(
  'com.alexmercerind/media_kit_video',
);

typedef AndroidVideoOutputSurfacePrimeInvoker =
    Future<void> Function(String method, Map<String, String> arguments);

class MpvAndroidSurfaceManager {
  const MpvAndroidSurfaceManager();

  AndroidEmbeddedSurfaceWarmupPolicy resolveWarmupPolicy({
    required bool isInitialOpen,
  }) {
    return resolveAndroidEmbeddedSurfaceWarmupPolicy(
      isInitialOpen: isInitialOpen,
    );
  }

  Future<bool> waitForTextureReady(
    ValueListenable<int?> textureId, {
    Duration timeout = const Duration(milliseconds: 350),
  }) {
    return waitForVideoControllerTextureReady(textureId, timeout: timeout);
  }
}

extension MpvPlayerAndroidSurfaceLifecycle on MpvPlayer {
  Future<bool> _waitForAndroidSurfaceBeforeInitialOpen({
    required AndroidSurfaceSnapshot previousSurface,
  }) async {
    if (!isAndroid) {
      return true;
    }
    final controller = _controller;
    if (controller == null) {
      return true;
    }
    final platform = controller.notifier.value;
    if (platform == null) {
      return true;
    }
    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: controller.id,
      previousSurface: previousSurface,
      timeout: MpvPlayer._androidInitialEmbeddedPlaySurfaceReadyTimeout,
      requireSurfaceHandle: true,
    );
    if (_isClosedForOperations) {
      return true;
    }
    if (refresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: MpvPlayer._androidEmbeddedSurfaceAttachStabilizeTimeout,
      );
      await _awaitAndroidEmbeddedSurfaceFrames();
      _logEvent(
        'setSource surface-ready before-open '
        'wid=${refresh.currentSurface.wid} '
        'texture=${refresh.currentSurface.textureId}',
      );
      return true;
    }
    final lateRefresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: controller.id,
      previousSurface: refresh.currentSurface,
      timeout: MpvPlayer._androidInitialEmbeddedPlaySurfaceFallbackTimeout,
      requireSurfaceHandle: true,
    );
    if (_isClosedForOperations) {
      return true;
    }
    if (lateRefresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: MpvPlayer._androidEmbeddedSurfaceAttachStabilizeTimeout,
      );
      await _awaitAndroidEmbeddedSurfaceFrames();
      _logEvent(
        'setSource surface-ready before-open late=true '
        'wid=${lateRefresh.currentSurface.wid} '
        'texture=${lateRefresh.currentSurface.textureId}',
      );
      return true;
    }
    _logEvent(
      'setSource surface still pending before open '
      'wid=${lateRefresh.currentSurface.wid} '
      'texture=${lateRefresh.currentSurface.textureId}',
    );
    return false;
  }

  Future<bool> _awaitAndroidEmbeddedPlayGateIfNeeded() async {
    if (!isAndroid) {
      return true;
    }
    final gate = _pendingAndroidEmbeddedPlayGate;
    if (gate == null) {
      return true;
    }
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return true;
    }
    final controller = _controller;
    final platform = controller?.notifier.value;
    if (controller == null || platform == null) {
      _pendingAndroidEmbeddedPlayGate = null;
      return true;
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
      timeout: MpvPlayer._androidInitialEmbeddedPlaySurfaceReadyTimeout,
      requireSurfaceHandle: true,
    );
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return true;
    }
    if (refresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: MpvPlayer._androidEmbeddedSurfaceAttachStabilizeTimeout,
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
      return true;
    }
    final lateRefresh = await waitForFreshAndroidSurfacePublication(
      platform: platform,
      textureId: controller.id,
      previousSurface: refresh.currentSurface,
      timeout: MpvPlayer._androidInitialEmbeddedPlaySurfaceFallbackTimeout,
      requireSurfaceHandle: true,
    );
    if (gate.generation != _androidEmbeddedPlayGateGeneration ||
        _isClosedForOperations) {
      _pendingAndroidEmbeddedPlayGate = null;
      return true;
    }
    if (lateRefresh.ready) {
      await waitForAndroidSurfaceAttachStabilization(
        platform,
        timeout: MpvPlayer._androidEmbeddedSurfaceAttachStabilizeTimeout,
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
      return true;
    }
    _logEvent(
      'play gate surface-timeout '
      'initial=${gate.isInitialOpen} '
      'wid=${lateRefresh.currentSurface.wid} '
      'texture=${lateRefresh.currentSurface.textureId}',
    );
    _emitDiagnostics(
      _currentDiagnostics.copyWith(error: kMpvAndroidSurfaceTimeoutError),
    );
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.error,
        errorMessage: kMpvAndroidSurfaceTimeoutError,
      ),
    );
    _pendingAndroidEmbeddedPlayGate = null;
    return false;
  }

  Future<void> _awaitAndroidEmbeddedHardwareDecoderReadyIfNeeded({
    required DateTime surfaceReadyAt,
  }) async {
    if (!isAndroid) {
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
        MpvPlayer._androidEmbeddedHardwareDecoderReadyTimeout,
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
        'play gate hw-ready timeout=${MpvPlayer._androidEmbeddedHardwareDecoderReadyTimeout.inMilliseconds}ms '
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
        // Give MediaCodec time to return dequeued GraphicBuffers before the
        // next open rebinds the surface (reduces freeAllBuffers-while-dequeued).
        if (isAndroid) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
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
      await _awaitAndroidEmbeddedSurfaceRefreshForReopen(previousSurface);
    }
    final warmupResult = await _awaitAndroidEmbeddedSurfaceReadyForOpen(
      isInitialOpen: isInitialOpen,
    );
    final deferPlayUntilSurfaceReady =
        shouldDelayAndroidEmbeddedPlayUntilSurfaceReady(
          isInitialOpen: isInitialOpen,
          previousSurface: previousSurface,
          warmupResult: warmupResult,
        );
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
    if (!isAndroid) {
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
      timeout: MpvPlayer._androidEmbeddedPlatformReadyTimeout,
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
      return (currentSurface: currentSurface, changed: false, ready: true);
    }
    final refresh = await waitForFreshAndroidSurfacePublication(
      platform: controller.notifier.value,
      textureId: controller.id,
      previousSurface: previousSurface,
      timeout: MpvPlayer._androidReopenFreshSurfaceWaitBudget,
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
    if (!isAndroid) {
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
    final policy =
        warmupPolicy ??
        resolveAndroidEmbeddedSurfaceWarmupPolicy(isInitialOpen: isInitialOpen);
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
        final currentSurface = readAndroidSurfaceSnapshot(
          platform: controller.notifier.value,
          textureId: controller.id,
        );
        if (!isAndroidSurfaceSnapshotReadyForMediaCodec(currentSurface)) {
          await _primeAndroidEmbeddedSurfaceForOpen(controller.player);
        }
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
            requireSurfaceHandle: true,
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
    final currentWid = tryReadAndroidSurfaceHandle(controller.notifier.value);
    final currentTextureId = controller.id.value;
    final currentPlatform = controller.notifier.value;
    final hasWidNotifier =
        tryGetAndroidSurfaceHandleListenable(currentPlatform) != null;
    final platformType = currentPlatform == null
        ? 'null'
        : currentPlatform.runtimeType.toString();
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
        'platform=$platformType widNotifier=$hasWidNotifier '
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
      'platform=$platformType widNotifier=$hasWidNotifier '
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

  Future<bool> _primeAndroidEmbeddedSurfaceForOpen(mk.Player player) async {
    if (!isAndroid) {
      return false;
    }
    try {
      final handle = await player.handle;
      final primeSize = resolveAndroidSurfacePrimeSize(
        isArcChromeOs: looksLikeArcChromeOsRuntime(),
      );
      _arcLastSurfacePrimeSize = primeSize;
      final primed = await primeAndroidVideoOutputSurface(
        playerHandle: handle,
        width: primeSize.width,
        height: primeSize.height,
      );
      _logEvent(
        'setSource surface-prime ${primed ? 'requested' : 'failed'} '
        'handle=$handle width=${primeSize.width} height=${primeSize.height} '
        'arc=${looksLikeArcChromeOsRuntime()}',
      );
      return primed;
    } catch (error) {
      _logEvent('setSource surface-prime failed error=$error');
      return false;
    }
  }
}

/// Phone keeps the historical tiny prime (forces Surface creation without
/// allocating a full frame).
///
/// ARC production default is mediacodec-copy, which skips the MediaCodec
/// surface warm path — so this prime is unused for the default tier. Any fixed
/// prime size (window / 1080p / 2K) is resolution-coupled and wrong as a
/// product default. Do not re-introduce a fixed ARC prime.
///
/// Experimental zero-copy must prime to the **actual stream** size known before
/// open, never a guessed resolution.
@visibleForTesting
({int width, int height}) resolveAndroidSurfacePrimeSize({
  required bool isArcChromeOs,
  Size? logicalViewSize,
  Size? primaryViewLogicalSize,
  int? knownStreamWidth,
  int? knownStreamHeight,
}) {
  if (!isArcChromeOs) {
    return (width: 2, height: 2);
  }
  // Only safe prime: exact stream dimensions when already known.
  final sw = knownStreamWidth ?? 0;
  final sh = knownStreamHeight ?? 0;
  if (sw >= 64 && sh >= 64) {
    return (width: sw & ~1, height: sh & ~1);
  }
  // No known stream size: do not guess 720/1080/2K. Tiny prime is still used
  // only as a last-resort Surface create; ARC default software avoids this path.
  assert(() {
    logicalViewSize;
    primaryViewLogicalSize;
    return true;
  }());
  return (width: 2, height: 2);
}

/// True when media_kit will call SetSurfaceSize for a different frame size.
@visibleForTesting
bool arcSurfacePrimeMismatchesStream({
  required int primeWidth,
  required int primeHeight,
  required int streamWidth,
  required int streamHeight,
}) {
  if (streamWidth <= 0 || streamHeight <= 0) {
    return false;
  }
  return primeWidth != streamWidth || primeHeight != streamHeight;
}

@visibleForTesting
Size? readPrimaryFlutterViewLogicalSize() {
  if (kIsWeb) {
    return null;
  }
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) {
    return null;
  }
  final dpr = view.devicePixelRatio;
  if (dpr <= 0) {
    return null;
  }
  final physical = view.physicalSize;
  if (physical.width <= 0 || physical.height <= 0) {
    return null;
  }
  return Size(physical.width / dpr, physical.height / dpr);
}

bool shouldStopBeforeOpeningNextSource(PlayerState state) {
  if (state.source != null) {
    return true;
  }
  return switch (state.status) {
    PlaybackStatus.buffering ||
    PlaybackStatus.playing ||
    PlaybackStatus.paused ||
    PlaybackStatus.completed ||
    PlaybackStatus.error => true,
    _ => false,
  };
}

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

bool usesEmbeddedAndroidMediaCodecOutput({
  required bool compatMode,
  required bool customOutputEnabled,
  required String videoOutputDriver,
  bool enableHardwareAcceleration = true,
  String hardwareDecoder = 'auto-safe',
}) {
  final normalizedVideoOutput = videoOutputDriver.trim().toLowerCase();
  final normalizedHardwareDecoder = hardwareDecoder.trim().toLowerCase();

  final isDirectMediaCodec =
      enableHardwareAcceleration &&
      ((normalizedHardwareDecoder.startsWith('mediacodec') &&
              !normalizedHardwareDecoder.endsWith('-copy')) ||
          normalizedHardwareDecoder == 'auto' ||
          normalizedHardwareDecoder == 'auto-safe');

  return compatMode ||
      (customOutputEnabled && normalizedVideoOutput == 'mediacodec_embed') ||
      (!customOutputEnabled && isDirectMediaCodec);
}

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

  final isDirectMediaCodec =
      (normalizedHardwareDecoder.startsWith('mediacodec') &&
          !normalizedHardwareDecoder.endsWith('-copy')) ||
      normalizedHardwareDecoder == 'auto' ||
      normalizedHardwareDecoder == 'auto-safe';

  return isDirectMediaCodec || normalizedVideoOutput == 'mediacodec_embed';
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

typedef AndroidSurfaceSnapshot = ({int wid, int textureId});

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

int? tryReadAndroidSurfaceHandle(Object? platform) {
  return tryGetAndroidSurfaceHandleListenable(platform)?.value;
}

AndroidSurfaceSnapshot readAndroidSurfaceSnapshot({
  required Object? platform,
  ValueListenable<int?>? textureId,
}) {
  return (
    wid: tryReadAndroidSurfaceHandle(platform) ?? 0,
    textureId: textureId?.value ?? 0,
  );
}

bool isAndroidSurfaceSnapshotReady(AndroidSurfaceSnapshot snapshot) {
  return snapshot.wid > 0 || snapshot.textureId > 0;
}

bool isAndroidSurfaceSnapshotReadyForMediaCodec(
  AndroidSurfaceSnapshot snapshot,
) {
  // Phone Android: wid-only is correct (texture often logs as 0 while playback
  // is fine). Do not tighten this for all platforms.
  return snapshot.wid > 0;
}

/// ChromeOS ARC reports versions like `R149-16667.55.0` via
/// [Platform.operatingSystemVersion]. Phone firmwares (e.g. Sony
/// `58.2.B.0.520`) do not match.
bool looksLikeArcChromeOsRuntime({
  String? operatingSystemVersion,
  bool? isAndroidPlatform,
}) {
  final android =
      isAndroidPlatform ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  if (!android) {
    return false;
  }
  final version =
      (operatingSystemVersion ??
              (!kIsWeb ? Platform.operatingSystemVersion : ''))
          .trim();
  if (version.isEmpty) {
    return false;
  }
  return RegExp(r'^R\d{2,4}-\d+').hasMatch(version);
}

bool didAndroidSurfaceSnapshotChange({
  required AndroidSurfaceSnapshot previous,
  required AndroidSurfaceSnapshot current,
}) {
  return previous.wid != current.wid || previous.textureId != current.textureId;
}

Future<bool> waitForVideoControllerSurfaceReady({
  required VideoController controller,
  Duration timeout = const Duration(milliseconds: 350),
  bool requireSurfaceHandle = false,
}) {
  final androidSurfaceHandle = tryGetAndroidSurfaceHandleListenable(
    controller.notifier.value,
  );
  if (androidSurfaceHandle != null) {
    if (requireSurfaceHandle) {
      return waitForValueListenableValue<int?>(
        androidSurfaceHandle,
        isReady: (value) => value != null && value > 0,
        timeout: timeout,
      );
    }
    return waitForEitherValueListenableValue<int?>(
      primary: androidSurfaceHandle,
      secondary: controller.id,
      isReady: (value) => value != null && value > 0,
      timeout: timeout,
    );
  }
  return waitForVideoControllerTextureReady(controller.id, timeout: timeout);
}

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
    return (currentSurface: currentSurface, changed: true, ready: true);
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
      completer.complete((
        currentSurface: nextSurface,
        changed: changed,
        ready: ready,
      ));
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

Future<bool> primeAndroidVideoOutputSurface({
  required int playerHandle,
  int width = 1,
  int height = 1,
  AndroidVideoOutputSurfacePrimeInvoker? invoke,
}) async {
  if (playerHandle == 0 || width <= 0 || height <= 0) {
    return false;
  }
  try {
    final call =
        invoke ??
        (String method, Map<String, String> arguments) {
          return _androidVideoOutputChannel.invokeMethod<void>(
            method,
            arguments,
          );
        };
    await call('VideoOutputManager.SetSurfaceSize', <String, String>{
      'handle': playerHandle.toString(),
      'width': width.toString(),
      'height': height.toString(),
    });
    return true;
  } catch (_) {
    return false;
  }
}

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
  return (wid: result?.wid ?? 0, textureId: result?.textureId ?? 0);
}

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

Duration resolveAndroidEmbeddedHardwareDecoderReadyDelta({
  required DateTime surfaceReadyAt,
  required DateTime hardwareDecoderReadyAt,
}) {
  final delta = hardwareDecoderReadyAt.difference(surfaceReadyAt);
  return delta.isNegative ? Duration.zero : delta;
}

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
