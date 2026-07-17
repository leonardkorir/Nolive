import 'package:live_core/live_core.dart';

/// Delivery-only knobs for shared SC / Twitch loopback proxies.
///
/// **Not** two products — one proxy code path; parameters fork by
/// [DeliveryPlatformFamily]:
/// - [mobile]: last mobile-release thin behavior (warm=3, no Auto prewarm,
///   no sticky/history thicken gates, no Twitch sticky/byte-cache/warm).
/// - [desktop]: current Linux thick pipeline (sticky, history, edge warm,
///   Auto top-N prewarm, Twitch sticky + asset cache).
class HlsProxyDeliveryKnobs {
  const HlsProxyDeliveryKnobs({
    required this.family,
    required this.scCachedAssetLimit,
    required this.scWarmAssetPrefetchLimit,
    required this.scWarmInitAssetCount,
    required this.scWarmConcurrency,
    required this.scWarmWaitTimeout,
    required this.scHighWarmWaitTimeout,
    required this.scHighEdgeWarmCount,
    required this.scHighEdgeWarmWait,
    required this.scHighNewMediaWarmWait,
    required this.scNeighborWarmAhead,
    required this.scPrimeEdgeWarmWait,
    required this.scPlaylistEdgeWarmMinCached,
    required this.scPlaylistFetchTimeout,
    required this.scPlaylistStickyMaxAge,
    required this.scHighPlaylistStickyMaxAge,
    required this.scPlaylistStickyStaleServeMaxAge,
    required this.scPlaylistBackgroundMinInterval,
    required this.scHighPlaylistBackgroundMinInterval,
    required this.scPlaylistPumpInterval,
    required this.scHighPlaylistPumpInterval,
    required this.scPrefetchTransientRetries,
    required this.scPrefetchRetryDelay,
    required this.scAutoPrewarmTopVariants,
    required this.scMediaStickySlotLimit,
    required this.scStableEdgeTrimSegments,
    required this.scMinPublishCachedMediaSegments,
    required this.scPreferPublishCachedMediaSegments,
    required this.scHighMinPublishMediaSegments,
    required this.scHighPreferPublishMediaSegments,
    required this.scHighMaxHistoryExtras,
    required this.scMidMinPublishMediaSegments,
    required this.scMidPreferPublishMediaSegments,
    required this.scMidMaxHistoryExtras,
    required this.scLowMaxHistoryExtras,
    required this.scPublishWarmWaitFirst,
    required this.scHighPublishWarmWaitFirst,
    required this.scPublishWarmWaitBackground,
    required this.scHighPublishWarmWaitBackground,
    required this.scPublishWarmRetry,
    required this.scHighPublishWarmRetry,
    required this.scThinStickyRefreshWait,
    required this.scConnectionTimeout,
    required this.scIdleTimeout,
    required this.scMaxConnectionsPerHost,
    required this.scKnownCdnDomains,
    required this.scSimplePublish,
    required this.twitchMaxConnectionsPerHost,
    required this.twitchStickyCandidateTtl,
    required this.twitchAssetBytesCacheLimit,
    required this.twitchAssetWarmPrefetchLimit,
    required this.twitchEnableStickyCandidate,
    required this.twitchEnableAssetByteCache,
    required this.twitchPreferStartupAutoLadder,
    required this.twitchVariantPlaylistStickyTtl,
    required this.twitchPrewarmStartupVariants,
  });

  final DeliveryPlatformFamily family;

  // --- Stripchat ---
  final int scCachedAssetLimit;
  final int scWarmAssetPrefetchLimit;
  final int scWarmInitAssetCount;
  final int scWarmConcurrency;
  final Duration scWarmWaitTimeout;
  final Duration scHighWarmWaitTimeout;
  final int scHighEdgeWarmCount;
  final Duration scHighEdgeWarmWait;
  final Duration scHighNewMediaWarmWait;
  final int scNeighborWarmAhead;
  final Duration scPrimeEdgeWarmWait;
  final int scPlaylistEdgeWarmMinCached;
  final Duration scPlaylistFetchTimeout;
  final Duration scPlaylistStickyMaxAge;
  final Duration scHighPlaylistStickyMaxAge;
  final Duration scPlaylistStickyStaleServeMaxAge;
  final Duration scPlaylistBackgroundMinInterval;
  final Duration scHighPlaylistBackgroundMinInterval;
  final Duration scPlaylistPumpInterval;
  final Duration scHighPlaylistPumpInterval;
  final int scPrefetchTransientRetries;
  final Duration scPrefetchRetryDelay;
  final int scAutoPrewarmTopVariants;
  final int scMediaStickySlotLimit;
  final int scStableEdgeTrimSegments;
  final int scMinPublishCachedMediaSegments;
  final int scPreferPublishCachedMediaSegments;
  final int scHighMinPublishMediaSegments;
  final int scHighPreferPublishMediaSegments;
  final int scHighMaxHistoryExtras;
  final int scMidMinPublishMediaSegments;
  final int scMidPreferPublishMediaSegments;
  final int scMidMaxHistoryExtras;
  final int scLowMaxHistoryExtras;
  final Duration scPublishWarmWaitFirst;
  final Duration scHighPublishWarmWaitFirst;
  final Duration scPublishWarmWaitBackground;
  final Duration scHighPublishWarmWaitBackground;
  final Duration scPublishWarmRetry;
  final Duration scHighPublishWarmRetry;
  final Duration scThinStickyRefreshWait;
  final Duration scConnectionTimeout;
  final Duration scIdleTimeout;
  final int scMaxConnectionsPerHost;
  final List<String> scKnownCdnDomains;

