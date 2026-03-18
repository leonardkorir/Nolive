import 'dart:async';

import 'package:flutter/widgets.dart';

import 'base_player.dart';
import 'memory_player.dart';
import 'player_backend.dart';
import 'player_state.dart';
import 'simulated_mdk_player.dart';
import 'simulated_mpv_player.dart';

typedef PlayerBuilder = BasePlayer Function();

class SwitchablePlayer implements BasePlayer {
  SwitchablePlayer({
    PlayerBackend initialBackend = PlayerBackend.memory,
    Map<PlayerBackend, PlayerBuilder>? builders,
  })  : _builders = builders ??
            {
              PlayerBackend.memory: MemoryPlayer.new,
              PlayerBackend.mpv: SimulatedMpvPlayer.new,
              PlayerBackend.mdk: SimulatedMdkPlayer.new,
            },
        _activeBackend = initialBackend,
        _delegate = (builders ??
            {
              PlayerBackend.memory: MemoryPlayer.new,
              PlayerBackend.mpv: SimulatedMpvPlayer.new,
              PlayerBackend.mdk: SimulatedMdkPlayer.new,
            })[initialBackend]!() {
    _attachDelegate();
  }

  final Map<PlayerBackend, PlayerBuilder> _builders;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  late BasePlayer _delegate;
  late PlayerBackend _activeBackend;
  StreamSubscription<PlayerState>? _delegateSubscription;
  bool _initialized = false;

  List<PlayerBackend> get supportedBackends =>
      _builders.keys.toList(growable: false);

  @override
  PlayerBackend get backend => _activeBackend;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  PlayerState get currentState => _delegate.currentState;

  @override
  bool get supportsEmbeddedView => _delegate.supportsEmbeddedView;

  Future<void> switchBackend(PlayerBackend nextBackend) async {
    if (nextBackend == _activeBackend) {
      return;
    }
    await _replaceDelegate(nextBackend);
  }

  Future<void> refreshBackend() => _replaceDelegate(_activeBackend);

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _delegate.initialize();
  }

  @override
  Future<void> setSource(PlaybackSource source) => _delegate.setSource(source);

  @override
  Future<void> play() => _delegate.play();

  @override
  Future<void> pause() => _delegate.pause();

  @override
  Future<void> stop() => _delegate.stop();

  @override
  Future<void> setVolume(double value) => _delegate.setVolume(value);

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return _delegate.buildView(
      key: key,
      aspectRatio: aspectRatio,
      fit: fit,
      pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
      resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
    );
  }

  @override
  Future<void> dispose() async {
    await _delegateSubscription?.cancel();
    await _delegate.dispose();
    await _stateController.close();
  }

  Future<void> _replaceDelegate(PlayerBackend nextBackend) async {
    final source = currentState.source;
    final status = currentState.status;
    final volume = currentState.volume;
    await _delegateSubscription?.cancel();
    await _delegate.dispose();
    _activeBackend = nextBackend;
    _delegate = _builders[nextBackend]!();
    _attachDelegate();
    if (_initialized) {
      await _delegate.initialize();
      await _delegate.setVolume(volume);
      if (source != null) {
        await _delegate.setSource(source);
        if (status == PlaybackStatus.playing) {
          await _delegate.play();
        } else if (status == PlaybackStatus.paused) {
          await _delegate.pause();
        }
      }
    }
  }

  void _attachDelegate() {
    _delegateSubscription = _delegate.states.listen((state) {
      if (!_stateController.isClosed) {
        _stateController.add(state.copyWith(backend: _activeBackend));
      }
    });
  }
}
