import 'dart:async';

import 'package:flutter/widgets.dart';

import 'base_player.dart';
import 'player_backend.dart';
import 'player_state.dart';

class SimulatedBackendPlayer implements BasePlayer {
  SimulatedBackendPlayer({
    required this.backend,
    required Duration startupDelay,
    required Duration bufferDelay,
  })  : _startupDelay = startupDelay,
        _bufferDelay = bufferDelay,
        _currentState = PlayerState(backend: backend);

  final Duration _startupDelay;
  final Duration _bufferDelay;

  @override
  final PlayerBackend backend;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  PlayerState _currentState;
  PlaybackSource? _currentSource;
  bool _initialized = false;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  bool get supportsEmbeddedView => false;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _emit(_currentState.copyWith(status: PlaybackStatus.initializing));
    await Future<void>.delayed(_startupDelay);
    _initialized = true;
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    _currentSource = source;
    _emit(_currentState.copyWith(
      status: PlaybackStatus.buffering,
      source: source,
      clearErrorMessage: true,
    ));
    await Future<void>.delayed(_bufferDelay);
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
    if (_currentSource == null) {
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          errorMessage: 'Playback source has not been resolved.',
        ),
      );
      return;
    }
    _emit(_currentState.copyWith(status: PlaybackStatus.buffering));
    await Future<void>.delayed(_bufferDelay);
    _emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setVolume(double value) async {
    _emit(_currentState.copyWith(volume: value.clamp(0, 1)));
  }

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }

  void _emit(PlayerState state) {
    _currentState = state.copyWith(backend: backend);
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }
}
