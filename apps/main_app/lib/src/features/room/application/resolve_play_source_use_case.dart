import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/room/application/room_play_selection_policy.dart';

typedef WrapTwitchPlayUrls =
    Future<List<LivePlayUrl>> Function({
      required String roomId,
      required LivePlayQuality quality,
      required List<LivePlayUrl> playUrls,
    });

typedef WrapChaturbatePlayUrls =
    Future<List<LivePlayUrl>> Function({
      required String roomId,
      required LivePlayQuality quality,
      required List<LivePlayUrl> playUrls,
    });

typedef WrapStripchatPlayUrls =
    Future<List<LivePlayUrl>> Function({
      required String roomId,
      required LivePlayQuality quality,
      required List<LivePlayUrl> playUrls,
    });

class ResolvePlaySourceUseCase {
  const ResolvePlaySourceUseCase(
    this.registry, {
    this.wrapChaturbatePlayUrls,
    this.wrapStripchatPlayUrls,
    this.wrapTwitchPlayUrls,
  });

  final ProviderRegistry registry;
  final WrapChaturbatePlayUrls? wrapChaturbatePlayUrls;
  final WrapStripchatPlayUrls? wrapStripchatPlayUrls;
  final WrapTwitchPlayUrls? wrapTwitchPlayUrls;

  Future<ResolvedPlaySource> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
    bool preferHttps = false,
    List<LivePlayUrl>? preloadedPlayUrls,
  }) async {
    final provider = registry.create(providerId);
    final urls =
        preloadedPlayUrls ??
        await provider
            .requireContract<SupportsPlayUrls>(ProviderCapability.playUrls)
            .fetchPlayUrls(detail: detail, quality: quality);
    if (urls.isEmpty) {
      throw ProviderParseException(
        providerId: providerId,
        message: '${provider.descriptor.displayName} 当前没有返回可用播放地址。',
      );
    }
    var effectiveUrls = urls;
    if (providerId == ProviderId.chaturbate) {
      final proxied = await wrapChaturbatePlayUrls?.call(
        roomId: detail.roomId,
        quality: quality,
        playUrls: urls,
      );
      if (proxied != null && proxied.isNotEmpty) {
        effectiveUrls = proxied;
      }
      effectiveUrls = _ensureChaturbateStableFallbackUrls(effectiveUrls);
      _debugTrace(
        'chaturbate resolve quality=${quality.id}/${quality.label} '
        'source=${preloadedPlayUrls == null ? 'network' : 'preloaded'} '
        'urls=${urls.length} proxied=${effectiveUrls.length} '
        'stableFallbacks=${effectiveUrls.where(isChaturbateStableFallback).length} '
        'lines=${_describeLines(effectiveUrls)}',
      );
    }
    if (providerId == ProviderId.stripchat) {
      final proxied = await wrapStripchatPlayUrls?.call(
        roomId: detail.roomId,
        quality: quality,
        playUrls: urls,
      );
      if (proxied != null && proxied.isNotEmpty) {
        effectiveUrls = proxied;
      }
      effectiveUrls = _ensureStripchatStableFallbackUrls(effectiveUrls);
      _debugTrace(
        'stripchat resolve quality=${quality.id}/${quality.label} '
        'source=${preloadedPlayUrls == null ? 'network' : 'preloaded'} '
        'urls=${urls.length} proxied=${effectiveUrls.length} '
        'stableFallbacks=${effectiveUrls.where(isStripchatStableFallback).length} '
        'lines=${_describeLines(effectiveUrls)}',
      );
    }
    if (providerId == ProviderId.twitch) {
      final proxied = await wrapTwitchPlayUrls?.call(
        roomId: detail.roomId,
        quality: quality,
        playUrls: urls,
      );
      if (proxied != null && proxied.isNotEmpty) {
        effectiveUrls = proxied;
      }
      _debugTrace(
        'twitch resolve quality=${quality.id}/${quality.label} '
        'source=${preloadedPlayUrls == null ? 'network' : 'preloaded'} '
        'urls=${urls.length} proxied=${effectiveUrls.length} '
        'lines=${_describeLines(effectiveUrls)}',
      );
    }
    final primary = _selectPrimaryUrl(
      providerId: providerId,
      requestedQuality: quality,
      urls: effectiveUrls,
      preferHttps: preferHttps,
    );
    final effectiveQuality = _resolveEffectiveQuality(
      providerId: providerId,
      requestedQuality: quality,
      selectedUrl: primary,
    );
    if (providerId == ProviderId.twitch) {
      _debugTrace(
        'twitch selected quality=${quality.id} '
        'effective=${effectiveQuality.id}/${effectiveQuality.label} '
        'line=${primary.lineLabel ?? '-'} '
        'playerType=${primary.metadata?['playerType'] ?? '-'} '
        'url=${_summarizeUrl(primary.url)}',
      );
    }

    return ResolvedPlaySource(
      quality: quality,
      effectiveQuality: effectiveQuality,
      playUrls: effectiveUrls,
      playbackSource: playbackSourceFromLivePlayUrl(
        primary,
        quality: effectiveQuality,
        providerId: providerId,
      ),
    );
  }

  LivePlayUrl _selectPrimaryUrl({
    required ProviderId providerId,
    required LivePlayQuality requestedQuality,
    required List<LivePlayUrl> urls,
    required bool preferHttps,
  }) {
    final preferred = preferredPlayUrlsForQuality(
      providerId: providerId,
      requestedQuality: requestedQuality,
      urls: urls,
    );
    final candidates = preferred.isEmpty ? urls : preferred;
    if (!preferHttps) {
      return candidates.first;
    }
    return candidates.firstWhere(
      (item) => Uri.tryParse(item.url)?.scheme == 'https',
      orElse: () => candidates.first,
    );
  }

  LivePlayQuality _resolveEffectiveQuality({
    required ProviderId providerId,
    required LivePlayQuality requestedQuality,
    required LivePlayUrl selectedUrl,
  }) {
    return resolveEffectivePlayQuality(
      providerId: providerId,
      requestedQuality: requestedQuality,
      selectedUrl: selectedUrl,
    );
  }

  void _debugTrace(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[ResolvePlaySource] $message');
  }

  String _describeLines(List<LivePlayUrl> urls) {
    return urls
        .map(
          (item) =>
              '${item.lineLabel ?? '-'}:${item.metadata?['playerType'] ?? '-'}',
        )
        .join(', ');
  }

  String _summarizeUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return rawUrl;
    }
    return '${uri.host}${uri.path}';
  }
}

