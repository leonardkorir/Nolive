import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_fullscreen_session_ports.dart';

class TestRecordingPlayer implements BasePlayer {
  TestRecordingPlayer({
    this.playerBackend = PlayerBackend.mpv,
    PlayerDiagnostics? currentDiagnostics,
  }) : _currentDiagnostics =
           currentDiagnostics ?? PlayerDiagnostics(backend: playerBackend),
       _currentState = PlayerState(backend: playerBackend);

  final List<String> events = <String>[];
  final List<Key?> viewKeys = <Key?>[];
  final PlayerBackend playerBackend;
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;
  PlayerDiagnostics _currentDiagnostics;

  @override
  PlayerBackend get backend => playerBackend;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

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
    events.add('initialize');
    emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        clearErrorMessage: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    events.add('play');
    // Simulate first decoded frame so room loading shell can dismiss.
    // Keep any diagnostics the test already seeded.
    if ((_currentDiagnostics.width ?? 0) <= 0 ||
        (_currentDiagnostics.height ?? 0) <= 0) {
      emitDiagnostics(_currentDiagnostics.copyWith(width: 1280, height: 720));
    }
    emit(
      _currentState.copyWith(
        status: PlaybackStatus.playing,
        position: const Duration(milliseconds: 40),
        buffered: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    emitDiagnostics(
      _currentDiagnostics.copyWith(clearWidth: true, clearHeight: true),
    );
    emit(
      _currentState.copyWith(status: PlaybackStatus.ready, clearSource: true),
    );
  }

  @override
  Future<void> setVolume(double value) async {
    events.add('setVolume');
    emit(_currentState.copyWith(volume: value));
  }

  @override
  Future<Uint8List?> captureScreenshot() async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    events.add('buildView');
    viewKeys.add(key);
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _diagnostics.close();
  }

  void emit(PlayerState next) {
    _currentState = next.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }

  void emitDiagnostics(PlayerDiagnostics next) {
    _currentDiagnostics = next;
    if (!_diagnostics.isClosed) {
      _diagnostics.add(_currentDiagnostics);
    }
  }
}

