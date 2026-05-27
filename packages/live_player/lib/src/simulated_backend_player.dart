import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'base_player.dart';
import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';

class SimulatedBackendPlayer implements BasePlayer {
  SimulatedBackendPlayer({
    required this.backend,
    required Duration startupDelay,
    required Duration bufferDelay,
  })  : _startupDelay = startupDelay,
        _bufferDelay = bufferDelay,
        _currentState = PlayerState(backend: backend),
        _currentDiagnostics = PlayerDiagnostics.empty(backend);

  final Duration _startupDelay;
  final Duration _bufferDelay;

  @override
  final PlayerBackend backend;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnosticsController =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;
  final PlayerDiagnostics _currentDiagnostics;
  PlaybackSource? _currentSource;
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<PlayerState> get states => _stateController.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnosticsController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  bool get supportsEmbeddedView => false;

  @override
  bool get supportsScreenshot => true;

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
    _currentSource = null;
    _emit(_currentState.copyWith(
      status: PlaybackStatus.ready,
      clearSource: true,
    ));
  }

  @override
  Future<void> setVolume(double value) async {
    _emit(_currentState.copyWith(volume: value.clamp(0, 1)));
  }

  @override
  Future<Uint8List?> captureScreenshot() async => Uint8List.fromList(
        _kPreviewScreenshotPng,
      );

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
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stateController.close();
    await _diagnosticsController.close();
  }

  void _emit(PlayerState state) {
    _currentState = state.copyWith(backend: backend);
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }
}

const List<int> _kPreviewScreenshotPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0xA7,
  0x69,
  0xA0,
  0xDD,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
