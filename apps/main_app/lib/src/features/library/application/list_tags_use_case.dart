import 'package:live_storage/live_storage.dart';

class ListTagsUseCase {
  const ListTagsUseCase(this.tagRepository);

  final TagRepository tagRepository;

  Future<List<String>> call() {
    return tagRepository.listAll();
  }
}
