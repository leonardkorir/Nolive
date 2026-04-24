import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;

import 'base_player.dart';
import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';

class MdkPlayer implements BasePlayer {
  MdkPlayer({
    this.lowLatency = true,
    this.androidTunnel = false,
    this.androidPreferHardwareVideoDecoder = true,
    this.debugLogEnabled = kDebugMode,
    this.eventLogger,
  });

  static const Duration _updateTextureTimeout = Duration(seconds: 3);
  static const Duration _stopWaitTimeout = Duration(milliseconds: 1200);
  static const Duration _releaseTextureTimeout = Duration(milliseconds: 1200);
  static const Duration _tunnelFirstFrameTimeout = Duration(milliseconds: 1200);
  static const Duration _lowBufferWarningThreshold =
      Duration(milliseconds: 250);
  static const Duration _runtimeDiagnosticsPollInterval = Duration(seconds: 1);
  static const int _maxRecentLogs = 24;

  final bool lowLatency;
  final bool androidTunnel;
  final bool androidPreferHardwareVideoDecoder;
  final bool debugLogEnabled;
  final void Function(String message)? eventLogger;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final Queue<String> _recentLogs = ListQueue<String>();

  mdk.Player? _player;
  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mdk);
  PlayerDiagnostics _currentDiagnostics = const PlayerDiagnostics(
    backend: PlayerBackend.mdk,
  );
  bool _initialized = false;
  Timer? _progressTimer;
  int _requestSerialCounter = 0;
  int _activeRequestSerial = 0;
  int _activeEventSerial = 0;
  bool _firstFrameRendered = false;
  bool _lowBufferWarningActive = false;
  int _rebufferCount = 0;
  DateTime? _rebufferStartedAt;
  Duration? _lastRebufferDuration;
  Timer? _tunnelFirstFrameWatchdog;
  bool _tunnelFallbackAttempted = false;

  @override
  PlayerBackend get backend => PlayerBackend.mdk;

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
    if (_initialized) {
      return;
    }
    _logEvent('initialize start');
    _emit(_currentState.copyWith(status: PlaybackStatus.initializing));
    final registerOptions = resolveMdkRegisterOptions(
      lowLatency: lowLatency,
      androidTunnel: androidTunnel,
    );
    fvp.registerWith(options: registerOptions);
    _logEvent(
      'registerWith '
      'platforms=windows,macos,linux,android,ios '
      'lowLatency=${registerOptions['lowLatency'] ?? 0} '
      'tunnel=$androidTunnel',
    );
    final player = mdk.Player();
    _player = player;
    _bindPlayer(player);
    _initialized = true;
    _emitDiagnostics(
      PlayerDiagnostics.empty(backend).copyWith(
        lowLatencyMode: lowLatency,
        debugLogEnabled: debugLogEnabled,
        recentLogs: debugLogEnabled ? _snapshotRecentLogs() : const <String>[],
      ),
    );
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
    _logEvent('initialize ready');
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    await initialize();
    final player = _player;
    if (player == null) {
      return;
    }
    final requestSerial = _beginSourceRequest();
    _logEvent(
      'setSource request=$requestSerial '
      'video=${_shortSourceDescriptor(source.url)} '
      'audio=${source.externalAudio == null ? '-' : _shortSourceDescriptor(source.externalAudio!.url)} '
      'bufferProfile=${source.bufferProfile.name} '
      'lowLatency=$lowLatency tunnel=$androidTunnel',
    );
    if (player.state != mdk.PlaybackState.stopped) {
      final stopped = _waitForStopped(player, context: 'setSource pre-stop');
      _logEvent('setSource pre-stop done stopped=$stopped');
      if (!_isRequestActive(requestSerial, player)) {
        _logStaleRequest(requestSerial, player, 'after-pre-stop');
        return;
      }
    }
    await _releaseTextureIfNeeded(player, context: 'setSource reset-texture');
    if (!_isRequestActive(requestSerial, player)) {
      _logStaleRequest(requestSerial, player, 'after-reset-texture');
      return;
    }

    player.setProperty('video.decoder', 'shader_resource=0');
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avformat.safe', '0');
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '7');
    player.setProperty('avformat.rtsp_transport', 'tcp');
    player.setProperty('avformat.extension_picky', '0');
    player.setProperty('avformat.allowed_segment_extensions', 'ALL');
    player.setProperty(
      'avio.protocol_whitelist',
      'file,ftp,rtmp,http,https,tls,rtp,tcp,udp,crypto,httpproxy,data,concatf,concat,subfile',
    );
    final bufferStrategy = resolveMdkBufferStrategy(
      lowLatency: lowLatency,
      bufferProfile: source.bufferProfile,
    );
    if (lowLatency) {
      player.setProperty('avformat.fpsprobesize', '0');
      player.setProperty('avformat.analyzeduration', '100000');
    }
    final preferredVideoDecoders = resolveMdkPreferredVideoDecoders(
      preferHardwareVideoDecoder: androidPreferHardwareVideoDecoder,
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );
    if (preferredVideoDecoders != null) {
      player.videoDecoders = preferredVideoDecoders;
      _logEvent(
        'setSource preferredVideoDecoders=${preferredVideoDecoders.join(',')}',
      );
    }
    player.setBufferRange(
      min: bufferStrategy.minMs,
      max: bufferStrategy.maxMs,
      drop: bufferStrategy.drop,
    );
    if (source.bufferProfile == PlaybackBufferProfile.heavyStreamStable) {
      _logEvent(
        'setSource heavy-stream buffer profile active '
        'profile=${source.bufferProfile.name}',
      );
    }
    _logEvent(
      'setSource bufferStrategy '
      'profile=${source.bufferProfile.name} '
      'lowLatency=$lowLatency '
      'minMs=${bufferStrategy.minMs} '
      'maxMs=${bufferStrategy.maxMs} '
      'drop=${bufferStrategy.drop}',
    );

    if (source.headers.isNotEmpty) {
      final headerString = source.headers.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\r\n');
      player.setProperty('avio.headers', headerString);
    }

    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.buffering,
        source: source,
        clearErrorMessage: true,
      ),
    );
    _emitDiagnostics(_currentDiagnostics.copyWith(clearError: true));

    player.media = source.url.toString();
    if (source.externalAudio != null) {
      player.setMedia(
        source.externalAudio!.url.toString(),
        mdk.MediaType.audio,
      );
      player.activeAudioTracks = const [0];
    }
    final prepareResult = await player.prepare();
    if (!_isRequestActive(requestSerial, player)) {
      _logStaleRequest(requestSerial, player, 'after-prepare');
      return;
    }
    _logEvent('setSource prepare=$prepareResult');
    if (prepareResult < 0) {
      _textureId.value = null;
      _logEvent('setSource prepare failed=$prepareResult');
      _emitDiagnostics(
        _currentDiagnostics.copyWith(
          error: 'MDK prepare failed: $prepareResult',
        ),
      );
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          position: Duration.zero,
          buffered: Duration.zero,
          clearSource: true,
          errorMessage: 'MDK prepare failed: $prepareResult',
        ),
      );
      return;
    }
    if (source.externalAudio != null) {
      final audioTracks =
          player.mediaInfo.audio?.map((item) => item.index).toList(
                    growable: false,
                  ) ??
              const <int>[];
      if (audioTracks.isNotEmpty) {
        player.activeAudioTracks = audioTracks;
      }
      assert(() {
        debugPrint(
          '[MdkPlayer] setSource '
          'video=${_shortSourceDescriptor(source.url)} '
          'audio=${_shortSourceDescriptor(source.externalAudio!.url)} '
          'prepare=$prepareResult '
          'audioTracks=${audioTracks.join(',')} '
          'activeAudioTracks=${player.activeAudioTracks.join(',')}',
        );
        return true;
      }());
    } else {
      assert(() {
        debugPrint(
          '[MdkPlayer] setSource '
          'video=${_shortSourceDescriptor(source.url)} '
          'audio=- '
          'prepare=$prepareResult',
        );
        return true;
      }());
    }

    if (shouldPrimeMdkPlaybackBeforeTexture(androidTunnel: androidTunnel)) {
      player.state = mdk.PlaybackState.playing;
      _logEvent('setSource prime-native-playback tunnel=true');
    }

    _logEvent(
      'setSource updateTexture start '
      'tunnel=$androidTunnel state=${player.state.name} '
      'mediaStatus=${_mediaStatusHex(player)} '
      'bufferedMs=${player.buffered()} positionMs=${player.position}',
    );
    var texturePendingLogged = false;
    unawaited(
      Future<void>.delayed(_updateTextureTimeout, () {
        if (texturePendingLogged || !_isRequestActive(requestSerial, player)) {
          return;
        }
        _logEvent(
          'setSource updateTexture pending>${_updateTextureTimeout.inMilliseconds}ms '
          'tunnel=$androidTunnel state=${player.state.name} '
          'mediaStatus=${_mediaStatusHex(player)} '
          'bufferedMs=${player.buffered()} positionMs=${player.position}',
        );
      }),
    );
    final textureStopwatch = Stopwatch()..start();
    final textureId = await player.updateTexture(tunnel: androidTunnel).timeout(
          _updateTextureTimeout,
          onTimeout: () => -2,
        );
    texturePendingLogged = true;
    textureStopwatch.stop();
    if (!_isRequestActive(requestSerial, player)) {
      _logStaleRequest(requestSerial, player, 'after-updateTexture');
      return;
    }
    _logEvent(
      'setSource texture=$textureId '
      'elapsedMs=${textureStopwatch.elapsedMilliseconds} '
      'mediaStatus=${_mediaStatusHex(player)}',
    );
    if (textureId < 0) {
      _textureId.value = null;
      _logEvent('setSource texture failed=$textureId');
      final errorMessage = switch (textureId) {
        -2 => 'MDK texture initialization timed out after '
            '${_updateTextureTimeout.inMilliseconds}ms',
        _ => 'MDK texture initialization failed: $textureId',
      };
      _emitDiagnostics(_currentDiagnostics.copyWith(error: errorMessage));
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          position: Duration.zero,
          buffered: Duration.zero,
          clearSource: true,
          errorMessage: errorMessage,
        ),
      );
      return;
    }

    _textureId.value = textureId;
    _syncRuntimeDiagnostics(player);
    _emitDiagnostics(_currentDiagnostics.copyWith(clearError: true));
    final nextStatus = resolveMdkPostTextureStatus(
      currentStatus: _currentState.status,
    );
    _emit(
      _currentState.copyWith(
        status: nextStatus,
        source: source,
        clearErrorMessage: true,
      ),
    );
    _logEvent(
      'setSource ready texture=$textureId status=${nextStatus.name} '
      'size=${_currentDiagnostics.width ?? 0}x${_currentDiagnostics.height ?? 0}',
    );
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (player == null) {
      return;
    }
    final previousStatus = _currentState.status;
    final textureId = _textureId.value ?? -1;
    if (previousStatus == PlaybackStatus.error) {
      _logEvent('play skipped status=error texture=$textureId');
      return;
    }
    if (_currentState.source == null || textureId < 0) {
      _logEvent(
        'play skipped '
        'status=${previousStatus.name} '
        'texture=$textureId '
        'source=${_currentState.source == null ? '-' : _shortSourceDescriptor(_currentState.source!.url)}',
      );
      return;
    }
    player.state = mdk.PlaybackState.playing;
    if ((previousStatus == PlaybackStatus.paused ||
            previousStatus == PlaybackStatus.completed) &&
        textureId >= 0) {
      _armTunnelFirstFrameWatchdog(
        player: player,
        requestSerial: _activeRequestSerial,
        expectedTextureId: textureId,
      );
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.playing,
          clearErrorMessage: true,
        ),
      );
      _logEvent('play resume texture=$textureId');
      return;
    }
    _armTunnelFirstFrameWatchdog(
      player: player,
      requestSerial: _activeRequestSerial,
      expectedTextureId: textureId,
    );
    _logEvent('play request texture=$textureId status=${previousStatus.name}');
  }

  @override
  Future<void> pause() async {
    final player = _player;
    if (player == null) {
      return;
    }
    player.state = mdk.PlaybackState.paused;
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
    _logEvent('pause');
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) {
      return;
    }
    _invalidateActiveRequest('stop');
    final stopped = _waitForStopped(player, context: 'stop');
    await _releaseTextureIfNeeded(player, context: 'stop');
    _textureId.value = null;
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
    _logEvent('stop done stopped=$stopped');
  }

  @override
  Future<void> setVolume(double value) async {
    final player = _player;
    final normalized = value.clamp(0, 1).toDouble();
    if (player == null) {
      _emit(_currentState.copyWith(volume: normalized));
      return;
    }
    player.volume = normalized;
    _emit(_currentState.copyWith(volume: normalized));
    _logEvent('setVolume ${normalized.toStringAsFixed(2)}');
  }

  @override
  Future<Uint8List?> captureScreenshot() async {
    final player = _player;
    if (player == null) {
      return null;
    }
    final video = player.mediaInfo.video;
    if (video == null || video.isEmpty) {
      return null;
    }
    final width = video.first.codec.width;
    final height = video.first.codec.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final rgba = await player.snapshot(width: width, height: height);
    if (rgba == null) {
      return null;
    }
    return _encodeRgbaToPng(
      rgba: rgba,
      width: width,
      height: height,
    );
  }

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return ValueListenableBuilder<int?>(
      key: key,
      valueListenable: _textureId,
      builder: (context, textureId, _) {
        if (textureId == null || textureId < 0) {
          return const SizedBox.expand();
        }
        final renderSize = resolveMdkTextureRenderSize(
          diagnostics: _currentDiagnostics,
          aspectRatio: aspectRatio,
        );
        final view = Texture(
          textureId: textureId,
          filterQuality: FilterQuality.low,
        );
        return SizedBox.expand(
          child: FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: renderSize.width,
              height: renderSize.height,
              child: view,
            ),
          ),
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    _invalidateActiveRequest('dispose');
    _logEvent('dispose start');
    _progressTimer?.cancel();
    _tunnelFirstFrameWatchdog?.cancel();
    _textureId.value = null;
    _player?.dispose();
    _player = null;
    await _stateController.close();
    await _diagnosticsController.close();
    _logEvent('dispose done');
  }

  void _bindPlayer(mdk.Player player) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_runtimeDiagnosticsPollInterval, (_) {
      if (!shouldPollMdkRuntimeDiagnostics(
        hasSource: _currentState.source != null,
        hasTexture: (_textureId.value ?? -1) >= 0,
      )) {
        return;
      }
      _syncRuntimeDiagnostics(player);
    });
    player.onMediaStatus((oldValue, newValue) {
      if (!_shouldHandlePlayerEvent(player)) {
        return true;
      }
      _syncRuntimeDiagnostics(player);
      _logEvent(
        'mediaStatus ${oldValue.rawValue.toRadixString(16)}->${newValue.rawValue.toRadixString(16)}',
      );
      return true;
    });
    player.onEvent((mdk.MediaEvent event) {
      if (!_shouldHandlePlayerEvent(player)) {
        return;
      }
      _logEvent(
        'event category=${event.category} detail=${event.detail} '
        'error=${event.error}',
      );
      if (event.category == 'render.video' && event.detail == '1st_frame') {
        _tunnelFirstFrameWatchdog?.cancel();
        _firstFrameRendered = true;
        _rebufferStartedAt = null;
        _syncRuntimeDiagnostics(player);
        _emitDiagnostics(_currentDiagnostics.copyWith(clearError: true));
        _emit(
          _currentState.copyWith(
            status: PlaybackStatus.playing,
            clearErrorMessage: true,
          ),
        );
      }
    });
  }

  void _syncRuntimeDiagnostics(mdk.Player player) {
    final buffered = Duration(milliseconds: player.buffered());
    final position = Duration(milliseconds: player.position);
    final mediaStatus = player.mediaStatus;
    final buffering = mediaStatus.test(mdk.MediaStatus.buffering);
    final video = player.mediaInfo.video;
    final audio = player.mediaInfo.audio;
    final width = video?.isNotEmpty == true ? video!.first.codec.width : null;
    final height = video?.isNotEmpty == true ? video!.first.codec.height : null;
    final nextStatus = resolveMdkBufferingStatusTransition(
      currentStatus: _currentState.status,
      buffering: buffering,
      hasSource: _currentState.source != null,
      firstFrameRendered: _firstFrameRendered,
    );

    _trackBufferingTelemetry(
      buffering: buffering,
      previousBuffering: _currentDiagnostics.buffering,
      buffered: buffered,
      position: position,
      player: player,
    );
    _trackLowBufferWindow(
      buffering: buffering,
      buffered: buffered,
      position: position,
      player: player,
    );

    _emitDiagnostics(
      _currentDiagnostics.copyWith(
        width: width,
        height: height,
        buffering: buffering,
        buffered: buffered,
        videoParams: video?.isNotEmpty == true
            ? _videoParamsToMap(video!.first)
            : const <String, String>{},
        audioParams: audio?.isNotEmpty == true
            ? _audioParamsToMap(audio!.first)
            : const <String, String>{},
      ),
    );

    _emit(
      _currentState.copyWith(
        status: nextStatus ?? _currentState.status,
        position: position,
        buffered: buffered,
      ),
    );
  }

  void _trackBufferingTelemetry({
    required bool buffering,
    required bool previousBuffering,
    required Duration buffered,
    required Duration position,
    required mdk.Player player,
  }) {
    if (_currentState.source == null) {
      _rebufferStartedAt = null;
      return;
    }
    if (buffering && !previousBuffering) {
      if (_firstFrameRendered &&
          _currentState.status == PlaybackStatus.playing) {
        _rebufferStartedAt = DateTime.now();
        _rebufferCount += 1;
        _emitDiagnostics(_currentDiagnostics);
        _logEvent(
          'playback rebuffer start '
          'count=$_rebufferCount '
          'bufferMs=${buffered.inMilliseconds} '
          'posMs=${position.inMilliseconds} '
          'mediaStatus=${_mediaStatusHex(player)}',
        );
        return;
      }
      _logEvent(
        'playback buffering start '
        'bufferMs=${buffered.inMilliseconds} '
        'posMs=${position.inMilliseconds} '
        'mediaStatus=${_mediaStatusHex(player)}',
      );
      return;
    }
    if (!buffering && previousBuffering) {
      final startedAt = _rebufferStartedAt;
      if (startedAt != null) {
        _lastRebufferDuration = DateTime.now().difference(startedAt);
        _rebufferStartedAt = null;
        _emitDiagnostics(_currentDiagnostics);
        _logEvent(
          'playback rebuffer end '
          'durationMs=${_lastRebufferDuration!.inMilliseconds} '
          'bufferMs=${buffered.inMilliseconds} '
          'posMs=${position.inMilliseconds} '
          'mediaStatus=${_mediaStatusHex(player)}',
        );
        return;
      }
      _logEvent(
        'playback buffering end '
        'bufferMs=${buffered.inMilliseconds} '
        'posMs=${position.inMilliseconds} '
        'mediaStatus=${_mediaStatusHex(player)}',
      );
    }
  }

  void _trackLowBufferWindow({
    required bool buffering,
    required Duration buffered,
    required Duration position,
    required mdk.Player player,
  }) {
    final canMeasureLowBuffer = _currentState.source != null &&
        _firstFrameRendered &&
        _currentState.status == PlaybackStatus.playing &&
        !buffering;
    if (!canMeasureLowBuffer) {
      _lowBufferWarningActive = false;
      return;
    }
    final lowBuffer = buffered < _lowBufferWarningThreshold;
    if (lowBuffer == _lowBufferWarningActive) {
      return;
    }
    _lowBufferWarningActive = lowBuffer;
    if (lowBuffer) {
      _logEvent(
        'playback low-buffer '
        'thresholdMs=${_lowBufferWarningThreshold.inMilliseconds} '
        'bufferMs=${buffered.inMilliseconds} '
        'posMs=${position.inMilliseconds} '
        'mediaStatus=${_mediaStatusHex(player)}',
      );
      return;
    }
    _logEvent(
      'playback low-buffer cleared '
      'thresholdMs=${_lowBufferWarningThreshold.inMilliseconds} '
      'bufferMs=${buffered.inMilliseconds} '
      'posMs=${position.inMilliseconds} '
      'mediaStatus=${_mediaStatusHex(player)}',
    );
  }

  void _emit(PlayerState state) {
    _currentState = state.copyWith(backend: backend);
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }

  void _emitDiagnostics(PlayerDiagnostics diagnostics) {
    _currentDiagnostics = diagnostics.copyWith(
      backend: backend,
      lowLatencyMode: lowLatency,
      rebufferCount: _rebufferCount,
      lastRebufferDuration: _lastRebufferDuration,
      clearLastRebufferDuration: _lastRebufferDuration == null,
    );
    if (!_diagnosticsController.isClosed) {
      _diagnosticsController.add(_currentDiagnostics);
    }
  }

  void _resetPlaybackTelemetry() {
    _tunnelFirstFrameWatchdog?.cancel();
    _firstFrameRendered = false;
    _lowBufferWarningActive = false;
    _rebufferCount = 0;
    _rebufferStartedAt = null;
    _lastRebufferDuration = null;
    _tunnelFallbackAttempted = false;
  }

  Map<String, String> _videoParamsToMap(dynamic info) {
    return <String, String>{
      'codec': info.codec.codec,
      'width': '${info.codec.width}',
      'height': '${info.codec.height}',
      if (info.codec.frameRate > 0) 'frame_rate': '${info.codec.frameRate}',
      if (info.codec.formatName != null) 'format': info.codec.formatName!,
      if (info.rotation != 0) 'rotation': '${info.rotation}',
    };
  }

  Map<String, String> _audioParamsToMap(dynamic info) {
    return <String, String>{
      'codec': info.codec.codec,
      'sample_rate': '${info.codec.sampleRate}',
      'channels': '${info.codec.channels}',
      if (info.codec.bitRate > 0) 'bit_rate': '${info.codec.bitRate}',
    };
  }

  Future<Uint8List?> _encodeRgbaToPng({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    final completer = Completer<Uint8List?>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) async {
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          completer.complete(data?.buffer.asUint8List());
        } catch (_) {
          completer.complete(null);
        } finally {
          image.dispose();
        }
      },
    );
    return completer.future;
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

  String _mediaStatusHex(mdk.Player player) {
    return player.mediaStatus.rawValue.toRadixString(16);
  }

  bool _waitForStopped(
    mdk.Player player, {
    required String context,
  }) {
    player.state = mdk.PlaybackState.stopped;
    final stopped = player.waitFor(
      mdk.PlaybackState.stopped,
      timeout: _stopWaitTimeout.inMilliseconds,
    );
    _logEvent(
      '$context waitForStopped=$stopped '
      'timeoutMs=${_stopWaitTimeout.inMilliseconds}',
    );
    return stopped;
  }

  Future<void> _releaseTextureIfNeeded(
    mdk.Player player, {
    required String context,
  }) async {
    final activeTextureId = player.textureId.value;
    if (activeTextureId == null || activeTextureId < 0) {
      _logEvent('$context releaseTexture skipped active=-');
      return;
    }
    _logEvent('$context releaseTexture start texture=$activeTextureId');
    final result = await player.updateTexture(width: -1).timeout(
          _releaseTextureTimeout,
          onTimeout: () => -3,
        );
    final activeTextureIdAfter = player.textureId.value;
    if (isMdkTextureReleaseDetached(
      result: result,
      activeTextureIdAfter: activeTextureIdAfter,
    )) {
      _logEvent(
        '$context releaseTexture detached '
        'result=$result '
        'activeAfter=${activeTextureIdAfter ?? '-'} '
        'timeoutMs=${_releaseTextureTimeout.inMilliseconds}',
      );
      return;
    }
    _logEvent(
      '$context releaseTexture result=$result '
      'timeoutMs=${_releaseTextureTimeout.inMilliseconds}',
    );
  }

  void _armTunnelFirstFrameWatchdog({
    required mdk.Player player,
    required int requestSerial,
    required int expectedTextureId,
  }) {
    _tunnelFirstFrameWatchdog?.cancel();
    if (!shouldAttemptMdkTunnelFallback(
      androidTunnel: androidTunnel,
      firstFrameRendered: _firstFrameRendered,
      fallbackAttempted: _tunnelFallbackAttempted,
      hasSource: _currentState.source != null,
      textureId: expectedTextureId,
    )) {
      return;
    }
    _tunnelFirstFrameWatchdog = Timer(_tunnelFirstFrameTimeout, () {
      unawaited(
        _recoverFromTunnelVideoStall(
          player: player,
          requestSerial: requestSerial,
          expectedTextureId: expectedTextureId,
        ),
      );
    });
  }

  Future<void> _recoverFromTunnelVideoStall({
    required mdk.Player player,
    required int requestSerial,
    required int expectedTextureId,
  }) async {
    if (!shouldAttemptMdkTunnelFallback(
      androidTunnel: androidTunnel,
      firstFrameRendered: _firstFrameRendered,
      fallbackAttempted: _tunnelFallbackAttempted,
      hasSource: _currentState.source != null,
      textureId: expectedTextureId,
    )) {
      return;
    }
    if (!_isRequestActive(requestSerial, player) ||
        _textureId.value != expectedTextureId) {
      return;
    }
    _tunnelFallbackAttempted = true;
    _logEvent(
      'playback tunnel first-frame timeout>'
      '${_tunnelFirstFrameTimeout.inMilliseconds}ms '
      'texture=$expectedTextureId '
      'status=${_currentState.status.name} '
      'mediaStatus=${_mediaStatusHex(player)}',
    );
    final stopwatch = Stopwatch()..start();
    final fallbackTextureId = await player.updateTexture(tunnel: false).timeout(
          _updateTextureTimeout,
          onTimeout: () => -2,
        );
    stopwatch.stop();
    if (!_isRequestActive(requestSerial, player)) {
      return;
    }
    _logEvent(
      'playback tunnel fallback texture=$fallbackTextureId '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    if (fallbackTextureId < 0) {
      return;
    }
    _textureId.value = fallbackTextureId;
    player.state = mdk.PlaybackState.playing;
    _syncRuntimeDiagnostics(player);
    _emitDiagnostics(_currentDiagnostics.copyWith(clearError: true));
  }

  int _beginSourceRequest() {
    final requestSerial = ++_requestSerialCounter;
    _activeRequestSerial = requestSerial;
    _activeEventSerial = requestSerial;
    _emitDiagnostics(_freshDiagnostics(clearRecentLogs: true));
    return requestSerial;
  }

  void _invalidateActiveRequest(String reason) {
    final nextSerial = ++_requestSerialCounter;
    _activeRequestSerial = nextSerial;
    _activeEventSerial = 0;
    _logEvent('request invalidate reason=$reason serial=$nextSerial');
  }

  bool _isRequestActive(int requestSerial, mdk.Player player) {
    return identical(player, _player) && requestSerial == _activeRequestSerial;
  }

  bool _shouldHandlePlayerEvent(mdk.Player player) {
    return identical(player, _player) && _activeEventSerial != 0;
  }

  void _logStaleRequest(int requestSerial, mdk.Player player, String stage) {
    final status = identical(player, _player) ? 'attached' : 'detached';
    _logEvent(
      'setSource request=$requestSerial stale stage=$stage '
      'player=$status active=$_activeRequestSerial',
    );
  }

  PlayerDiagnostics _freshDiagnostics({bool clearRecentLogs = false}) {
    if (clearRecentLogs) {
      _recentLogs.clear();
    }
    _resetPlaybackTelemetry();
    return PlayerDiagnostics.empty(backend).copyWith(
      debugLogEnabled: debugLogEnabled,
      recentLogs: debugLogEnabled ? _snapshotRecentLogs() : const <String>[],
    );
  }

  List<String> _snapshotRecentLogs() {
    return List<String>.unmodifiable(_recentLogs.toList(growable: false));
  }

  void _logEvent(String message) {
    final normalized = message.trim();
    if (normalized.isNotEmpty && debugLogEnabled) {
      _recentLogs.addLast(normalized);
      while (_recentLogs.length > _maxRecentLogs) {
        _recentLogs.removeFirst();
      }
      _emitDiagnostics(
        _currentDiagnostics.copyWith(
          debugLogEnabled: true,
          recentLogs: _snapshotRecentLogs(),
        ),
      );
    }
    eventLogger?.call(message);
  }
}

