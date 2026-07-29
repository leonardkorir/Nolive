import 'package:live_core/live_core.dart';

/// Per-provider room capabilities, declared once instead of re-derived from
/// `providerId == ProviderId.<site>` comparisons scattered across the feature.
///
/// Adding a provider used to mean hunting for every site-specific `if` in the
/// room layer and guessing which ones applied. With this table it means adding
/// one row and deciding each field explicitly; [roomProviderTraitsTable] is
/// asserted to cover every [ProviderId.knownValues] entry.
///
/// Only genuine *capabilities* live here. Per-site parsing quirks (quality id
/// extraction, play-source URL shaping, danmaku error semantics) stay with the
/// code that owns them — folding those into a table would just move the switch.
class RoomProviderTraits {
  const RoomProviderTraits({
    this.usesGenericMultiLineFailover = true,
    this.allowsRoomDetailOverride = true,
    this.autoRecoversUnexpectedStop = true,
    this.prefersMpvOnAndroid = false,
    this.promotesAndroidAutoQualityAtStartup = false,
    this.usesHeadlessStartupPromotion = false,
    this.usesLadderStartupQualityPlan = false,
    this.usesFixedLineRecovery = false,
    this.supportsAdaptiveAutoQuality = true,
    this.resetsRecoveryOnManualLineSwitch = false,
    this.skipsEquivalentProxyRebind = false,
    this.waitsForSurfaceOnInitialBootstrap = false,
    this.retainsPlaybackOnReloadParseFailure = false,
    this.playbackRebindSettleDelay = Duration.zero,
    this.initialBootstrapSettleDelay = Duration.zero,
  });

  /// May use the generic multi-line CDN failover loop.
  ///
  /// Providers that own specialized recovery opt out so the two paths do not
  /// fight over the same rebind.
  final bool usesGenericMultiLineFailover;

  /// A failed provider `fetchRoomDetail` may fall back to the app-level
  /// WebView-assisted override.
  final bool allowsRoomDetailOverride;

  /// An unexpected playback stop may schedule an automatic recovery.
  final bool autoRecoversUnexpectedStop;

  /// Force the mpv backend on Android regardless of the user's preference.
  final bool prefersMpvOnAndroid;

  /// On Android, promote a startup request to the adaptive `auto` rendition.
  final bool promotesAndroidAutoQualityAtStartup;

  /// Uses the headless startup-promotion recovery controller.
  final bool usesHeadlessStartupPromotion;

  /// Resolves its startup quality through the ladder startup plan (promotion
  /// from a fixed tier up to adaptive `auto` once playback is healthy).
  final bool usesLadderStartupQualityPlan;

  /// Recovers a stalled fixed-tier stream by switching lines rather than
  /// waiting for the generic failover loop.
  final bool usesFixedLineRecovery;

  /// The "自动画质（Auto）" switch may force the adaptive `auto` rendition on
  /// room entry.
  ///
  /// YouTube exposes an `auto` ladder entry, but that multi-variant master
  /// path is unreliable under mpv, so it is treated as fixed-tier only.
  final bool supportsAdaptiveAutoQuality;

  /// Manual line switches must reset the recovery controller first.
  final bool resetsRecoveryOnManualLineSwitch;

  /// A resolved source that is equivalent to the live proxy source may skip
  /// the rebind entirely.
  final bool skipsEquivalentProxyRebind;

  /// The first bootstrap of a room must wait for a rendered frame before
  /// issuing play, so the platform surface exists.
  final bool waitsForSurfaceOnInitialBootstrap;

  /// Keep the currently playing source when a room reload fails to parse.
  final bool retainsPlaybackOnReloadParseFailure;

  /// Settle time between binding a source and issuing play, on rebinds.
  final Duration playbackRebindSettleDelay;

  /// Settle time between binding a source and issuing play, on the first
  /// bootstrap of a room (no previous source).
  final Duration initialBootstrapSettleDelay;
}

/// Behaviour for a provider the room layer has no explicit row for.
///
/// Matches what the previous scattered `providerId != ProviderId.x` checks did
/// for unknown ids: full generic handling, no site-specific workarounds.
const RoomProviderTraits kDefaultRoomProviderTraits = RoomProviderTraits();

/// Room capabilities per provider.
final Map<ProviderId, RoomProviderTraits> roomProviderTraitsTable = {
  ProviderId.bilibili: const RoomProviderTraits(),
  ProviderId.douyu: const RoomProviderTraits(),
  ProviderId.huya: const RoomProviderTraits(),
  ProviderId.douyin: const RoomProviderTraits(),

  // Chaturbate room detail + danmaku bootstrap must stay on the pure-Dart
  // provider path; WebView overrides hang list fan-out and strip tokens.
  // Playback runs through a local proxy, so an equivalent resolved source is
  // a no-op rebind.
  ProviderId.chaturbate: const RoomProviderTraits(
    usesGenericMultiLineFailover: false,
    allowsRoomDetailOverride: false,
    prefersMpvOnAndroid: true,
    skipsEquivalentProxyRebind: true,
  ),

  // Twitch owns startup quality promotion and needs a settle window between
  // setSource and play, longer on the very first bootstrap.
  ProviderId.twitch: const RoomProviderTraits(
    usesGenericMultiLineFailover: false,
    prefersMpvOnAndroid: true,
    usesHeadlessStartupPromotion: true,
    usesLadderStartupQualityPlan: true,
    usesFixedLineRecovery: true,
    resetsRecoveryOnManualLineSwitch: true,
    waitsForSurfaceOnInitialBootstrap: true,
    playbackRebindSettleDelay: Duration(milliseconds: 120),
    initialBootstrapSettleDelay: Duration(milliseconds: 220),
  ),

  // Stripchat streams depend on JS-bridge key decryption and private-mode/P2P
  // transitions, so blind hot-retries loop forever once a broadcaster goes
  // private or a key expires.
  ProviderId.stripchat: const RoomProviderTraits(
    usesGenericMultiLineFailover: false,
    autoRecoversUnexpectedStop: false,
    prefersMpvOnAndroid: true,
    usesHeadlessStartupPromotion: true,
  ),

  // YouTube exposes a real adaptive rendition worth preferring at startup, and
  // its reload parse failures are usually transient signature churn, so the
  // already-playing source is kept.
  ProviderId.youtube: const RoomProviderTraits(
    prefersMpvOnAndroid: true,
    promotesAndroidAutoQualityAtStartup: true,
    supportsAdaptiveAutoQuality: false,
    retainsPlaybackOnReloadParseFailure: true,
  ),
};

/// Room capabilities for [providerId], falling back to
/// [kDefaultRoomProviderTraits] for providers with no explicit row.
RoomProviderTraits roomProviderTraitsFor(ProviderId providerId) {
  return roomProviderTraitsTable[providerId] ?? kDefaultRoomProviderTraits;
}
