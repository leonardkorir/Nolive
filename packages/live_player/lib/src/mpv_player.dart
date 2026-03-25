import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import 'base_player.dart';
import 'player_backend.dart';
import 'player_state.dart';

class MpvPlayer implements BasePlayer {
  MpvPlayer({
    this.enableHardwareAcceleration = true,
    this.compatMode = false,
  });

  static bool _mediaKitInitialized = false;

  final bool enableHardwareAcceleration;
  final bool compatMode;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  mk.Player? _player;
  VideoController? _controller;
  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);
  bool _initialized = false;

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  bool get supportsEmbeddedView => true;

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

    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(title: 'Nolive'),
    );
    _player = player;
    _controller = VideoController(
      player,
      configuration: compatMode
          ? const VideoControllerConfiguration(
              vo: 'mediacodec_embed',
              hwdec: 'mediacodec',
            )
          : VideoControllerConfiguration(
              enableHardwareAcceleration: enableHardwareAcceleration,
              hwdec: enableHardwareAcceleration ? 'auto-safe' : 'no',
              androidAttachSurfaceAfterVideoParameters: false,
            ),
    );
    _bindPlayer(player);
    _initialized = true;
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
        _emit(_currentState.copyWith(position: position));
      }),
      player.stream.duration.listen((duration) {
        _emit(_currentState.copyWith(duration: duration));
      }),
      player.stream.volume.listen((volume) {
        _emit(_currentState.copyWith(volume: (volume / 100).clamp(0, 1)));
      }),
      player.stream.buffering.listen((buffering) {
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
        _emit(_currentState.copyWith(buffered: buffered));
      }),
      player.stream.error.listen((message) {
        if (message.isEmpty) {
          return;
        }
        _emit(
          _currentState.copyWith(
            status: PlaybackStatus.error,
            errorMessage: message,
          ),
        );
      }),
    ]);
  }

  void _emit(PlayerState state) {
    _currentState = state.copyWith(backend: backend);
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
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
