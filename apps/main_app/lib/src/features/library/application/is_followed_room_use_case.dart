import 'package:live_storage/live_storage.dart';

class IsFollowedRoomUseCase {
  const IsFollowedRoomUseCase(this.followRepository);

  final FollowRepository followRepository;

  Future<bool> call({required String providerId, required String roomId}) {
    return followRepository.exists(providerId, roomId);
  }
}
