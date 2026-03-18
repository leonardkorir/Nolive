import 'package:nolive_app/src/features/library/application/list_library_snapshot_use_case.dart';
import 'package:nolive_app/src/features/library/application/list_tags_use_case.dart';

class LoadLibraryDashboardUseCase {
  const LoadLibraryDashboardUseCase({
    required this.listLibrarySnapshot,
    required this.listTags,
  });

  final ListLibrarySnapshotUseCase listLibrarySnapshot;
  final ListTagsUseCase listTags;

  Future<LibraryDashboard> call() async {
    final snapshot = await listLibrarySnapshot();
    final tags = await listTags();
    return LibraryDashboard(snapshot: snapshot, tags: tags);
  }
}

class LibraryDashboard {
  const LibraryDashboard({required this.snapshot, required this.tags});

  final LibrarySnapshot snapshot;
  final List<String> tags;
}
