import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/platform/android_playback_bridge.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

abstract class RoomAndroidPlaybackBridgeFacade {
  bool get isSupported;

  Future<bool> isInPictureInPictureMode();

  Future<double?> getMediaVolume();

  Future<bool> setMediaVolume(double value);

  Future<bool> lockPortrait();

  Future<bool> lockLandscape();

  Future<bool> lockPortraitFullscreen();

  Future<bool> prepareForPictureInPicture();
}

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
  Future<bool> lockLandscape() {
    return AndroidPlaybackBridge.instance.lockLandscape();
  }

  @override
  Future<bool> lockPortraitFullscreen() {
    return AndroidPlaybackBridge.instance.lockPortraitFullscreen();
  }

  @override
  Future<bool> prepareForPictureInPicture() {
    return AndroidPlaybackBridge.instance.prepareForPictureInPicture();
  }
}

abstract class RoomPipHostFacade {
  Future<bool> isPipAvailable();

  Stream<PiPStatus> get statusStream;

  Future<PiPStatus> enablePip({required Rational aspectRatio});

  Widget wrapSwitcher({
    required Widget childWhenDisabled,
    required Widget childWhenEnabled,
  });
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
  Stream<PiPStatus> get statusStream {
    if (!_pipSupported) {
      // Never subscribe to floating.pipStatusStream off-Android (10ms probe).
      return Stream<PiPStatus>.value(PiPStatus.unavailable);
    }
    return _floating!.pipStatusStream;
  }

  @override
  Future<PiPStatus> enablePip({required Rational aspectRatio}) async {
    if (!_pipSupported) {
      return PiPStatus.unavailable;
    }
    try {
      return await _floating!.enable(ImmediatePiP(aspectRatio: aspectRatio));
    } catch (_) {
      try {
        return await _floating!.enable(const ImmediatePiP());
      } catch (_) {
        return PiPStatus.unavailable;
      }
    }
  }

  @override
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

abstract class RoomDesktopWindowFacade {
  bool get isSupported;

  Future<Rect> getBounds();

  Future<bool> isAlwaysOnTop();

  Future<bool> isResizable();

  Future<void> setAlwaysOnTop(bool value);

  Future<void> setResizable(bool value);

  Future<void> setBounds(Rect bounds, {bool animate});
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

abstract class RoomScreenAwakeFacade {
  Future<void> toggle({required bool enabled});
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

abstract class RoomSystemUiFacade {
  Future<void> setEnabledSystemUIMode(SystemUiMode mode);

  Future<void> setPreferredOrientations(List<DeviceOrientation> orientations);

  Future<void> setSystemUIOverlayStyle(SystemUiOverlayStyle style);
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

class RoomFullscreenSessionPlatforms {
  const RoomFullscreenSessionPlatforms({
    required this.androidPlaybackBridge,
    required this.pipHost,
    required this.desktopWindow,
    required this.screenAwake,
    required this.systemUi,
  });

  factory RoomFullscreenSessionPlatforms.defaults() {
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

  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final RoomPipHostFacade pipHost;
  final RoomDesktopWindowFacade desktopWindow;
  final RoomScreenAwakeFacade screenAwake;
  final RoomSystemUiFacade systemUi;
}
