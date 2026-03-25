import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';

import 'twitch_ad_guard_proxy.dart';

class ResolvePlaySourceUseCase {
  const ResolvePlaySourceUseCase(
    this.registry, {
    this.twitchAdGuardProxy,
  });

  final ProviderRegistry registry;
  final TwitchAdGuardProxy? twitchAdGuardProxy;

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
    if (providerId == ProviderId.twitch) {
      final proxied = await twitchAdGuardProxy?.wrapPlayUrls(
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
      playbackSource: playbackSourceFromLivePlayUrl(primary),
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
      ProviderId.bilibili => _extractIntQueryValue(selectedUrl, const ['qn']),
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

PlaybackSource playbackSourceFromLivePlayUrl(LivePlayUrl playUrl) {
  final audioUrl = playUrl.metadata?['audioUrl']?.toString().trim() ?? '';
  if (kDebugMode) {
    debugPrint(
      '[ResolvePlaySource] build playback source '
      'line=${playUrl.lineLabel ?? '-'} '
      'video=${_shortPlaybackDescriptor(playUrl.url)} '
      'audio=${audioUrl.isEmpty ? '-' : _shortPlaybackDescriptor(audioUrl)}',
    );
  }
  return PlaybackSource(
    url: Uri.parse(playUrl.url),
    headers: playUrl.headers,
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