PlaybackSource playbackSourceFromLivePlayUrl(
  LivePlayUrl playUrl, {
  LivePlayQuality? quality,
  ProviderId? providerId,
  bool? isDesktop,
}) {
  final audioUrl = playUrl.metadata?['audioUrl']?.toString().trim() ?? '';
  final suppressMasterMetadata = _shouldSuppressMasterMetadataForPlaybackSource(
    playUrl,
  );
  final masterPlaylistUrl =
      playUrl.metadata?['masterPlaylistUrl']?.toString().trim() ?? '';
  final masterPlaylistContent =
      playUrl.metadata?['masterPlaylistContent']?.toString() ?? '';
  final hlsBitrate = playUrl.metadata?['hlsBitrate']?.toString().trim() ?? '';
  final bufferProfile = resolvePlaybackBufferProfile(
    playUrl: playUrl,
    quality: quality,
    providerId: providerId,
    isDesktop: isDesktop,
  );
  if (kDebugMode) {
    debugPrint(
      '[ResolvePlaySource] build playback source '
      'line=${playUrl.lineLabel ?? '-'} '
      'bufferProfile=${bufferProfile.name} '
      'hlsBitrate=${hlsBitrate.isEmpty ? '-' : hlsBitrate} '
      'master=${masterPlaylistUrl.isEmpty ? '-' : _shortPlaybackDescriptor(masterPlaylistUrl)} '
      'video=${_shortPlaybackDescriptor(playUrl.url)} '
      'audio=${audioUrl.isEmpty ? '-' : _shortPlaybackDescriptor(audioUrl)}',
    );
  }
  return PlaybackSource(
    url: Uri.parse(playUrl.url),
    headers: playUrl.headers,
    masterPlaylistUrl: suppressMasterMetadata || masterPlaylistUrl.isEmpty
        ? null
        : Uri.parse(masterPlaylistUrl),
    masterPlaylistContent:
        suppressMasterMetadata || masterPlaylistContent.trim().isEmpty
        ? null
        : masterPlaylistContent,
    bufferProfile: bufferProfile,
    hlsBitrate: hlsBitrate.isEmpty ? null : hlsBitrate,
    externalAudio: audioUrl.isEmpty
        ? null
        : PlaybackExternalMedia(
            url: Uri.parse(audioUrl),
            headers: _readHeadersMap(playUrl.metadata?['audioHeaders']),
            label: playUrl.metadata?['audioLineLabel']?.toString(),
            mimeType: playUrl.metadata?['audioMimeType']?.toString(),
          ),
  );
}

