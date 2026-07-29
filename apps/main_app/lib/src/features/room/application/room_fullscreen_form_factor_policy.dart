import 'package:flutter/services.dart';

/// Compact phone uses shortestSide &lt; 600 logical px (Material adaptive).
const double kRoomFullscreenPhoneCompactShortestSide = 600;

/// How fullscreen applies orientation for form factor + video aspect.
///
/// Product matrix:
/// - **Chromebook ARC**: always [longEdgeLandscape] (no portrait shell/fullscreen).
/// - **Horizontal video**: always [longEdgeLandscape] on every device.
/// - **Vertical + phone**: [hardPortrait].
/// - **Vertical + non-ARC large tablet**: [userHoldPortraitOrLandscape].
enum RoomFullscreenVideoOrientationMode {
  /// Long-edge L/R only. All ARC sessions; all horizontal streams.
  longEdgeLandscape,

  /// Vertical streams on **phone only**: hard portrait.
  hardPortrait,

  /// Vertical streams on **non-ARC large tablets**: portraitUp + L/R landscape
  /// (user hold). Never selected for ARC.
  userHoldPortraitOrLandscape,
}

/// True for Chromebook ARC or large-screen tablets (not compact phones).
bool isRoomFullscreenLargeFormFactor({
  required Size screenSize,
  bool isArcChromeOs = false,
}) {
  if (isArcChromeOs) {
    return true;
  }
  return screenSize.shortestSide >= kRoomFullscreenPhoneCompactShortestSide;
}

/// Resolve fullscreen orientation mode (pure policy, no I/O).
RoomFullscreenVideoOrientationMode resolveRoomFullscreenVideoOrientationMode({
  required Size screenSize,
  required bool verticalVideo,
  bool isArcChromeOs = false,
}) {
  // Chromebook: landscape only (including vertical sources → letterbox).
  if (isArcChromeOs) {
    return RoomFullscreenVideoOrientationMode.longEdgeLandscape;
  }
  if (!verticalVideo) {
    return RoomFullscreenVideoOrientationMode.longEdgeLandscape;
  }
  if (isRoomFullscreenLargeFormFactor(
    screenSize: screenSize,
    isArcChromeOs: false,
  )) {
    return RoomFullscreenVideoOrientationMode.userHoldPortraitOrLandscape;
  }
  return RoomFullscreenVideoOrientationMode.hardPortrait;
}

/// App-wide orientations on phone / non-ARC (excludes reverse portrait).
const List<DeviceOrientation> kRoomAppPreferredOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Chromebook / ARC Flutter orientation list (startup shell only).
/// Room session paths on ARC use **native-only** orientation writes and must
/// not dual-write multi-orientation lists. This list never includes portrait.
const List<DeviceOrientation> kRoomArcLandscapeOnlyOrientations = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Flexible fullscreen orientations for non-ARC large-form vertical streams.
const List<DeviceOrientation> kRoomVerticalLargeFormOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// ChromeOS ARC version strings such as `R149-16667.55.0`.
///
/// Keep in sync with Kotlin [FullscreenLandscapeOrientationMemory.looksLikeArcChromeOsDevice]
/// R-build branch (fingerprint "cheets" is native-only).
bool looksLikeArcChromeOsVersion(String operatingSystemVersion) {
  final trimmed = operatingSystemVersion.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return RegExp(r'^R\d{2,4}-\d+').hasMatch(trimmed);
}
