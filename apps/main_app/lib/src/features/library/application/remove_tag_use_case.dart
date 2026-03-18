import 'package:live_storage/live_storage.dart';

class RemoveTagUseCase {
  const RemoveTagUseCase({
    required this.tagRepository,
    required this.followRepository,
  });

  final TagRepository tagRepository;
  final FollowRepository followRepository;

  Future<void> call(String tag) async {
    await tagRepository.remove(tag);
    final follows = await followRepository.listAll();
    for (final follow in follows) {
      if (!follow.tags.contains(tag)) {
        continue;
      }
      final nextTags = [...follow.tags]..removeWhere((item) => item == tag);
      await followRepository.upsert(follow.copyWith(tags: nextTags));
    }
  }
}