bool _shouldSuppressMasterMetadataForPlaybackSource(LivePlayUrl playUrl) {
  return isStripchatLlHlsProxy(playUrl);
}

// Labels that imply high bitrate / high resolution domestic FLV.
// Include 4K / 超高清 so "4K超高清" does not fall through to defaultLowLatency.
const _heavyStreamQualityKeywords = <String>[
  '蓝光30m',
  '蓝光',
  '原画',
  '4k',
  '4K',
  '超高清',
  'uhd',
  '2160',
  '1440',
  '2k',
  '2K',
];

/// Desktop host detection for buffer-profile resolution (injectable in tests).
@visibleForTesting
bool resolveIsDesktopPlaybackHost({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (isWeb ?? kIsWeb) {
    return false;
  }
  final resolved = platform ?? defaultTargetPlatform;
  return resolved == TargetPlatform.linux ||
      resolved == TargetPlatform.windows ||
      resolved == TargetPlatform.macOS;
}

@visibleForTesting
PlaybackBufferProfile resolvePlaybackBufferProfile({
  required LivePlayUrl playUrl,
  LivePlayQuality? quality,
  ProviderId? providerId,
  bool? isDesktop,
}) {
  // Android baseline (shared): Stripchat loopback proxy uses loopbackStableHls;
  // Chaturbate uses its own chaturbateLlHlsProxyStable profile. Do not cross-map.
  if (isStripchatLlHlsProxy(playUrl) || isStripchatStableFallback(playUrl)) {
    return PlaybackBufferProfile.loopbackStableHls;
  }
  if (isChaturbateLlHlsProxy(playUrl) || isChaturbateStableFallback(playUrl)) {
    return PlaybackBufferProfile.chaturbateLlHlsProxyStable;
  }

  if (_looksLikeMmcdnLowLatencySource(playUrl)) {
    return PlaybackBufferProfile.edgeLowLatencyHls;
  }
  if (_looksLikeDoppioLowLatencySource(playUrl)) {
    return PlaybackBufferProfile.edgeLowLatencyHls;
  }

  final width = _readIntAcrossMetadata(
    playUrl: playUrl,
    quality: quality,
    keys: const ['width'],
  );
  if (width != null && width >= 2560) {
    return PlaybackBufferProfile.heavyStreamStable;
  }

  final height = _readIntAcrossMetadata(
    playUrl: playUrl,
    quality: quality,
    keys: const ['height'],
  );
  if (height != null && height >= 1440) {
    return PlaybackBufferProfile.heavyStreamStable;
  }

  final bandwidth = _readIntAcrossMetadata(
    playUrl: playUrl,
    quality: quality,
    keys: const ['bandwidth'],
  );
  if (bandwidth != null && bandwidth >= 12000000) {
    return PlaybackBufferProfile.heavyStreamStable;
  }

  final bitrate = _readIntAcrossMetadata(
    playUrl: playUrl,
    quality: quality,
    keys: const ['bitrate', 'bitRate', 'averageBitrate'],
  );
  if (bitrate != null && bitrate >= 12000000) {
    return PlaybackBufferProfile.heavyStreamStable;
  }

  final labels = <String>[quality?.label ?? '', playUrl.lineLabel ?? ''];
  for (final label in labels) {
    if (_matchesHeavyStreamLabel(label)) {
      return PlaybackBufferProfile.heavyStreamStable;
    }
  }

  // Foreign live (Twitch / YouTube): multi-second cache on phone and desktop.
  // Delivery-only — does not change Auto ABR / quality business policy.
  // Phone used to fall through to defaultLowLatency (cache=no) and thrash on
  // ad-guard / 1080p HLS; desktop already used desktopStableLive successfully.
  // [isDesktop] remains for API compatibility / future host-only profile forks.
  if (_looksLikeForeignStableLive(
    playUrl: playUrl,
    providerId: providerId,
  )) {
    return PlaybackBufferProfile.desktopStableLive;
  }

  return PlaybackBufferProfile.defaultLowLatency;
}

/// Twitch / YouTube (and ad-guard loopback) — shared name kept for callers.
bool _looksLikeForeignStableLive({
  required LivePlayUrl playUrl,
  ProviderId? providerId,
}) {
  if (providerId == ProviderId.twitch || providerId == ProviderId.youtube) {
    return true;
  }
  final proxyKind = playUrl.metadata?['proxyKind']?.toString().trim() ?? '';
  if (proxyKind == 'twitch-ad-guard') {
    return true;
  }
  final uri = Uri.tryParse(playUrl.url);
  if (uri == null) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (path.contains('/twitch-ad-guard/')) {
    return true;
  }
  if (host.contains('ttvnw.net') ||
      host.contains('twitch.tv') ||
      host.endsWith('jtvnw.net')) {
    return true;
  }
  if (host.contains('googlevideo.com') ||
      host.contains('youtube.com') ||
      host.contains('youtu.be')) {
    return true;
  }
  final master =
      playUrl.metadata?['masterPlaylistUrl']?.toString().toLowerCase() ?? '';
  if (master.contains('googlevideo.com') || master.contains('youtube.com')) {
    return true;
  }
  return false;
}

List<LivePlayUrl> _ensureChaturbateStableFallbackUrls(List<LivePlayUrl> urls) {
  return urls
      .map((playUrl) {
        if (isChaturbateLlHlsProxy(playUrl) ||
            isChaturbateStableFallback(playUrl) ||
            !_looksLikeMmcdnLowLatencySource(playUrl)) {
          return playUrl;
        }
        return LivePlayUrl(
          url: playUrl.url,
          headers: playUrl.headers,
          lineLabel: playUrl.lineLabel,
          metadata: {
            ...?playUrl.metadata,
            'chaturbateStableFallback': true,
            'chaturbateProxyFallbackReason': 'proxy-unavailable',
          },
        );
      })
      .toList(growable: false);
}

List<LivePlayUrl> _ensureStripchatStableFallbackUrls(List<LivePlayUrl> urls) {
  return urls
      .map((playUrl) {
        if (isStripchatLlHlsProxy(playUrl) ||
            isStripchatStableFallback(playUrl)) {
          return playUrl;
        }
        final uri = Uri.tryParse(playUrl.url);
        final host = uri?.host.toLowerCase() ?? '';
        final isDoppio = host.contains('doppiocdn') || host.contains('strpst');
        if (!isDoppio) {
          return playUrl;
        }
        return LivePlayUrl(
          url: playUrl.url,
          headers: playUrl.headers,
          lineLabel: playUrl.lineLabel,
          metadata: {
            ...?playUrl.metadata,
            'stripchatStableFallback': true,
            'stripchatProxyFallbackReason': 'proxy-unavailable',
          },
        );
      })
      .toList(growable: false);
}

int? _readIntAcrossMetadata({
  required LivePlayUrl playUrl,
  required LivePlayQuality? quality,
  required List<String> keys,
}) {
  final sources = <Map<String, Object?>>[
    if (playUrl.metadata != null) playUrl.metadata!,
    if (quality?.metadata != null) quality!.metadata!,
  ];
  for (final metadata in sources) {
    for (final key in keys) {
      final value = int.tryParse(metadata[key]?.toString() ?? '');
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}

bool _matchesHeavyStreamLabel(String label) {
  final normalized = label.trim().toLowerCase().replaceAll(' ', '');
  if (normalized.isEmpty) {
    return false;
  }
  for (final keyword in _heavyStreamQualityKeywords) {
    final key = keyword.toLowerCase().replaceAll(' ', '');
    if (key.isNotEmpty && normalized.contains(key)) {
      return true;
    }
  }
  return false;
}

bool _looksLikeMmcdnLowLatencySource(LivePlayUrl playUrl) {
  final candidates = <String>[
    playUrl.url,
    playUrl.metadata?['audioUrl']?.toString() ?? '',
    playUrl.metadata?['masterPlaylistUrl']?.toString() ?? '',
  ];
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      continue;
    }
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (!host.endsWith('live.mmcdn.com')) {
      continue;
    }
    if (path.contains('/v1/edge/streams/') &&
        (path.contains('llhls') || path.endsWith('/llhls.m3u8'))) {
      return true;
    }
    if (path.contains('/live-hls/amlst:') &&
        path.endsWith('.m3u8') &&
        (path.contains('/chunklist_') || path.endsWith('/playlist.m3u8'))) {
      return true;
    }
  }
  return false;
}

bool _looksLikeDoppioLowLatencySource(LivePlayUrl playUrl) {
  final candidates = <String>[
    playUrl.url,
    playUrl.metadata?['audioUrl']?.toString() ?? '',
    playUrl.metadata?['masterPlaylistUrl']?.toString() ?? '',
  ];
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      continue;
    }
    final host = uri.host.toLowerCase();
    if (!(host.startsWith('media-hls.') || host.startsWith('edge-hls.'))) {
      continue;
    }
    if (!uri.path.toLowerCase().endsWith('.m3u8')) {
      continue;
    }
    if (uri.queryParameters['playlistType']?.toLowerCase() == 'lowlatency') {
      return true;
    }
  }
  return false;
}

