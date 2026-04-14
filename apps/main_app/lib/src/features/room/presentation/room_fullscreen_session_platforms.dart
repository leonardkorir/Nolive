import 'dart:io';

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  Future<bool> prepareForPictureInPicture();
}

class DefaultRoomAndroidPlaybackBridgeFacade
    implements RoomAndroidPlaybackBridgeFacade {
  const DefaultRoomAndroidPlaybackBridgeFacade();

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

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
  Future<bool> prepareForPictureInPicture() {
    return AndroidPlaybackBridge.instance.prepareForPictureInPicture();
  }
}

abstract class RoomPipHostFacade {
  Future<bool> isPipAvailable();

  Stream<PiPStatus> get statusStream;

  Future<PiPStatus> enablePip({
    required Rational aspectRatio,
  });

  Widget wrapSwitcher({
    required Widget childWhenDisabled,
    required Widget childWhenEnabled,
  });
}

class FloatingRoomPipHostFacade implements RoomPipHostFacade {
  FloatingRoomPipHostFacade({Floating? floating})
      : _floating = floating ?? Floating();

  final Floating _floating;

  @override
  Future<bool> isPipAvailable() {
    return _floating.isPipAvailable;
  }

  @override
  Stream<PiPStatus> get statusStream => _floating.pipStatusStream;

  @override
  Future<PiPStatus> enablePip({
    required Rational aspectRatio,
  }) async {
    try {
      return await _floating.enable(ImmediatePiP(aspectRatio: aspectRatio));
    } catch (_) {
      return _floating.enable(const ImmediatePiP());
    }
  }

  @override
  Widget wrapSwitcher({
    required Widget childWhenDisabled,
    required Widget childWhenEnabled,
  }) {
    if (kIsWeb || !Platform.isAndroid) {
      return childWhenDisabled;
    }
    return PiPSwitcher(
      floating: _floating,
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
  const WindowManagerRoomDesktopWindowFacade();

  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<bool> isAlwaysOnTop() => windowManager.isAlwaysOnTop();

  @override
  Future<bool> isResizable() => windowManager.isResizable();

  @override
  Future<void> setAlwaysOnTop(bool value) => windowManager.setAlwaysOnTop(value);

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
  Future<void> toggle({required bool enabled}) {
    return WakelockPlus.toggle(enable: enabled);
  }
}

abstract class RoomSystemUiFacade {
  Future<void> setEnabledSystemUIMode(SystemUiMode mode);

  Future<void> setPreferredOrientations(
    List<DeviceOrientation> orientations,
  );

  Future<void> setSystemUIOverlayStyle(SystemUiOverlayStyle style);
}

class DefaultRoomSystemUiFacade implements RoomSystemUiFacade {
  const DefaultRoomSystemUiFacade();

  @override
  Future<void> setEnabledSystemUIMode(SystemUiMode mode) {
    return SystemChrome.setEnabledSystemUIMode(mode);
  }

  @override
  Future<void> setPreferredOrientations(
    List<DeviceOrientation> orientations,
  ) {
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
    return RoomFullscreenSessionPlatforms(
      androidPlaybackBridge: const DefaultRoomAndroidPlaybackBridgeFacade(),
      pipHost: FloatingRoomPipHostFacade(),
      desktopWindow: const WindowManagerRoomDesktopWindowFacade(),
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