class TestRoomAndroidPlaybackBridgeFacade
    implements RoomAndroidPlaybackBridgeFacade {
  bool supported = true;
  bool inPictureInPictureMode = false;
  Completer<bool>? inPictureInPictureModeCompleter;
  double? mediaVolume = 0.6;
  Object? prepareForPictureInPictureError;
  Object? lockPortraitError;
  Object? lockLandscapeError;
  Object? lockPortraitFullscreenError;
  Object? freezeFullscreenOrientationError;
  bool freezeFullscreenOrientationResult = true;
  final List<String> events = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Future<double?> getMediaVolume() async {
    events.add('getMediaVolume');
    return mediaVolume;
  }

  @override
  Future<bool> isInPictureInPictureMode() async {
    events.add('isInPictureInPictureMode');
    final completer = inPictureInPictureModeCompleter;
    if (completer != null) {
      return completer.future;
    }
    return inPictureInPictureMode;
  }

  @override
  Future<bool> lockPortrait() async {
    events.add('lockPortrait');
    final error = lockPortraitError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  Future<bool> restoreShellOrientation() => lockPortrait();

  @override
  Future<bool> lockLandscape() async {
    events.add('lockLandscape');
    final error = lockLandscapeError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  Future<bool> lockPortraitFullscreen() async {
    events.add('lockPortraitFullscreen');
    final error = lockPortraitFullscreenError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  Future<bool> freezeFullscreenOrientation() async {
    events.add('freezeFullscreenOrientation');
    final error = freezeFullscreenOrientationError;
    if (error != null) {
      throw error;
    }
    return freezeFullscreenOrientationResult;
  }

  @override
  Future<bool> prepareForPictureInPicture() async {
    events.add('prepareForPictureInPicture');
    final error = prepareForPictureInPictureError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  Future<bool> setMediaVolume(double value) async {
    mediaVolume = value;
    events.add('setMediaVolume');
    return true;
  }
}

class TestRoomPipHostFacade implements RoomPipHostFacade {
  final StreamController<RoomPipStatus> _status =
      StreamController<RoomPipStatus>.broadcast();
  bool pipAvailable = true;
  bool switcherEnabled = false;
  RoomPipStatus nextEnableStatus = RoomPipStatus.enabled;
  Completer<RoomPipStatus>? enablePipCompleter;
  bool emitStatusOnEnable = true;
  RoomPipAspectRatio? lastAspectRatio;

  @override
  Future<RoomPipStatus> enablePip({
    required RoomPipAspectRatio aspectRatio,
  }) async {
    lastAspectRatio = aspectRatio;
    final status = enablePipCompleter != null
        ? await enablePipCompleter!.future
        : nextEnableStatus;
    if (emitStatusOnEnable) {
      _status.add(status);
    }
    return status;
  }

  void emitStatus(RoomPipStatus status) {
    _status.add(status);
  }

  @override
  Future<bool> isPipAvailable() async => pipAvailable;

  @override
  Stream<RoomPipStatus> get statusStream => _status.stream;

  /// Not part of [RoomPipHostFacade] any more — the switcher is a widget-layer
  /// concern. Kept so tests that drive the fake directly still read naturally.
  Widget wrapSwitcher({
    required Widget childWhenDisabled,
    required Widget childWhenEnabled,
  }) {
    return switcherEnabled ? childWhenEnabled : childWhenDisabled;
  }

  Future<void> dispose() async {
    await _status.close();
  }
}

class TestRoomDesktopWindowFacade implements RoomDesktopWindowFacade {
  bool supported = false;
  Rect bounds = const Rect.fromLTWH(0, 0, 960, 540);
  bool alwaysOnTop = false;
  bool resizable = true;
  Object? setBoundsError;
  final List<String> events = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<bool> isAlwaysOnTop() async => alwaysOnTop;

  @override
  Future<bool> isResizable() async => resizable;

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    alwaysOnTop = value;
    events.add('setAlwaysOnTop:$value');
  }

  @override
  Future<void> setBounds(Rect nextBounds, {bool animate = false}) async {
    final error = setBoundsError;
    if (error != null) {
      throw error;
    }
    bounds = nextBounds;
    events.add('setBounds:${nextBounds.width}x${nextBounds.height}:$animate');
  }

  @override
  Future<void> setResizable(bool value) async {
    resizable = value;
    events.add('setResizable:$value');
  }
}

class TestRoomScreenAwakeFacade implements RoomScreenAwakeFacade {
  final List<bool> states = <bool>[];

  @override
  Future<void> toggle({required bool enabled}) async {
    states.add(enabled);
  }
}

class TestRoomSystemUiFacade implements RoomSystemUiFacade {
  final List<String> events = <String>[];
  SystemUiMode? lastMode;
  List<DeviceOrientation>? lastOrientations;
  SystemUiOverlayStyle? lastOverlayStyle;
  Object? modeError;
  Object? orientationError;
  Object? overlayError;

  @override
  Future<void> setEnabledSystemUIMode(SystemUiMode mode) async {
    final error = modeError;
    if (error != null) {
      throw error;
    }
    lastMode = mode;
    events.add('mode:${mode.name}');
  }

  @override
  Future<void> setPreferredOrientations(
    List<DeviceOrientation> orientations,
  ) async {
    final error = orientationError;
    if (error != null) {
      throw error;
    }
    lastOrientations = List<DeviceOrientation>.of(orientations);
    events.add('orientations:${orientations.map((it) => it.name).join(",")}');
  }

  @override
  Future<void> setSystemUIOverlayStyle(SystemUiOverlayStyle style) async {
    final error = overlayError;
    if (error != null) {
      throw error;
    }
    lastOverlayStyle = style;
    events.add('overlay');
  }
}
