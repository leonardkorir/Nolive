import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/platform/android_playback_bridge.dart';
import 'package:nolive_app/src/features/room/application/room_fullscreen_session_ports.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// Plugin-backed implementations of the room fullscreen platform ports.
///
/// Keep every `floating` / `window_manager` / `wakelock_plus` / method-channel
/// touch in this file so the room application layer stays plugin-free.
class DefaultRoomAndroidPlaybackBridgeFacade
    implements RoomAndroidPlaybackBridgeFacade {
  DefaultRoomAndroidPlaybackBridgeFacade({AppPlatformCapabilities? platform})
    : _platform = platform ?? AppPlatformCapabilities.current();

  final AppPlatformCapabilities _platform;

  @override
  bool get isSupported => _platform.isAndroid;

  @override
  Future<bool> isInPictureInPictureMode() {
    return AndroidPlaybackBridge.instance.isInPictureInPictureMode();
  }

  @override
  Future<double?> getMediaVolume() {
    return AndroidPlaybackBridge.instance.getMediaVolume();
  }

  @override
  Future<bool> setMediaVolume(double value) {
    return AndroidPlaybackBridge.instance.setMediaVolume(value);
  }

  @override
  Future<bool> lockPortrait() {
    return AndroidPlaybackBridge.instance.lockPortrait();
  }

  @override
  Future<bool> restoreShellOrientation() {
    return AndroidPlaybackBridge.instance.restoreShellOrientation();
  }

  @override
  Future<bool> lockLandscape() {
    return AndroidPlaybackBridge.instance.lockLandscape();
  }

  @override
  Future<bool> lockPortraitFullscreen() {
    return AndroidPlaybackBridge.instance.lockPortraitFullscreen();
  }

  @override
  Future<bool> freezeFullscreenOrientation() {
    return AndroidPlaybackBridge.instance.freezeFullscreenOrientation();
  }

  @override
  Future<bool> prepareForPictureInPicture() {
    return AndroidPlaybackBridge.instance.prepareForPictureInPicture();
  }
}

/// Maps the plugin's status onto the application-facing [RoomPipStatus].
RoomPipStatus roomPipStatusFrom(PiPStatus status) {
  return switch (status) {
    PiPStatus.enabled => RoomPipStatus.enabled,
    PiPStatus.disabled => RoomPipStatus.disabled,
    PiPStatus.automatic => RoomPipStatus.automatic,
    PiPStatus.unavailable => RoomPipStatus.unavailable,
  };
}

class FloatingRoomPipHostFacade implements RoomPipHostFacade {
  FloatingRoomPipHostFacade({
    Floating? floating,
    AppPlatformCapabilities? platform,
  }) : _platform = platform ?? AppPlatformCapabilities.current(),
       // `floating` is Android-only; constructing/probing it on Linux/desktop
       // starts a 10ms timer that floods MissingPluginException and can
       // destabilize room enter. Only touch Floating on Android.
       _floating = (platform ?? AppPlatformCapabilities.current()).isAndroid
           ? (floating ?? Floating())
           : floating;

  final Floating? _floating;
  final AppPlatformCapabilities _platform;

  bool get _pipSupported => _platform.isAndroid && _floating != null;

