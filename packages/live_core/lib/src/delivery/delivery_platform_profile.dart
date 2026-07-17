/// Delivery-only runtime family for shared LL-HLS / CDN knobs.
///
/// One proxy implementation is shared across shells; **parameters** fork by
/// family so mobile and desktop do not share the same warm/sticky/CDN defaults.
///
/// Mapping (reserved for future shells):
/// - [mobile]: Android, iOS
/// - [desktop]: Linux, Windows, macOS
enum DeliveryPlatformFamily {
  /// Phone / tablet shells — last mobile-release thin delivery defaults.
  mobile,

  /// Desktop shells — current thick Linux delivery pipeline.
  desktop,
}

/// Active delivery family + surface defaults (CDN URL shape, etc.).
///
/// Bind once at app bootstrap via [bind]. Proxies and mappers read [active].
/// Defaults to [desktop] when unbound so unit tests keep the thick Linux path
/// unless they explicitly bind [mobile].
class DeliveryPlatformProfile {
  const DeliveryPlatformProfile._({
    required this.family,
    required this.stripchatDefaultCdnDomain,
    required this.stripchatMasterPlaylistQuery,
    required this.stripchatPreferNetCdnFirst,
  });

  final DeliveryPlatformFamily family;

  /// Mapper default when room metadata has no CDN list.
  final String stripchatDefaultCdnDomain;

  /// Query string for edge master URL (`?minHeight=...`).
  final String stripchatMasterPlaylistQuery;

  /// When true, pick doppiocdn.net before .org/.com (desktop HAR path).
  /// When false, first CDN from room config (mobile release behavior).
  final bool stripchatPreferNetCdnFirst;

  bool get isMobileFamily => family == DeliveryPlatformFamily.mobile;

  bool get isDesktopFamily => family == DeliveryPlatformFamily.desktop;

  /// Mobile / phone: last-release Stripchat surface (org + minHeight only).
  static const DeliveryPlatformProfile mobile = DeliveryPlatformProfile._(
    family: DeliveryPlatformFamily.mobile,
    stripchatDefaultCdnDomain: 'doppiocdn.org',
    stripchatMasterPlaylistQuery: '?minHeight=240',
    stripchatPreferNetCdnFirst: false,
  );

  /// Desktop: current Linux thick pipeline surface (.net + lowLatency).
  static const DeliveryPlatformProfile desktop = DeliveryPlatformProfile._(
    family: DeliveryPlatformFamily.desktop,
    stripchatDefaultCdnDomain: 'doppiocdn.net',
    stripchatMasterPlaylistQuery: '?minHeight=240&playlistType=lowLatency',
    stripchatPreferNetCdnFirst: true,
  );

  static DeliveryPlatformProfile? _active;

  /// Currently bound profile; unbound → [desktop] (Linux CI / package tests).
  static DeliveryPlatformProfile get active => _active ?? desktop;

  /// Bind once from app bootstrap (Android/iOS → mobile, Win/Linux/macOS → desktop).
  static void bind(DeliveryPlatformProfile profile) {
    _active = profile;
  }

  /// Test helper: clear binding so [active] falls back to [desktop].
  static void resetForTest() {
    _active = null;
  }

  /// Resolve family from OS flags. Win/macOS reserved as desktop; iOS as mobile.
  static DeliveryPlatformProfile resolve({
    required bool isAndroid,
    required bool isIOS,
    required bool isLinux,
    required bool isWindows,
    required bool isMacOS,
  }) {
    if (isAndroid || isIOS) {
      return mobile;
    }
    if (isLinux || isWindows || isMacOS) {
      return desktop;
    }
    // Web / unknown: conservative mobile-like surface.
    return mobile;
  }
}
