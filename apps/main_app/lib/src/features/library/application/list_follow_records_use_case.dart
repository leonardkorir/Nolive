import 'package:live_storage/live_storage.dart';

class ListFollowRecordsUseCase {
  const ListFollowRecordsUseCase(this.followRepository);

  final FollowRepository followRepository;

  Future<List<FollowRecord>> call() {
    return followRepository.listAll();
  }
}
