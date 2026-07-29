import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_provider_traits.dart';

/// Whether the player "自动画质（Auto）" switch should force adaptive auto on
/// room entry for this provider.
///
/// YouTube exposes an `auto` ladder entry, but that multi-variant master path
/// is unreliable under MPV; treat YouTube as fixed-tier only.
bool supportsAdaptiveAutoQuality(ProviderId providerId) {
  return roomProviderTraitsFor(providerId).supportsAdaptiveAutoQuality;
}

/// Adaptive "auto" tier used by Twitch / Chaturbate / Stripchat-style ladders.
LivePlayQuality? findAdaptiveAutoQuality(List<LivePlayQuality> qualities) {
  for (final quality in qualities) {
    if (quality.id.trim().toLowerCase() == 'auto') {
      return quality;
    }
  }
  return null;
}

/// Provider-aware startup quality selection used by [LoadRoomUseCase].
LivePlayQuality selectRoomStartupQuality({
  required ProviderId providerId,
  required List<LivePlayQuality> qualities,
}) {
  if (providerId == ProviderId.chaturbate) {
    return _selectHighestFixedQuality(qualities);
  }
  return _selectHighestQuality(qualities);
}

/// Provider-aware default quality selection used by [LoadRoomUseCase].
LivePlayQuality selectRoomDefaultQuality({
  required ProviderId providerId,
  required List<LivePlayQuality> qualities,
}) {
  if (providerId == ProviderId.chaturbate) {
    return _selectHighestFixedQuality(qualities);
  }
  return qualities.firstWhere(
    (item) => item.isDefault,
    orElse: () => qualities.first,
  );
}

/// Orders / filters play URLs for the requested quality before primary pick.
List<LivePlayUrl> preferredPlayUrlsForQuality({
  required ProviderId providerId,
  required LivePlayQuality requestedQuality,
  required List<LivePlayUrl> urls,
}) {
  if (providerId == ProviderId.bilibili) {
    final requestedQn = int.tryParse(requestedQuality.id);
    final ordered = List<LivePlayUrl>.from(urls)
      ..sort((left, right) {
        return compareBilibiliPlayUrls(left, right, requestedQn: requestedQn);
      });
    if (requestedQn == null) {
      return ordered;
    }
    final exactMatch = ordered
        .where((item) => extractBilibiliEffectiveQn(item) == requestedQn)
        .toList(growable: false);
    return exactMatch.isEmpty ? ordered : exactMatch;
  }
  if (providerId == ProviderId.chaturbate) {
    final ordered = List<LivePlayUrl>.from(urls);
    ordered.sort((left, right) {
      return chaturbatePlaybackPriority(
        left,
      ).compareTo(chaturbatePlaybackPriority(right));
    });
    return ordered;
  }
  if (providerId == ProviderId.twitch) {
    final ordered = List<LivePlayUrl>.from(urls);
    ordered.sort((left, right) {
      return twitchPlayerTypePriority(
        left.metadata?['playerType']?.toString(),
      ).compareTo(
        twitchPlayerTypePriority(right.metadata?['playerType']?.toString()),
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
  final exactMatch = urls
      .where((item) {
        return extractIntMetadataValue(item, const ['rate']) == requestedRate;
      })
      .toList(growable: false);
  return exactMatch.isEmpty ? urls : exactMatch;
}

LivePlayQuality resolveEffectivePlayQuality({
  required ProviderId providerId,
  required LivePlayQuality requestedQuality,
  required LivePlayUrl selectedUrl,
}) {
  final effectiveId = switch (providerId) {
    ProviderId.bilibili => extractBilibiliEffectiveQn(selectedUrl),
    ProviderId.douyu =>
      extractIntMetadataValue(selectedUrl, const ['rate']) ??
          extractIntQueryValue(selectedUrl, const ['rate']),
    ProviderId.huya => extractIntQueryValue(selectedUrl, const ['ratio']),
    _ => null,
  };
  if (effectiveId == null || effectiveId.toString() == requestedQuality.id) {
    return requestedQuality;
  }

  final qualityMap = readIntLabelMap(requestedQuality.metadata?['qualityMap']);
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

int compareBilibiliPlayUrls(
  LivePlayUrl left,
  LivePlayUrl right, {
  required int? requestedQn,
}) {
  final leftQn = extractBilibiliEffectiveQn(left) ?? -1;
  final rightQn = extractBilibiliEffectiveQn(right) ?? -1;
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

int? extractBilibiliEffectiveQn(LivePlayUrl item) {
  return extractIntMetadataValue(item, const ['expectedQn', 'qn']) ??
      extractIntQueryValue(item, const ['expected_qn', 'qn']);
}

int chaturbatePlaybackPriority(LivePlayUrl playUrl) {
  if (isChaturbateLlHlsProxy(playUrl)) {
    return 0;
  }
  if (isChaturbateStableFallback(playUrl)) {
    return 1;
  }
  return 2;
}

int twitchPlayerTypePriority(String? playerType) {
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

bool isChaturbateStableFallback(LivePlayUrl playUrl) {
  return playUrl.metadata?['chaturbateStableFallback'] == true;
}

bool isChaturbateLlHlsProxy(LivePlayUrl playUrl) {
  final proxyKind = playUrl.metadata?['proxyKind']?.toString().trim();
  if (proxyKind == 'chaturbate-llhls') {
    return true;
  }
  final uri = Uri.tryParse(playUrl.url);
  return uri != null && uri.path.contains('/chaturbate-llhls/');
}

bool isStripchatLlHlsProxy(LivePlayUrl playUrl) {
  final proxyKind = playUrl.metadata?['proxyKind']?.toString().trim();
  if (proxyKind == 'stripchat-llhls') {
    return true;
  }
  final uri = Uri.tryParse(playUrl.url);
  return uri != null && uri.path.contains('/stripchat-llhls/');
}

bool isStripchatStableFallback(LivePlayUrl playUrl) {
  return playUrl.metadata?['stripchatStableFallback'] == true;
}

int? extractIntQueryValue(LivePlayUrl item, List<String> keys) {
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

int? extractIntMetadataValue(LivePlayUrl item, List<String> keys) {
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

Map<int, String> readIntLabelMap(Object? raw) {
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

LivePlayQuality _selectHighestQuality(List<LivePlayQuality> qualities) {
  if (qualities.length == 1) {
    return qualities.first;
  }
  final sorted = [...qualities]
    ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
  return sorted.first;
}

LivePlayQuality _selectHighestFixedQuality(List<LivePlayQuality> qualities) {
  final fixedQualities = qualities
      .where((item) => item.id.trim().toLowerCase() != 'auto')
      .toList(growable: false);
  if (fixedQualities.isEmpty) {
    return _selectHighestQuality(qualities);
  }
  return _selectHighestQuality(fixedQualities);
}
