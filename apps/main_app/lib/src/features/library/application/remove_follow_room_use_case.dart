import 'package:flutter/foundation.dart';
import 'package:live_storage/live_storage.dart';

class RemoveFollowRoomUseCase {
  const RemoveFollowRoomUseCase(
    this.followRepository, {
    this.followDataRevision,
  });

  final FollowRepository followRepository;
  final ValueNotifier<int>? followDataRevision;

  Future<void> call(
      {required String providerId, required String roomId}) async {
    await followRepository.remove(providerId, roomId);
    if (followDataRevision != null) {
      followDataRevision!.value += 1;
    }
  }
}
