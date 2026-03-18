import 'package:live_storage/live_storage.dart';

class ClearTagsUseCase {
  const ClearTagsUseCase({
    required this.tagRepository,
    required this.followRepository,
  });

  final TagRepository tagRepository;
  final FollowRepository followRepository;

  Future<void> call() async {
    await tagRepository.clear();
    final follows = await followRepository.listAll();
    for (final follow in follows) {
      if (follow.tags.isEmpty) {
        continue;
      }
      await followRepository.upsert(follow.copyWith(tags: const []));
    }
  }
}
