/// Platform ports the room fullscreen session depends on.
///
/// Only the abstractions live here; every plugin-backed implementation sits in
/// `app/platform/room_fullscreen_session_platform_adapters.dart` so that this
/// layer never pulls in `floating`, `wakelock_plus`, `window_manager`, or the
/// Android method channel. Tests substitute fakes for these ports directly.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Picture-in-picture state, independent of the `floating` plugin's enum.
enum RoomPipStatus {
  /// The app is currently shrunk into a PiP window.
  enabled,

  /// The app is not floating over others.
  disabled,

  /// The app will shrink when the user next minimises it.
  automatic,

  /// PiP is not available on this device.
  unavailable,
}

/// Integral PiP aspect ratio, in the 1..4096 range Android accepts.
@immutable
class RoomPipAspectRatio {
  const RoomPipAspectRatio({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is RoomPipAspectRatio &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'RoomPipAspectRatio($width:$height)';
}

abstract class RoomAndroidPlaybackBridgeFacade {
  bool get isSupported;

  Future<bool> isInPictureInPictureMode();

  Future<double?> getMediaVolume();

  Future<bool> setMediaVolume(double value);

  /// Restores app-shell orientation. Channel name is historical `lockPortrait`;
  /// on ARC this re-arms **landscape-only** shell, not portrait.
  Future<bool> lockPortrait();

  /// Preferred name for [lockPortrait] at new call sites.
  Future<bool> restoreShellOrientation();

  Future<bool> lockLandscape();

  Future<bool> lockPortraitFullscreen();

  Future<bool> freezeFullscreenOrientation();

  Future<bool> prepareForPictureInPicture();
}

/// PiP host port.
///
/// State and control only. Wrapping the page in the plugin's switcher widget
/// is a widget-layer concern and lives in
/// `app/platform/room_pip_switcher.dart`.
abstract class RoomPipHostFacade {
  Future<bool> isPipAvailable();

  Stream<RoomPipStatus> get statusStream;

  Future<RoomPipStatus> enablePip({required RoomPipAspectRatio aspectRatio});
}

abstract class RoomDesktopWindowFacade {
  bool get isSupported;

  Future<Rect> getBounds();

  Future<bool> isAlwaysOnTop();

  Future<bool> isResizable();

  Future<void> setAlwaysOnTop(bool value);

  Future<void> setResizable(bool value);

  Future<void> setBounds(Rect bounds, {bool animate});
}

abstract class RoomScreenAwakeFacade {
  Future<void> toggle({required bool enabled});
}

abstract class RoomSystemUiFacade {
  Future<void> setEnabledSystemUIMode(SystemUiMode mode);

  Future<void> setPreferredOrientations(List<DeviceOrientation> orientations);

  Future<void> setSystemUIOverlayStyle(SystemUiOverlayStyle style);
}

/// Bundle of the platform ports a room fullscreen session needs.
///
/// Construct the production bundle with
/// `defaultRoomFullscreenSessionPlatforms()` from the platform adapter file.
class RoomFullscreenSessionPlatforms {
  const RoomFullscreenSessionPlatforms({
    required this.androidPlaybackBridge,
    required this.pipHost,
    required this.desktopWindow,
    required this.screenAwake,
    required this.systemUi,
  });

  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final RoomPipHostFacade pipHost;
  final RoomDesktopWindowFacade desktopWindow;
  final RoomScreenAwakeFacade screenAwake;
  final RoomSystemUiFacade systemUi;
}
