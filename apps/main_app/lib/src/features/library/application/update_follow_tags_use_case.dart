import 'package:live_storage/live_storage.dart';

class UpdateFollowTagsUseCase {
  const UpdateFollowTagsUseCase({
    required this.followRepository,
    required this.tagRepository,
  });

  final FollowRepository followRepository;
  final TagRepository tagRepository;

  Future<void> call({
    required String providerId,
    required String roomId,
    required List<String> tags,
  }) async {
    final records = await followRepository.listAll();
    final record = records
        .where(
          (item) => item.providerId == providerId && item.roomId == roomId,
        )
        .firstOrNull;
    if (record == null) {
      return;
    }

    final normalized = tags
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    for (final tag in normalized) {
      await tagRepository.create(tag);
    }

    await followRepository.upsert(record.copyWith(tags: normalized));
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