  /// Release-like path: rewrite full media playlist and warm a few assets;
  /// skip sticky edge gates, history thicken, and Auto top-N prewarm storms.
  final bool scSimplePublish;

  // --- Twitch ---
  /// Null = do not set [HttpClient.maxConnectionsPerHost] (release).
  final int? twitchMaxConnectionsPerHost;
  final Duration twitchStickyCandidateTtl;
  final int twitchAssetBytesCacheLimit;
  final int twitchAssetWarmPrefetchLimit;
  final bool twitchEnableStickyCandidate;
  final bool twitchEnableAssetByteCache;

  /// When true, Auto master only exposes ≤480p ladder (still multi-variant Auto
  /// ABR). Speeds phone open; fixed qualities still use full groups.
  final bool twitchPreferStartupAutoLadder;

  /// Cache rewritten media playlist per Auto group so ABR re-polls skip CDN probe.
  final Duration twitchVariantPlaylistStickyTtl;

  /// Background-prewarm lowest N Auto variants after session create.
  final int twitchPrewarmStartupVariants;

  bool get isMobileFamily => family == DeliveryPlatformFamily.mobile;

  bool get isDesktopFamily => family == DeliveryPlatformFamily.desktop;

  /// Mobile delivery: keep Auto multi-variant ABR, thicken proxy/cache enough
  /// for phone nets (Twitch Auto + SC cold starts). Not a full desktop history
  /// pipeline — no history thicken / high publish waits.
  static const HlsProxyDeliveryKnobs mobile = HlsProxyDeliveryKnobs(
    family: DeliveryPlatformFamily.mobile,
    scCachedAssetLimit: 180,
    scWarmAssetPrefetchLimit: 8,
    scWarmInitAssetCount: 2,
    scWarmConcurrency: 8,
    scWarmWaitTimeout: Duration(milliseconds: 1000),
    scHighWarmWaitTimeout: Duration(milliseconds: 2000),
    scHighEdgeWarmCount: 3,
    scHighEdgeWarmWait: Duration(milliseconds: 0),
    scHighNewMediaWarmWait: Duration(milliseconds: 0),
    scNeighborWarmAhead: 4,
    scPrimeEdgeWarmWait: Duration(milliseconds: 600),
    scPlaylistEdgeWarmMinCached: 2,
    scPlaylistFetchTimeout: Duration(seconds: 10),
    // Short sticky so phone does not re-hit CDN every ABR poll.
    scPlaylistStickyMaxAge: Duration(seconds: 3),
    scHighPlaylistStickyMaxAge: Duration(seconds: 2),
    scPlaylistStickyStaleServeMaxAge: Duration(seconds: 10),
    scPlaylistBackgroundMinInterval: Duration(milliseconds: 900),
    scHighPlaylistBackgroundMinInterval: Duration(milliseconds: 500),
    scPlaylistPumpInterval: Duration(milliseconds: 2200),
    scHighPlaylistPumpInterval: Duration(milliseconds: 1200),
    scPrefetchTransientRetries: 1,
    scPrefetchRetryDelay: Duration(milliseconds: 120),
    // Cache-ahead top media children only — master stays multi-variant Auto.
    scAutoPrewarmTopVariants: 2,
    scMediaStickySlotLimit: 6,
    scStableEdgeTrimSegments: 0,
    scMinPublishCachedMediaSegments: 1,
    scPreferPublishCachedMediaSegments: 2,
    scHighMinPublishMediaSegments: 1,
    scHighPreferPublishMediaSegments: 2,
    scHighMaxHistoryExtras: 0,
    scMidMinPublishMediaSegments: 1,
    scMidPreferPublishMediaSegments: 2,
    scMidMaxHistoryExtras: 0,
    scLowMaxHistoryExtras: 0,
    scPublishWarmWaitFirst: Duration.zero,
    scHighPublishWarmWaitFirst: Duration.zero,
    scPublishWarmWaitBackground: Duration.zero,
    scHighPublishWarmWaitBackground: Duration.zero,
    scPublishWarmRetry: Duration.zero,
    scHighPublishWarmRetry: Duration.zero,
    scThinStickyRefreshWait: Duration(milliseconds: 300),
    scConnectionTimeout: Duration(seconds: 15),
    scIdleTimeout: Duration(seconds: 15),
    scMaxConnectionsPerHost: 24,
    scKnownCdnDomains: <String>[
      'doppiocdn.com',
      'doppiocdn.org',
      'doppiocdn.net',
      'doppiocdn.media',
    ],
    // Full rewritten media playlist + light sticky (no history thicken).
    scSimplePublish: true,
    // Align Twitch delivery with the desktop path that already plays Auto.
    twitchMaxConnectionsPerHost: 24,
    twitchStickyCandidateTtl: Duration(seconds: 12),
    twitchAssetBytesCacheLimit: 64,
    // More ahead segments so 480p Auto does not underrun while CDN RTT is high.
    twitchAssetWarmPrefetchLimit: 8,
    twitchEnableStickyCandidate: true,
    twitchEnableAssetByteCache: true,
    // Never collapse Auto master ladder on phone — Auto stays full multi-variant.
    twitchPreferStartupAutoLadder: false,
    twitchVariantPlaylistStickyTtl: Duration(seconds: 12),
    twitchPrewarmStartupVariants: 4,
  );

