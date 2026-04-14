import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';

class LoadFollowWatchlistUseCase {
  const LoadFollowWatchlistUseCase({
    required this.followRepository,
    required this.registry,
    this.detailTimeout = const Duration(seconds: 8),
    this.maxConcurrent = 6,
    this.roomDetailOverride,
  });

  final FollowRepository followRepository;
  final ProviderRegistry registry;
  final Duration detailTimeout;
  final int maxConcurrent;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })? roomDetailOverride;

  Future<FollowWatchlist> call({
    void Function(int index, FollowWatchEntry entry)? onEntryResolved,
  }) async {
    final follows = await followRepository.listAll();
    if (follows.isEmpty) {
      return const FollowWatchlist(entries: <FollowWatchEntry>[]);
    }
    final resolvedMaxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;
    final workerCount = follows.length < resolvedMaxConcurrent
        ? follows.length
        : resolvedMaxConcurrent;
    final entries = List<FollowWatchEntry?>.filled(follows.length, null);
    final updatedRecords = List<FollowRecord?>.filled(follows.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        if (index >= follows.length) {
          return;
        }
        nextIndex += 1;
        final result = await _inspectFollow(follows[index]);
        entries[index] = result.entry;
        updatedRecords[index] = result.updatedRecord;
        onEntryResolved?.call(index, result.entry);
      }
    }

    await Future.wait(
      List.generate(workerCount, (_) => worker()),
      eagerError: false,
    );
    final changedRecords = updatedRecords.whereType<FollowRecord>().toList(
          growable: false,
        );
    if (changedRecords.isNotEmpty) {
      await followRepository.upsertAll(changedRecords);
    }
    return FollowWatchlist(
      entries: entries.whereType<FollowWatchEntry>().toList(growable: false),
    );
  }

  Future<_ResolvedFollowEntry> _inspectFollow(FollowRecord record) async {
    try {
      final provider = registry.create(ProviderId(record.providerId));
      final detailFuture = () async {
        final overridden = await roomDetailOverride?.call(
          providerId: provider.descriptor.id,
          roomId: record.roomId,
        );
        if (overridden != null) {
          return overridden;
        }
        return provider
            .requireContract<SupportsRoomDetail>(
              ProviderCapability.roomDetail,
            )
            .fetchRoomDetail(record.roomId);
      }();
      final detail = await detailFuture.timeout(detailTimeout);
      final syncedRecord = _buildSyncedRecord(record, detail);
      return _ResolvedFollowEntry(
        entry: FollowWatchEntry(
          record: syncedRecord ?? record,
          detail: detail,
        ),
        updatedRecord: syncedRecord,
      );
    } catch (error) {
      return _ResolvedFollowEntry(
        entry: FollowWatchEntry(record: record, error: error),
      );
    }
  }

  FollowRecord? _buildSyncedRecord(
    FollowRecord record,
    LiveRoomDetail detail,
  ) {
    final normalizedName = normalizeDisplayText(detail.streamerName);
    final normalizedAvatarUrl = detail.streamerAvatarUrl?.trim() ?? '';
    final normalizedTitle = normalizeDisplayText(detail.title);
    final normalizedAreaName = normalizeDisplayText(detail.areaName);
    final normalizedCoverUrl = detail.coverUrl?.trim() ?? '';
    final normalizedKeyframeUrl = detail.keyframeUrl?.trim() ?? '';
    final nextRecord = record.copyWith(
      streamerName:
          normalizedName.isEmpty ? record.streamerName : normalizedName,
      streamerAvatarUrl: normalizedAvatarUrl.isEmpty
          ? record.streamerAvatarUrl
          : normalizedAvatarUrl,
      lastTitle: normalizedTitle.isEmpty ? record.lastTitle : normalizedTitle,
      lastAreaName:
          normalizedAreaName.isEmpty ? record.lastAreaName : normalizedAreaName,
      lastCoverUrl:
          normalizedCoverUrl.isEmpty ? record.lastCoverUrl : normalizedCoverUrl,
      lastKeyframeUrl: normalizedKeyframeUrl.isEmpty
          ? record.lastKeyframeUrl
          : normalizedKeyframeUrl,
    );
    if (nextRecord.streamerName == record.streamerName &&
        nextRecord.streamerAvatarUrl == record.streamerAvatarUrl &&
        nextRecord.lastTitle == record.lastTitle &&
        nextRecord.lastAreaName == record.lastAreaName &&
        nextRecord.lastCoverUrl == record.lastCoverUrl &&
        nextRecord.lastKeyframeUrl == record.lastKeyframeUrl) {
      return null;
    }
    return nextRecord;
  }
}

