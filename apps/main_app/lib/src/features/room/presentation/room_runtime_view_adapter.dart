import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

class RoomRuntimeViewAdapter {
  const RoomRuntimeViewAdapter(this._runtime);

  final PlayerRuntimeController _runtime;

  bool get supportsEmbeddedView => _runtime.supportsEmbeddedView;

  bool get supportsScreenshot => _runtime.supportsScreenshot;

  Stream<PlayerDiagnostics> get diagnosticsStream => _runtime.diagnostics;

  PlayerDiagnostics get initialDiagnostics => _runtime.currentDiagnostics;

  String get backendLabel => _runtime.backend.name.toUpperCase();

  String get currentStatusLabel => _runtime.currentState.status.name;

  PlaybackSource? get currentPlaybackSource => _runtime.currentState.source;

  Widget buildEmbeddedView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return _runtime.buildView(
      key: key,
      aspectRatio: aspectRatio,
      fit: fit,
      pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
      resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
    );
  }
}
