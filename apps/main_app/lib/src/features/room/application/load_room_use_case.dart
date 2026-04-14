import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';

const LivePlayQuality _kUnavailablePlayQuality = LivePlayQuality(
  id: 'unavailable',
  label: '不可用',
  isDefault: true,
);

class LoadRoomUseCase {
  const LoadRoomUseCase(
    this.registry, {
    required this.historyRepository,
    this.roomDetailOverride,
    this.resolveRecordHistoryEnabled,
  });

  final ProviderRegistry registry;
  final HistoryRepository historyRepository;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })? roomDetailOverride;
  final Future<bool> Function()? resolveRecordHistoryEnabled;

  Future<LoadedRoomSnapshot> call({
    required ProviderId providerId,
    required String roomId,
    bool preferHighestQuality = false,
    bool? recordHistory,
  }) async {
    final provider = registry.create(providerId);
    final playQualities = provider.requireContract<SupportsPlayQualities>(
      ProviderCapability.playQualities,
    );
    final playUrls = provider.requireContract<SupportsPlayUrls>(
      ProviderCapability.playUrls,
    );

    final detail = await _loadRoomDetail(provider: provider, roomId: roomId);
    final loadedQualities = await playQualities.fetchPlayQualities(detail);
    var playbackUnavailableReason = _playbackUnavailableReason(
      providerName: provider.descriptor.displayName,
      detail: detail,
      urls: const [],
    );
    late final List<LivePlayQuality> qualities;
    late final LivePlayQuality selectedQuality;
    late final List<LivePlayUrl> urls;

    if (loadedQualities.isEmpty) {
      if (playbackUnavailableReason == null) {
        throw ProviderParseException(
          providerId: providerId,
          message: '${provider.descriptor.displayName} 当前没有返回可用清晰度。',
        );
      }
      qualities = const [_kUnavailablePlayQuality];
      selectedQuality = _kUnavailablePlayQuality;
      urls = const [];
    } else {
      qualities = loadedQualities;
      selectedQuality = preferHighestQuality
          ? _selectHighestQuality(qualities)
          : _selectDefaultQuality(
              providerId: providerId,
              qualities: qualities,
            );
      urls = await playUrls.fetchPlayUrls(
        detail: detail,
        quality: selectedQuality,
      );
      playbackUnavailableReason = _playbackUnavailableReason(
        providerName: provider.descriptor.displayName,
        detail: detail,
        urls: urls,
      );
    }

    if (urls.isEmpty && playbackUnavailableReason == null) {
      throw ProviderParseException(
        providerId: providerId,
        message: '${provider.descriptor.displayName} 当前没有返回可用播放地址。',
      );
    }
    final shouldRecordHistory =
        recordHistory ?? await resolveRecordHistoryEnabled?.call() ?? true;
    if (shouldRecordHistory) {
      await historyRepository.add(
        HistoryRecord(
          providerId: providerId.value,
          roomId: detail.roomId,
          title: detail.title,
          streamerName: detail.streamerName,
          viewedAt: DateTime.now(),
        ),
      );
    }

    return LoadedRoomSnapshot(
      providerId: providerId,
      detail: detail,
      qualities: qualities,
      selectedQuality: selectedQuality,
      playUrls: urls,
      playbackUnavailableReason: playbackUnavailableReason,
    );
  }

  Future<LiveRoomDetail> _loadRoomDetail({
    required LiveProvider provider,
    required String roomId,
  }) async {
    final overridden = await roomDetailOverride?.call(
      providerId: provider.descriptor.id,
      roomId: roomId,
    );
    if (overridden != null) {
      return overridden;
    }
    final roomDetail = provider.requireContract<SupportsRoomDetail>(
      ProviderCapability.roomDetail,
    );
    return roomDetail.fetchRoomDetail(roomId);
  }

  LivePlayQuality _selectHighestQuality(List<LivePlayQuality> qualities) {
    if (qualities.length == 1) {
      return qualities.first;
    }
    final sorted = [...qualities]
      ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
    return sorted.first;
  }

  LivePlayQuality _selectDefaultQuality({
    required ProviderId providerId,
    required List<LivePlayQuality> qualities,
  }) {
    final defaultQuality = qualities.firstWhere(
      (item) => item.isDefault,
      orElse: () => qualities.first,
    );
    if (providerId == ProviderId.twitch) {
      return defaultQuality;
    }
    return defaultQuality;
  }

  String? _playbackUnavailableReason({
    required String providerName,
    required LiveRoomDetail detail,
    required List<LivePlayUrl> urls,
  }) {
    if (urls.isNotEmpty) {
      return null;
    }
    final explicitReason = _metadataString(
      detail.metadata,
      const ['playbackUnavailableReason', 'unavailableReason'],
    );
    if (explicitReason != null) {
      return explicitReason;
    }

    final roomStatus = _roomStatus(detail.metadata);
    if (roomStatus != null) {
      return '$providerName 当前房间状态为 "$roomStatus"，暂时没有公开播放流。';
    }
    if (_isRestrictedRoom(detail.metadata)) {
      return '$providerName 当前房间需要额外权限，暂时没有公开播放流。';
    }
    if (!detail.isLive) {
      return '$providerName 当前房间暂未开播，暂时没有可用播放流。';
    }
    return null;
  }

  String? _roomStatus(Map<String, Object?>? metadata) {
    final rawStatus = _metadataString(
      metadata,
      const ['roomStatus', 'status', 'liveStatus', 'streamStatus'],
    );
    if (rawStatus == null) {
      return null;
    }
    final normalized = rawStatus.toLowerCase();
    if (normalized == 'public' ||
        normalized == 'live' ||
        normalized == 'online' ||
        normalized == 'open') {
      return null;
    }
    return rawStatus;
  }

  String? _metadataString(
    Map<String, Object?>? metadata,
    List<String> keys,
  ) {
    if (metadata == null) {
      return null;
    }
    for (final key in keys) {
      final value = metadata[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool _isRestrictedRoom(Map<String, Object?>? metadata) {
    if (metadata == null) {
      return false;
    }
    for (final key in const [
      'requiresLogin',
      'requiresSubscription',
      'subscriberOnly',
      'subscriptionOnly',
      'membersOnly',
      'private',
      'restricted',
      'locked',
      'paywalled',
    ]) {
      final value = metadata[key];
      if (value == true) {
        return true;
      }
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
    }
    return false;
  }
}

class LoadedRoomSnapshot {
  const LoadedRoomSnapshot({
    required this.providerId,
    required this.detail,
    required this.qualities,
    required this.selectedQuality,
    required this.playUrls,
    this.playbackUnavailableReason,
  });

  final ProviderId providerId;
  final LiveRoomDetail detail;
  final List<LivePlayQuality> qualities;
  final LivePlayQuality selectedQuality;
  final List<LivePlayUrl> playUrls;
  final String? playbackUnavailableReason;

  bool get hasPlayback => playUrls.isNotEmpty;
}
