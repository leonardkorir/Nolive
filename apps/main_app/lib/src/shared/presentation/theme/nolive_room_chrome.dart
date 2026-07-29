import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_tokens.dart';

/// Shared look for player overlays, loading shells, and room toast chips.
///
/// Player surfaces stay dark-on-video; radii align with [NoliveRadii].
class NoliveRoomChrome {
  const NoliveRoomChrome._();

  static const Color scrimStrong = Color(0xAA000000);
  static const Color scrimMid = Color(0x88000000);
  static const Color scrimSoft = Color(0x66000000);
  static const Color scrimFaint = Color(0x22000000);

  static const Color panelFill = Color(0x9E000000); // ~0.62 black
  static const Color panelFillSoft = Color(0x8C000000); // ~0.55
  static const Color panelFillHeavy = Color(0xB8000000); // ~0.72

  static const Color onVideo = Colors.white;
  static const Color onVideoMuted = Colors.white70;

  /// Overlay card / chip radius (matches surface lg).
  static double panelRadius([BuildContext? context]) {
    if (context == null) {
      return NoliveRadii.standard.lg;
    }
    return NoliveRadii.of(context).lg;
  }

  static BorderRadius panelBorderRadius([BuildContext? context]) {
    return BorderRadius.circular(panelRadius(context));
  }

  static List<Color> posterGradient = const [scrimSoft, scrimFaint, scrimMid];

  static BoxDecoration panelDecoration({
    BuildContext? context,
    double alpha = 0.62,
  }) {
    return BoxDecoration(
      color: Colors.black.withValues(alpha: alpha),
      borderRadius: panelBorderRadius(context),
    );
  }
}