  @override
  Future<bool> isPipAvailable() async {
    if (!_pipSupported) {
      return false;
    }
    try {
      return await _floating!.isPipAvailable;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<RoomPipStatus> get statusStream {
    if (!_pipSupported) {
      // Never subscribe to floating.pipStatusStream off-Android (10ms probe).
      return Stream<RoomPipStatus>.value(RoomPipStatus.unavailable);
    }
    return _floating!.pipStatusStream.map(roomPipStatusFrom);
  }

  @override
  Future<RoomPipStatus> enablePip({
    required RoomPipAspectRatio aspectRatio,
  }) async {
    if (!_pipSupported) {
      return RoomPipStatus.unavailable;
    }
    final rational = Rational(aspectRatio.width, aspectRatio.height);
    try {
      final status = await _floating!.enable(
        ImmediatePiP(aspectRatio: rational),
      );
      return roomPipStatusFrom(status);
    } catch (_) {
      try {
        return roomPipStatusFrom(await _floating!.enable(const ImmediatePiP()));
      } catch (_) {
        return RoomPipStatus.unavailable;
      }
    }
  }

  /// Widget-layer decoration, kept off [RoomPipHostFacade] so the application
  /// port stays free of both `floating` and `Widget`.
  Widget wrapSwitcher({
    required Widget childWhenDisabled,
    required Widget childWhenEnabled,
  }) {
    if (!_pipSupported) {
      return childWhenDisabled;
    }
    return PiPSwitcher(
      floating: _floating!,
      duration: Duration.zero,
      childWhenDisabled: childWhenDisabled,
      childWhenEnabled: childWhenEnabled,
    );
  }
}

/// Wraps [childWhenDisabled] in the platform PiP switcher when [host] is the
/// Android-backed implementation, and returns it unchanged otherwise.
///
/// The room page calls this instead of reaching through the application port,
/// which is what let the port drop its `Widget`-returning member.
Widget wrapWithRoomPipSwitcher({
  required RoomPipHostFacade host,
  required Widget childWhenDisabled,
  required Widget childWhenEnabled,
}) {
  if (host is! FloatingRoomPipHostFacade) {
    return childWhenDisabled;
  }
  return host.wrapSwitcher(
    childWhenDisabled: childWhenDisabled,
    childWhenEnabled: childWhenEnabled,
  );
}

class WindowManagerRoomDesktopWindowFacade implements RoomDesktopWindowFacade {
  WindowManagerRoomDesktopWindowFacade({AppPlatformCapabilities? platform})
    : _platform = platform ?? AppPlatformCapabilities.current();

  final AppPlatformCapabilities _platform;

  @override
  bool get isSupported => _platform.isDesktop;

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<bool> isAlwaysOnTop() => windowManager.isAlwaysOnTop();

  @override
  Future<bool> isResizable() => windowManager.isResizable();

  @override
  Future<void> setAlwaysOnTop(bool value) =>
      windowManager.setAlwaysOnTop(value);

  @override
  Future<void> setResizable(bool value) => windowManager.setResizable(value);

  @override
  Future<void> setBounds(Rect bounds, {bool animate = false}) {
    return windowManager.setBounds(bounds, animate: animate);
  }
}

class WakelockRoomScreenAwakeFacade implements RoomScreenAwakeFacade {
  const WakelockRoomScreenAwakeFacade();

  @override
  Future<void> toggle({required bool enabled}) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Linux/desktop builds may lack a wakelock plugin path; ignore.
    }
  }
}

class DefaultRoomSystemUiFacade implements RoomSystemUiFacade {
  const DefaultRoomSystemUiFacade();

  @override
  Future<void> setEnabledSystemUIMode(SystemUiMode mode) {
    return SystemChrome.setEnabledSystemUIMode(mode);
  }

  @override
  Future<void> setPreferredOrientations(List<DeviceOrientation> orientations) {
    return SystemChrome.setPreferredOrientations(orientations);
  }

  @override
  Future<void> setSystemUIOverlayStyle(SystemUiOverlayStyle style) async {
    SystemChrome.setSystemUIOverlayStyle(style);
  }
}

/// Production wiring for [RoomFullscreenSessionPlatforms].
RoomFullscreenSessionPlatforms defaultRoomFullscreenSessionPlatforms() {
  final platform = AppPlatformCapabilities.current();
  return RoomFullscreenSessionPlatforms(
    androidPlaybackBridge: DefaultRoomAndroidPlaybackBridgeFacade(
      platform: platform,
    ),
    pipHost: FloatingRoomPipHostFacade(platform: platform),
    desktopWindow: WindowManagerRoomDesktopWindowFacade(platform: platform),
    screenAwake: const WakelockRoomScreenAwakeFacade(),
    systemUi: const DefaultRoomSystemUiFacade(),
  );
}
