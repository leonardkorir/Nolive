import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'player_backend.dart';
import 'player_diagnostics.dart';
import 'player_state.dart';

abstract class BasePlayer {
  PlayerBackend get backend;

  Stream<PlayerState> get states;

  Stream<PlayerDiagnostics> get diagnostics;

  PlayerState get currentState;

  PlayerDiagnostics get currentDiagnostics;

  bool get supportsEmbeddedView;

  bool get supportsScreenshot;

  Future<void> initialize();

  Future<void> setSource(PlaybackSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double value);

  Future<Uint8List?> captureScreenshot();

  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  });

  Future<void> dispose();
}
