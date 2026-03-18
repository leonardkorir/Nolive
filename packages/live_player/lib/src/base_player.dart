import 'package:flutter/widgets.dart';

import 'player_backend.dart';
import 'player_state.dart';

abstract class BasePlayer {
  PlayerBackend get backend;

  Stream<PlayerState> get states;

  PlayerState get currentState;

  bool get supportsEmbeddedView;

  Future<void> initialize();

  Future<void> setSource(PlaybackSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double value);

  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  });

  Future<void> dispose();
}