  /// Current Linux thick delivery (HEAD after 487db61 hardening).
  static const HlsProxyDeliveryKnobs desktop = HlsProxyDeliveryKnobs(
    family: DeliveryPlatformFamily.desktop,
    scCachedAssetLimit: 200,
    scWarmAssetPrefetchLimit: 16,
    scWarmInitAssetCount: 2,
    scWarmConcurrency: 16,
    scWarmWaitTimeout: Duration(milliseconds: 1200),
    scHighWarmWaitTimeout: Duration(milliseconds: 4500),
    scHighEdgeWarmCount: 4,
    scHighEdgeWarmWait: Duration(milliseconds: 2000),
    scHighNewMediaWarmWait: Duration(milliseconds: 2200),
    scNeighborWarmAhead: 8,
    scPrimeEdgeWarmWait: Duration(milliseconds: 900),
    scPlaylistEdgeWarmMinCached: 3,
    scPlaylistFetchTimeout: Duration(seconds: 4),
    scPlaylistStickyMaxAge: Duration(seconds: 5),
    scHighPlaylistStickyMaxAge: Duration(seconds: 2),
    scPlaylistStickyStaleServeMaxAge: Duration(seconds: 12),
    scPlaylistBackgroundMinInterval: Duration(milliseconds: 700),
    scHighPlaylistBackgroundMinInterval: Duration(milliseconds: 200),
    scPlaylistPumpInterval: Duration(milliseconds: 1800),
    scHighPlaylistPumpInterval: Duration(milliseconds: 500),
    scPrefetchTransientRetries: 1,
    scPrefetchRetryDelay: Duration(milliseconds: 120),
    scAutoPrewarmTopVariants: 3,
    scMediaStickySlotLimit: 6,
    scStableEdgeTrimSegments: 1,
    scMinPublishCachedMediaSegments: 2,
    scPreferPublishCachedMediaSegments: 3,
    scHighMinPublishMediaSegments: 3,
    scHighPreferPublishMediaSegments: 8,
    scHighMaxHistoryExtras: 6,
    scMidMinPublishMediaSegments: 2,
    scMidPreferPublishMediaSegments: 4,
    scMidMaxHistoryExtras: 3,
    scLowMaxHistoryExtras: 4,
    scPublishWarmWaitFirst: Duration(milliseconds: 2200),
    scHighPublishWarmWaitFirst: Duration(milliseconds: 3600),
    scPublishWarmWaitBackground: Duration(milliseconds: 1800),
    scHighPublishWarmWaitBackground: Duration(milliseconds: 2400),
    scPublishWarmRetry: Duration(milliseconds: 900),
    scHighPublishWarmRetry: Duration(milliseconds: 1200),
    scThinStickyRefreshWait: Duration(milliseconds: 550),
    scConnectionTimeout: Duration(seconds: 5),
    scIdleTimeout: Duration(seconds: 15),
    scMaxConnectionsPerHost: 24,
    scKnownCdnDomains: <String>[
      'doppiocdn.net',
      'doppiocdn.org',
      'doppiocdn.com',
      'doppiocdn.media',
    ],
    scSimplePublish: false,
    twitchMaxConnectionsPerHost: 16,
    twitchStickyCandidateTtl: Duration(seconds: 10),
    twitchAssetBytesCacheLimit: 48,
    twitchAssetWarmPrefetchLimit: 4,
    twitchEnableStickyCandidate: true,
    twitchEnableAssetByteCache: true,
    // Desktop nets tolerate full Auto ladder; still cache variants + light prewarm.
    twitchPreferStartupAutoLadder: false,
    twitchVariantPlaylistStickyTtl: Duration(seconds: 8),
    twitchPrewarmStartupVariants: 3,
  );

  static HlsProxyDeliveryKnobs forFamily(DeliveryPlatformFamily family) {
    switch (family) {
      case DeliveryPlatformFamily.mobile:
        return mobile;
      case DeliveryPlatformFamily.desktop:
        return desktop;
    }
  }

  static HlsProxyDeliveryKnobs fromActiveProfile() {
    return forFamily(DeliveryPlatformProfile.active.family);
  }
}