Map<String, String> _readHeadersMap(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  final headers = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    final value = entry.value?.toString().trim() ?? '';
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    headers[key] = value;
  }
  return headers;
}

String _shortPlaybackDescriptor(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return rawUrl;
  }
  final itagMatch = RegExp(r'/itag/([^/]+)').firstMatch(uri.path);
  final idMatch = RegExp(r'/id/([^/]+)').firstMatch(uri.path);
  final parts = <String>[uri.host];
  if (itagMatch != null) {
    parts.add('itag=${itagMatch.group(1)}');
  }
  if (idMatch != null) {
    parts.add('id=${idMatch.group(1)}');
  }
  if (parts.length == 1) {
    parts.add(
      uri.path.split('/').where((item) => item.isNotEmpty).take(2).join('/'),
    );
  }
  return parts.join(' ');
}

class ResolvedPlaySource {
  const ResolvedPlaySource({
    required this.quality,
    required this.effectiveQuality,
    required this.playUrls,
    required this.playbackSource,
  });

  final LivePlayQuality quality;
  final LivePlayQuality effectiveQuality;
  final List<LivePlayUrl> playUrls;
  final PlaybackSource playbackSource;

  bool get isQualityFallback =>
      quality.id != effectiveQuality.id ||
      quality.label != effectiveQuality.label;

  bool get hasPdkeyHealthAlert {
    for (final playUrl in playUrls) {
      final checker = playUrl.metadata?['pdkeyHealthAlertChecker'];
      if (checker is bool Function() && checker()) {
        return true;
      }
    }
    return false;
  }
}
