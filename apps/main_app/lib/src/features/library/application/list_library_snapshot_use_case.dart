import 'package:live_storage/live_storage.dart';

class ListLibrarySnapshotUseCase {
  const ListLibrarySnapshotUseCase({
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
  });

  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;

  Future<LibrarySnapshot> call() async {
    final history = await historyRepository.listRecent(limit: 20);
    final follows = await followRepository.listAll();
    final tags = await tagRepository.listAll();
    return LibrarySnapshot(history: history, follows: follows, tags: tags);
  }
}

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.history,
    required this.follows,
    required this.tags,
  });

  final List<HistoryRecord> history;
  final List<FollowRecord> follows;
  final List<String> tags;
}