@visibleForTesting
Size resolveMdkTextureRenderSize({
  required PlayerDiagnostics diagnostics,
  required double? aspectRatio,
}) {
  final width = diagnostics.width;
  final height = diagnostics.height;
  if (width != null && height != null && width > 0 && height > 0) {
    return Size(width.toDouble(), height.toDouble());
  }
  if (aspectRatio != null && aspectRatio > 0) {
    const fallbackHeight = 1000.0;
    return Size(aspectRatio * fallbackHeight, fallbackHeight);
  }
  return const Size(1600, 900);
}

@visibleForTesting
PlaybackStatus resolveMdkPostTextureStatus({
  required PlaybackStatus currentStatus,
}) {
  if (currentStatus == PlaybackStatus.playing) {
    return PlaybackStatus.playing;
  }
  return PlaybackStatus.ready;
}

@visibleForTesting
PlaybackStatus? resolveMdkBufferingStatusTransition({
  required PlaybackStatus currentStatus,
  required bool buffering,
  required bool hasSource,
  required bool firstFrameRendered,
}) {
  if (!hasSource) {
    return null;
  }
  if (buffering) {
    return switch (currentStatus) {
      PlaybackStatus.ready ||
      PlaybackStatus.buffering ||
      PlaybackStatus.playing =>
        PlaybackStatus.buffering,
      _ => null,
    };
  }
  if (currentStatus != PlaybackStatus.buffering) {
    return null;
  }
  return firstFrameRendered ? PlaybackStatus.playing : PlaybackStatus.ready;
}

