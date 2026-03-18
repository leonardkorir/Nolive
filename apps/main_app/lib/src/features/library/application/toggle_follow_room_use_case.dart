import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';

class ToggleFollowRoomUseCase {
  const ToggleFollowRoomUseCase(
    this.followRepository, {
    this.followDataRevision,
  });

  final FollowRepository followRepository;
  final ValueNotifier<int>? followDataRevision;

  Future<bool> call({
    required String providerId,
    required String roomId,
    required String streamerName,
    String? streamerAvatarUrl,
    String? title,
    String? areaName,
    String? coverUrl,
    String? keyframeUrl,
  }) async {
    final exists = await followRepository.exists(providerId, roomId);
    if (exists) {
      await followRepository.remove(providerId, roomId);
      _markChanged();
      return false;
    }
    await followRepository.upsert(
      FollowRecord(
        providerId: providerId,
        roomId: roomId,
        streamerName: normalizeDisplayText(streamerName),
        streamerAvatarUrl: _normalizeOptionalString(streamerAvatarUrl),
        lastTitle: _normalizeDisplayOrNull(title),
        lastAreaName: _normalizeDisplayOrNull(areaName),
        lastCoverUrl: _normalizeOptionalString(coverUrl),
        lastKeyframeUrl: _normalizeOptionalString(keyframeUrl),
      ),
    );
    _markChanged();
    return true;
  }

  void _markChanged() {
    if (followDataRevision != null) {
      followDataRevision!.value += 1;
    }
  }
}

String? _normalizeOptionalString(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String? _normalizeDisplayOrNull(String? value) {
  final normalized = normalizeDisplayText(value);
  return normalized.isEmpty ? null : normalized;
}
