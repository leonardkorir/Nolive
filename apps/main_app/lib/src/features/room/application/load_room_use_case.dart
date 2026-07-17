import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/room/application/room_detail_override_policy.dart';
import 'package:nolive_app/src/features/room/application/room_play_selection_policy.dart';

LivePlayQuality _kUnavailablePlayQuality = LivePlayQuality(
  id: 'unavailable',
  label: '不可用',
  isDefault: true,
);

/// Wall-clock budget for detail + qualities + play URLs so a single hung
/// network call cannot leave the room page spinning forever (log: douyu hang).
@visibleForTesting
const Duration kLoadRoomNetworkTimeout = Duration(seconds: 20);

class LoadRoomUseCase {
  const LoadRoomUseCase(
    this.registry, {
    required this.historyRepository,
    this.roomDetailOverride,
    this.resolveRecordHistoryEnabled,
    this.networkTimeout = kLoadRoomNetworkTimeout,
  });

  final ProviderRegistry registry;
  final HistoryRepository historyRepository;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })?
  roomDetailOverride;
  final Future<bool> Function()? resolveRecordHistoryEnabled;
  final Duration networkTimeout;

  Future<LoadedRoomSnapshot> call({
    required ProviderId providerId,
    required String roomId,
    bool preferHighestQuality = false,
    bool preferAdaptiveAutoQuality = true,
    NetworkQualityPreference? qualityPreference,
    bool isCellular = false,
    NetworkQualityPreference? cellularQualityPreference,
    bool? recordHistory,
  }) async {
    try {
      return await _loadWithNetworkTimeout(
        providerId: providerId,
        roomId: roomId,
        preferHighestQuality: preferHighestQuality,
        preferAdaptiveAutoQuality: preferAdaptiveAutoQuality,
        qualityPreference: qualityPreference,
        isCellular: isCellular,
        cellularQualityPreference: cellularQualityPreference,
        recordHistory: recordHistory,
      );
    } on TimeoutException {
      throw ProviderParseException(
        providerId: providerId,
        message:
            '加载房间超时（${networkTimeout.inSeconds}s），请检查网络后重试。',
      );
    }
  }

  Future<LoadedRoomSnapshot> _loadWithNetworkTimeout({
    required ProviderId providerId,
    required String roomId,
    required bool preferHighestQuality,
    required bool preferAdaptiveAutoQuality,
    NetworkQualityPreference? qualityPreference,
    required bool isCellular,
    NetworkQualityPreference? cellularQualityPreference,
    bool? recordHistory,
  }) {
    return _loadBody(
      providerId: providerId,
      roomId: roomId,
      preferHighestQuality: preferHighestQuality,
      preferAdaptiveAutoQuality: preferAdaptiveAutoQuality,
      qualityPreference: qualityPreference,
      isCellular: isCellular,
      cellularQualityPreference: cellularQualityPreference,
      recordHistory: recordHistory,
    ).timeout(networkTimeout);
  }

  Future<LoadedRoomSnapshot> _loadBody({
    required ProviderId providerId,
    required String roomId,
    required bool preferHighestQuality,
    required bool preferAdaptiveAutoQuality,
    NetworkQualityPreference? qualityPreference,
    required bool isCellular,
    NetworkQualityPreference? cellularQualityPreference,
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
      qualities = [_kUnavailablePlayQuality];
      selectedQuality = _kUnavailablePlayQuality;
      urls = const [];
    } else {
      qualities = loadedQualities;
      selectedQuality = _selectQualityByPreference(
        providerId: providerId,
        qualities: qualities,
        preferHighestQuality: preferHighestQuality,
        preferAdaptiveAutoQuality: preferAdaptiveAutoQuality,
        qualityPreference: qualityPreference,
        isCellular: isCellular,
        cellularQualityPreference: cellularQualityPreference,
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
          providerId: providerId,
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
    Object? providerError;
    StackTrace? providerStackTrace;
    final roomDetail = provider.requireContract<SupportsRoomDetail>(
      ProviderCapability.roomDetail,
    );
    try {
      return await roomDetail.fetchRoomDetail(roomId);
    } catch (error, stackTrace) {
      providerError = error;
      providerStackTrace = stackTrace;
    }

    if (shouldAllowRoomDetailOverride(provider.descriptor.id)) {
      final overridden = await roomDetailOverride?.call(
        providerId: provider.descriptor.id,
        roomId: roomId,
      );
      if (overridden != null) {
        return overridden;
      }
    }
    Error.throwWithStackTrace(providerError, providerStackTrace);
  }

  LivePlayQuality _selectQualityByPreference({
    required ProviderId providerId,
    required List<LivePlayQuality> qualities,
    required bool preferHighestQuality,
    required bool preferAdaptiveAutoQuality,
    NetworkQualityPreference? qualityPreference,
    required bool isCellular,
    NetworkQualityPreference? cellularQualityPreference,
  }) {
    // Platforms that expose adaptive "auto" (Twitch / Chaturbate / Stripchat…)
    // can warm up on auto when the user leaves the auto-quality switch on.
    // YouTube is excluded: its adaptive master is not a reliable MPV source.
    if (preferAdaptiveAutoQuality &&
        supportsAdaptiveAutoQuality(providerId)) {
      final autoQuality = findAdaptiveAutoQuality(qualities);
      if (autoQuality != null) {
        return autoQuality;
      }
    }

    // Prefer-highest switch and network "最高" share site-aware startup
    // selection so adaptive "auto" is never treated as the top fixed tier.
    if (preferHighestQuality) {
      return selectRoomStartupQuality(
        providerId: providerId,
        qualities: qualities,
      );
    }
    final wifi = qualityPreference ?? NetworkQualityPreference.middle;
    final cellular =
        cellularQualityPreference ?? NetworkQualityPreference.lowest;
    final preference = resolveNetworkQualityPreference(
      isCellular: isCellular,
      wifiPreference: wifi,
      cellularPreference: cellular,
    );
    if (preference == NetworkQualityPreference.highest) {
      return selectRoomStartupQuality(
        providerId: providerId,
        qualities: qualities,
      );
    }

    // Ladder index assumes descending quality (index 0 = best). Drop adaptive
    // "auto" entries and sort by sortOrder so middle/lowest are meaningful.
    final fixedLadder = qualities
        .where((item) => item.id.trim().toLowerCase() != 'auto')
        .toList(growable: true);
    final ladder = (fixedLadder.isNotEmpty ? fixedLadder : [...qualities])
      ..sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    final index = selectQualityIndex(
      qualityCount: ladder.length,
      preference: preference,
    );
    if (index < 0 || index >= ladder.length) {
      return selectRoomDefaultQuality(
        providerId: providerId,
        qualities: qualities,
      );
    }
    return ladder[index];
  }

  String? _playbackUnavailableReason({
    required String providerName,
    required LiveRoomDetail detail,
    required List<LivePlayUrl> urls,
  }) {
    if (urls.isNotEmpty) {
      return null;
    }
    final explicitReason = _metadataString(detail.metadata, const [
      'playbackUnavailableReason',
      'unavailableReason',
    ]);
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
    final rawStatus = _metadataString(metadata, const [
      'roomStatus',
      'status',
      'liveStatus',
      'streamStatus',
    ]);
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

  String? _metadataString(Map<String, Object?>? metadata, List<String> keys) {
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
