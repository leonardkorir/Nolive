import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';

class ResolvePlaySourceUseCase {
  const ResolvePlaySourceUseCase(this.registry);

  final ProviderRegistry registry;

  Future<ResolvedPlaySource> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
    bool preferHttps = false,
  }) async {
    final provider = registry.create(providerId);
    final playUrlsContract = provider.requireContract<SupportsPlayUrls>(
      ProviderCapability.playUrls,
    );
    final urls = await playUrlsContract.fetchPlayUrls(
      detail: detail,
      quality: quality,
    );
    if (urls.isEmpty) {
      throw ProviderParseException(
        providerId: providerId,
        message: '${provider.descriptor.displayName} 当前没有返回可用播放地址。',
      );
    }
    final primary = _selectPrimaryUrl(
      providerId: providerId,
      requestedQuality: quality,
      urls: urls,
      preferHttps: preferHttps,
    );
    final effectiveQuality = _resolveEffectiveQuality(
      providerId: providerId,
      requestedQuality: quality,
      selectedUrl: primary,
    );

    return ResolvedPlaySource(
      quality: quality,
      effectiveQuality: effectiveQuality,
      playUrls: urls,
      playbackSource: PlaybackSource(
        url: Uri.parse(primary.url),
        headers: primary.headers,
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
