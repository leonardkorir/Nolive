import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;

import 'base_player.dart';
import 'player_backend.dart';
import 'player_state.dart';

class MdkPlayer implements BasePlayer {
  MdkPlayer({
    this.lowLatency = true,
    this.androidTunnel = false,
  });

  static bool _registered = false;

  final bool lowLatency;
  final bool androidTunnel;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);

  mdk.Player? _player;
  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mdk);
  bool _initialized = false;

  @override
  PlayerBackend get backend => PlayerBackend.mdk;

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
    if (!_registered) {
      fvp.registerWith(
        options: {
          'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
        },
      );
      _registered = true;
    }
    final player = mdk.Player();
    _player = player;
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
    if (player.state != mdk.PlaybackState.stopped) {
      player.state = mdk.PlaybackState.stopped;
      player.waitFor(mdk.PlaybackState.stopped);
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
    if (lowLatency) {
      player.setProperty('avformat.fflags', '+nobuffer');
      player.setProperty('avformat.fpsprobesize', '0');
      player.setProperty('avformat.analyzeduration', '100000');
      player.setBufferRange(min: 0, max: 1000, drop: true);
    } else {
      player.setBufferRange(min: 0);
    }

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

    player.media = source.url.toString();
    if (source.externalAudio != null) {
      player.setMedia(
        source.externalAudio!.url.toString(),
        mdk.MediaType.audio,
      );
      player.activeAudioTracks = const [0];
    }
    final prepareResult = await player.prepare();
    if (prepareResult < 0) {
      _textureId.value = null;
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
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

    final textureId = await player.updateTexture(tunnel: androidTunnel);
    if (textureId < 0) {
      _textureId.value = null;
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          errorMessage: 'MDK texture initialization failed: $textureId',
        ),
      );
      return;
    }

    _textureId.value = textureId;
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        clearErrorMessage: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (player == null) {
      return;
    }
    player.state = mdk.PlaybackState.playing;
    _emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    final player = _player;
    if (player == null) {
      return;
    }
    player.state = mdk.PlaybackState.paused;
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) {
      return;
    }
    player.state = mdk.PlaybackState.stopped;
    _textureId.value = null;
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
    player.volume = normalized;
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
    return ValueListenableBuilder<int?>(
      key: key,
      valueListenable: _textureId,
      builder: (context, textureId, _) {
        if (textureId == null || textureId < 0) {
          return const SizedBox.expand();
        }
        final view = Texture(
          textureId: textureId,
          filterQuality: FilterQuality.medium,
        );
        if (aspectRatio == null) {
          return SizedBox.expand(child: FittedBox(fit: fit, child: view));
        }
        return Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: FittedBox(fit: fit, child: view),
          ),
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    _textureId.value = null;
    _player?.dispose();
    _player = null;
    _textureId.dispose();
    await _stateController.close();
  }

  void _bindPlayer(mdk.Player player) {
    player.onEvent((mdk.MediaEvent event) {
      if (event.category == 'render.video' && event.detail == '1st_frame') {
        _emit(_currentState.copyWith(status: PlaybackStatus.playing));
      }
    });
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
