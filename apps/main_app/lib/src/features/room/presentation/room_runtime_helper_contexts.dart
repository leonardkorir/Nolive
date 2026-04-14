import 'dart:typed_data';

import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

class RoomRuntimeObservationContext {
  const RoomRuntimeObservationContext({
    required this.states,
    required this.diagnostics,
    required this.readCurrentState,
  });

  factory RoomRuntimeObservationContext.fromPlayerRuntime(
    PlayerRuntimeController runtime,
  ) {
    return RoomRuntimeObservationContext(
      states: runtime.states,
      diagnostics: runtime.diagnostics,
      readCurrentState: () => runtime.currentState,
    );
  }

  final Stream<PlayerState> states;
  final Stream<PlayerDiagnostics> diagnostics;
  final PlayerState Function() readCurrentState;
}

class RoomRuntimeInspectionContext {
  const RoomRuntimeInspectionContext({
    required this.readCurrentState,
    required this.resolveBackend,
  });

  factory RoomRuntimeInspectionContext.fromPlayerRuntime(
    PlayerRuntimeController runtime,
  ) {
    return RoomRuntimeInspectionContext(
      readCurrentState: () => runtime.currentState,
      resolveBackend: () => runtime.backend,
    );
  }

  final PlayerState Function() readCurrentState;
  final PlayerBackend Function() resolveBackend;
}

class RoomRuntimeControlContext {
  const RoomRuntimeControlContext({
    required this.readCurrentState,
    required this.resolveBackend,
    required this.ensureBackendWithoutPlaybackState,
    required this.resolveSupportsScreenshot,
    required this.captureScreenshot,
  });

  factory RoomRuntimeControlContext.fromPlayerRuntime(
    PlayerRuntimeController runtime,
  ) {
    return RoomRuntimeControlContext(
      readCurrentState: () => runtime.currentState,
      resolveBackend: () => runtime.backend,
      ensureBackendWithoutPlaybackState: runtime.ensureBackendWithoutPlaybackState,
      resolveSupportsScreenshot: () => runtime.supportsScreenshot,
      captureScreenshot: runtime.captureScreenshot,
    );
  }

  final PlayerState Function() readCurrentState;
  final PlayerBackend Function() resolveBackend;
  final Future<void> Function(PlayerBackend backend)
      ensureBackendWithoutPlaybackState;
  final bool Function() resolveSupportsScreenshot;
  final Future<Uint8List?> Function() captureScreenshot;

  bool get supportsScreenshot => resolveSupportsScreenshot();
}