class _ResolvedFollowEntry {
  const _ResolvedFollowEntry({
    required this.entry,
    this.updatedRecord,
  });

  final FollowWatchEntry entry;
  final FollowRecord? updatedRecord;
}

class FollowWatchlist {
  const FollowWatchlist({required this.entries});

  final List<FollowWatchEntry> entries;

  int get liveCount => entries.where((item) => item.isLive).length;

  int get offlineCount => entries.where((item) => item.isOffline).length;
}

class FollowWatchEntry {
  const FollowWatchEntry({
    required this.record,
    this.detail,
    this.error,
  });

  final FollowRecord record;
  final LiveRoomDetail? detail;
  final Object? error;

  bool get hasError => error != null;

  bool get isLive => detail?.isLive ?? false;

  bool get isOffline => !hasError && !isLive;

  bool get isUnavailable => hasError && !isLive;

  String get roomId => detail?.roomId ?? record.roomId;

  String get displayStreamerName {
    final detailName = normalizeDisplayText(detail?.streamerName);
    if (detailName.isNotEmpty) {
      return detailName;
    }
    return normalizeDisplayText(record.streamerName);
  }

  String get displayAreaName {
    final detailArea = normalizeDisplayText(detail?.areaName);
    if (detailArea.isNotEmpty) {
      return detailArea;
    }
    return normalizeDisplayText(record.lastAreaName);
  }

  String? get displayStreamerAvatarUrl {
    final detailAvatar = detail?.streamerAvatarUrl?.trim() ?? '';
    if (detailAvatar.isNotEmpty) {
      return detailAvatar;
    }
    final recordAvatar = record.streamerAvatarUrl?.trim() ?? '';
    return recordAvatar.isEmpty ? null : recordAvatar;
  }

  List<String> get displayTags => record.tags
      .map(normalizeDisplayText)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  String get title {
    final detailTitle = normalizeDisplayText(detail?.title);
    if (detailTitle.isNotEmpty) {
      return detailTitle;
    }
    final recordTitle = normalizeDisplayText(record.lastTitle);
    if (recordTitle.isNotEmpty) {
      return recordTitle;
    }
    return '$displayStreamerName 的直播间';
  }

  String? get displayCoverUrl {
    final detailCover = detail?.coverUrl?.trim() ?? '';
    if (detailCover.isNotEmpty) {
      return detailCover;
    }
    final recordCover = record.lastCoverUrl?.trim() ?? '';
    return recordCover.isEmpty ? null : recordCover;
  }

  String? get displayKeyframeUrl {
    final detailKeyframe = detail?.keyframeUrl?.trim() ?? '';
    if (detailKeyframe.isNotEmpty) {
      return detailKeyframe;
    }
    final recordKeyframe = record.lastKeyframeUrl?.trim() ?? '';
    return recordKeyframe.isEmpty ? null : recordKeyframe;
  }

  LiveRoom toLiveRoom() {
    final detail = this.detail;
    return LiveRoom(
      providerId: record.providerId,
      roomId: roomId,
      title: title,
      streamerName: displayStreamerName,
      coverUrl: displayCoverUrl,
      keyframeUrl: displayKeyframeUrl,
      areaName: displayAreaName,
      streamerAvatarUrl: displayStreamerAvatarUrl,
      viewerCount: detail?.viewerCount,
      isLive: isLive,
    );
  }
}
