import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';

typedef WrapTwitchPlayUrls = Future<List<LivePlayUrl>> Function({
  required LivePlayQuality quality,
  required List<LivePlayUrl> playUrls,
});

typedef WrapChaturbatePlayUrls = Future<List<LivePlayUrl>> Function({
  required LivePlayQuality quality,
  required List<LivePlayUrl> playUrls,
});

class ResolvePlaySourceUseCase {
  const ResolvePlaySourceUseCase(
    this.registry, {
    this.wrapChaturbatePlayUrls,
    this.wrapTwitchPlayUrls,
  });

  final ProviderRegistry registry;
  final WrapChaturbatePlayUrls? wrapChaturbatePlayUrls;
  final WrapTwitchPlayUrls? wrapTwitchPlayUrls;

  Future<ResolvedPlaySource> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
    bool preferHttps = false,
    List<LivePlayUrl>? preloadedPlayUrls,
  }) async {
    final provider = registry.create(providerId);
    final urls = preloadedPlayUrls ??
        await provider
            .requireContract<SupportsPlayUrls>(
              ProviderCapability.playUrls,
            )
            .fetchPlayUrls(
              detail: detail,
              quality: quality,
            );
    if (urls.isEmpty) {
      throw ProviderParseException(
        providerId: providerId,
        message: '${provider.descriptor.displayName} 当前没有返回可用播放地址。',
      );
    }
    var effectiveUrls = urls;
    if (providerId == ProviderId.chaturbate) {
      final proxied = await wrapChaturbatePlayUrls?.call(
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
        'stableFallbacks=${effectiveUrls.where(_isChaturbateStableFallback).length} '
        'lines=${_describeLines(effectiveUrls)}',
      );
    }
    if (providerId == ProviderId.twitch) {
      final proxied = await wrapTwitchPlayUrls?.call(
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
      ),
    );
  }

  LivePlayUrl _selectPrimaryUrl({
    required ProviderId providerId,
    required LivePlayQuality requestedQuality,
    required List<LivePlayUrl> urls,
    required bool preferHttps,
  }) {
    final preferred = _preferredUrlsForRequestedQuality(
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

  List<LivePlayUrl> _preferredUrlsForRequestedQuality({
    required ProviderId providerId,
    required LivePlayQuality requestedQuality,
    required List<LivePlayUrl> urls,
  }) {
    if (providerId == ProviderId.bilibili) {
      final requestedQn = int.tryParse(requestedQuality.id);
      final ordered = List<LivePlayUrl>.from(urls)
        ..sort((left, right) {
          return _compareBilibiliPlayUrls(
            left,
            right,
            requestedQn: requestedQn,
          );
        });
      if (requestedQn == null) {
        return ordered;
      }
      final exactMatch = ordered.where((item) {
        return _extractBilibiliEffectiveQn(item) == requestedQn;
      }).toList(growable: false);
      return exactMatch.isEmpty ? ordered : exactMatch;
    }
    if (providerId == ProviderId.chaturbate) {
      final ordered = List<LivePlayUrl>.from(urls);
      ordered.sort((left, right) {
        return _chaturbatePlaybackPriority(left).compareTo(
          _chaturbatePlaybackPriority(right),
        );
      });
      return ordered;
    }
    if (providerId == ProviderId.twitch) {
      final ordered = List<LivePlayUrl>.from(urls);
      ordered.sort((left, right) {
        return _twitchPlayerTypePriority(
          left.metadata?['playerType']?.toString(),
        ).compareTo(
          _twitchPlayerTypePriority(
            right.metadata?['playerType']?.toString(),
          ),
        );
      });
      return ordered;
    }
    if (providerId != ProviderId.douyu) {
      return urls;
    }
    final requestedRate = int.tryParse(requestedQuality.id);
    if (requestedRate == null) {
      return urls;
    }
    final exactMatch = urls.where((item) {
      return _extractIntMetadataValue(item, const ['rate']) == requestedRate;
    }).toList(growable: false);
    return exactMatch.isEmpty ? urls : exactMatch;
  }

  int _compareBilibiliPlayUrls(
    LivePlayUrl left,
    LivePlayUrl right, {
    required int? requestedQn,
  }) {
    final leftQn = _extractBilibiliEffectiveQn(left) ?? -1;
    final rightQn = _extractBilibiliEffectiveQn(right) ?? -1;
    if (requestedQn != null) {
      final leftExact = leftQn == requestedQn;
      final rightExact = rightQn == requestedQn;
      if (leftExact != rightExact) {
        return leftExact ? -1 : 1;
      }
    }
    final qualityCompare = rightQn.compareTo(leftQn);
    if (qualityCompare != 0) {
      return qualityCompare;
    }
    final leftPenalty = left.url.contains('mcdn') ? 1 : 0;
    final rightPenalty = right.url.contains('mcdn') ? 1 : 0;
    if (leftPenalty != rightPenalty) {
      return leftPenalty.compareTo(rightPenalty);
    }
    return 0;
  }

  int? _extractBilibiliEffectiveQn(LivePlayUrl item) {
    return _extractIntMetadataValue(item, const ['expectedQn', 'qn']) ??
        _extractIntQueryValue(item, const ['expected_qn', 'qn']);
  }

  int _chaturbatePlaybackPriority(LivePlayUrl playUrl) {
    if (_isChaturbateLlHlsProxy(playUrl)) {
      return 0;
    }
    if (_isChaturbateStableFallback(playUrl)) {
      return 1;
    }
    return 2;
  }

  int _twitchPlayerTypePriority(String? playerType) {
    switch (playerType?.trim().toLowerCase()) {
      case 'popout':
        return 0;
      case 'embed':
        return 1;
      case 'site':
        return 2;
      case 'autoplay':
        return 3;
    }
    return 99;
  }

  LivePlayQuality _resolveEffectiveQuality({
    required ProviderId providerId,
    required LivePlayQuality requestedQuality,
    required LivePlayUrl selectedUrl,
  }) {
    final effectiveId = switch (providerId) {
      ProviderId.bilibili => _extractBilibiliEffectiveQn(selectedUrl),
      ProviderId.douyu =>
        _extractIntMetadataValue(selectedUrl, const ['rate']) ??
            _extractIntQueryValue(selectedUrl, const ['rate']),
      ProviderId.huya => _extractIntQueryValue(selectedUrl, const ['ratio']),
      _ => null,
    };
    if (effectiveId == null || effectiveId.toString() == requestedQuality.id) {
      return requestedQuality;
    }

    final qualityMap =
        _readIntLabelMap(requestedQuality.metadata?['qualityMap']);
    final label = qualityMap[effectiveId];
    return LivePlayQuality(
      id: effectiveId.toString(),
      label: label ?? '实际 $effectiveId',
      sortOrder: effectiveId,
      metadata: {
        ...?requestedQuality.metadata,
        'requestedId': requestedQuality.id,
      },
    );
  }

  int? _extractIntQueryValue(LivePlayUrl item, List<String> keys) {
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      return null;
    }
    for (final key in keys) {
      final value = int.tryParse(uri.queryParameters[key] ?? '');
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _extractIntMetadataValue(LivePlayUrl item, List<String> keys) {
    final metadata = item.metadata;
    if (metadata == null) {
      return null;
    }
    for (final key in keys) {
      final value = int.tryParse(metadata[key]?.toString() ?? '');
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Map<int, String> _readIntLabelMap(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    final result = <int, String>{};
    for (final entry in raw.entries) {
      final key = int.tryParse(entry.key.toString());
      final value = entry.value?.toString();
      if (key == null || value == null || value.isEmpty) {
        continue;
      }
      result[key] = value;
    }
    return result;
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
}) {
  final audioUrl = playUrl.metadata?['audioUrl']?.toString().trim() ?? '';
  final masterPlaylistUrl =
      playUrl.metadata?['masterPlaylistUrl']?.toString().trim() ?? '';
  final masterPlaylistContent =
      playUrl.metadata?['masterPlaylistContent']?.toString() ?? '';
  final hlsBitrate = playUrl.metadata?['hlsBitrate']?.toString().trim() ?? '';
  final bufferProfile = resolvePlaybackBufferProfile(
    playUrl: playUrl,
    quality: quality,
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
    masterPlaylistUrl:
        masterPlaylistUrl.isEmpty ? null : Uri.parse(masterPlaylistUrl),
    masterPlaylistContent:
        masterPlaylistContent.trim().isEmpty ? null : masterPlaylistContent,
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

const _heavyStreamQualityKeywords = <String>[
  '蓝光30m',
  '蓝光',
  '原画',
];

@visibleForTesting
PlaybackBufferProfile resolvePlaybackBufferProfile({
  required LivePlayUrl playUrl,
  LivePlayQuality? quality,
}) {
  if (_isChaturbateLlHlsProxy(playUrl) ||
      _isChaturbateStableFallback(playUrl)) {
    return PlaybackBufferProfile.chaturbateLlHlsProxyStable;
  }

  if (_looksLikeMmcdnLowLatencySource(playUrl)) {
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

  final labels = <String>[
    quality?.label ?? '',
    playUrl.lineLabel ?? '',
  ];
  for (final label in labels) {
    if (_matchesHeavyStreamLabel(label)) {
      return PlaybackBufferProfile.heavyStreamStable;
    }
  }

  return PlaybackBufferProfile.defaultLowLatency;
}

List<LivePlayUrl> _ensureChaturbateStableFallbackUrls(List<LivePlayUrl> urls) {
  return urls.map((playUrl) {
    if (_isChaturbateLlHlsProxy(playUrl) ||
        _isChaturbateStableFallback(playUrl) ||
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
  }).toList(growable: false);
}

bool _isChaturbateStableFallback(LivePlayUrl playUrl) {
  return playUrl.metadata?['chaturbateStableFallback'] == true;
}

bool _isChaturbateLlHlsProxy(LivePlayUrl playUrl) {
  final proxyKind = playUrl.metadata?['proxyKind']?.toString().trim();
  if (proxyKind == 'chaturbate-llhls') {
    return true;
  }
  final uri = Uri.tryParse(playUrl.url);
  return uri != null && uri.path.contains('/chaturbate-llhls/');
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
    if (normalized.contains(keyword)) {
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
        uri.path.split('/').where((item) => item.isNotEmpty).take(2).join('/'));
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
}