typedef MdkBufferStrategy = ({int minMs, int maxMs, bool drop});

@visibleForTesting
bool shouldPrimeMdkPlaybackBeforeTexture({
  required bool androidTunnel,
}) {
  return androidTunnel;
}

@visibleForTesting
bool shouldAttemptMdkTunnelFallback({
  required bool androidTunnel,
  required bool firstFrameRendered,
  required bool fallbackAttempted,
  required bool hasSource,
  required int textureId,
}) {
  return androidTunnel &&
      !firstFrameRendered &&
      !fallbackAttempted &&
      hasSource &&
      textureId >= 0;
}

@visibleForTesting
bool shouldPollMdkRuntimeDiagnostics({
  required bool hasSource,
  required bool hasTexture,
}) {
  return hasSource || hasTexture;
}

@visibleForTesting
Map<String, Object> resolveMdkRegisterOptions({
  required bool lowLatency,
  required bool androidTunnel,
}) {
  return <String, Object>{
    'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
    if (lowLatency) 'lowLatency': 2,
    'tunnel': androidTunnel,
  };
}

@visibleForTesting
MdkBufferStrategy resolveMdkBufferStrategy({
  required bool lowLatency,
  PlaybackBufferProfile bufferProfile = PlaybackBufferProfile.defaultLowLatency,
}) {
  if (bufferProfile == PlaybackBufferProfile.heavyStreamStable) {
    return (
      minMs: 1000,
      maxMs: 8000,
      drop: false,
    );
  }
  if (lowLatency) {
    return (
      minMs: 500,
      maxMs: 4000,
      drop: false,
    );
  }
  return (
    minMs: 500,
    maxMs: 6000,
    drop: false,
  );
}

@visibleForTesting
List<String>? resolveMdkPreferredVideoDecoders({
  required bool preferHardwareVideoDecoder,
  required TargetPlatform targetPlatform,
  required bool isWeb,
}) {
  if (isWeb ||
      targetPlatform != TargetPlatform.android ||
      !preferHardwareVideoDecoder) {
    return null;
  }
  return const <String>['AMediaCodec', 'MediaCodec', 'FFmpeg'];
}

@visibleForTesting
bool isMdkTextureReleaseDetached({
  required int result,
  required int? activeTextureIdAfter,
}) {
  return result == -1 &&
      (activeTextureIdAfter == null || activeTextureIdAfter < 0);
}
