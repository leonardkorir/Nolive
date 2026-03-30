import 'dart:async';
import 'dart:collection';

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
  });

  static const Duration _progressBroadcastStep = Duration(milliseconds: 400);
  static const Duration _bufferBroadcastStep = Duration(milliseconds: 400);
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
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Queue<String> _recentLogs = ListQueue<String>();

  mk.Player? _player;
  VideoController? _controller;
  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);
  PlayerDiagnostics _currentDiagnostics = const PlayerDiagnostics(
    backend: PlayerBackend.mpv,
  );
  bool _initialized = false;
  Duration _lastBroadcastPosition = Duration.zero;
  Duration _lastBroadcastBuffered = Duration.zero;

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
    if (_initialized) {
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
    await _configurePlayerProperties(
      player,
      properties: runtimeConfiguration.platformProperties,
    );
    _bindPlayer(player);
    _initialized = true;
    _emitDiagnostics(
      _currentDiagnostics.copyWith(debugLogEnabled: logEnabled),
    );
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    await initialize();
    final player = _player;
    if (player == null) {
      return;
    }
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.buffering,
        source: source,
        clearErrorMessage: true,
      ),
    );
    _lastBroadcastPosition = Duration.zero;
    _lastBroadcastBuffered = Duration.zero;
    await _configureSourceOptions(player, source);
    await player.open(
      mk.Media(source.url.toString(), httpHeaders: source.headers),
      play: false,
    );
    assert(() {
      debugPrint(
        '[MpvPlayer] setSource '
        'video=${_shortSourceDescriptor(source.url)} '
        'audio=${source.externalAudio == null ? '-' : _shortSourceDescriptor(source.externalAudio!.url)} '
        'audioHeaders=${source.externalAudio?.headers.keys.join(',') ?? '-'}',
      );
      return true;
    }());
    if (source.externalAudio != null) {
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
  }

  Future<void> _configureSourceOptions(
    mk.Player player,
    PlaybackSource source,
  ) async {
    final dynamic platform = player.platform;
    if (platform == null) {
      return;
    }
    final forceSeekable = source.url.host == '127.0.0.1' &&
        source.url.path.contains('/twitch-ad-guard/');
    try {
      await platform.setProperty(
        'force-seekable',
        forceSeekable ? 'yes' : 'no',
      );
    } catch (_) {
      // Older media_kit backends may not expose direct mpv property writes.
    }
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await player.play();
  }

  @override
  Future<void> pause() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await player.pause();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await player.stop();
    _lastBroadcastPosition = Duration.zero;
    _lastBroadcastBuffered = Duration.zero;
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setVolume(double value) async {
    final player = _player;
    final normalized = value.clamp(0, 1).toDouble();
    if (player == null) {
      _emit(_currentState.copyWith(volume: normalized));
      return;
    }
    await player.setVolume(normalized * 100);
    _emit(_currentState.copyWith(volume: normalized));
  }

  @override
  Future<Uint8List?> captureScreenshot() async {
    final player = _player;
    if (player == null) {
      return null;
    }
    try {
      return await player.screenshot(format: 'image/png');
    } catch (_) {
      return null;
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
    final controller = _controller;
    if (controller == null) {
      return SizedBox.expand(key: key);
    }
    return Video(
      key: key,
      controller: controller,
      aspectRatio: aspectRatio,
      fit: fit,
      pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
      resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
      controls: NoVideoControls,
    );
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _player?.dispose();
    _player = null;
    _controller = null;
    await _stateController.close();
    await _diagnosticsController.close();
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
          _emit(_currentState.copyWith(status: PlaybackStatus.playing));
        } else if (_currentState.status == PlaybackStatus.playing) {
          _emit(_currentState.copyWith(status: PlaybackStatus.paused));
        }
      }),
      player.stream.completed.listen((completed) {
        if (completed) {
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
          final nextLogs = List<String>.from(_recentLogs)
            ..add('[${entry.level}] ${entry.prefix}: ${entry.text.trim()}');
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
  });

  final VideoControllerConfiguration controllerConfiguration;
  final mk.MPVLogLevel logLevel;
  final Map<String, String> platformProperties;
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
  final controllerConfiguration = customOutputEnabled
      ? VideoControllerConfiguration(
          vo: sanitizedVideoOutputDriver,
          hwdec: enableHardwareAcceleration ? sanitizedHardwareDecoder : 'no',
        )
      : compatMode
          ? const VideoControllerConfiguration(
              vo: 'mediacodec_embed',
              hwdec: 'mediacodec',
            )
          : VideoControllerConfiguration(
              enableHardwareAcceleration: enableHardwareAcceleration,
              hwdec:
                  enableHardwareAcceleration ? sanitizedHardwareDecoder : 'no',
              androidAttachSurfaceAfterVideoParameters: false,
            );
  final platformProperties = <String, String>{
    'cache': doubleBufferingEnabled ? 'yes' : 'no',
    'cache-secs': doubleBufferingEnabled ? '3' : '0',
    'demuxer-seekable-cache': doubleBufferingEnabled ? 'yes' : 'no',
    'demuxer-donate-buffer': doubleBufferingEnabled ? 'yes' : 'no',
    if (!doubleBufferingEnabled) 'demuxer-max-back-bytes': '0',
  };
  return MpvRuntimeConfiguration(
    controllerConfiguration: controllerConfiguration,
    logLevel: logEnabled ? mk.MPVLogLevel.debug : mk.MPVLogLevel.error,
    platformProperties: platformProperties,
  );
}
