import 'package:live_storage/live_storage.dart';

class CreateTagUseCase {
  const CreateTagUseCase(this.tagRepository);

  final TagRepository tagRepository;

  Future<void> call(String tag) async {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      return;
    }
    await tagRepository.create(normalized);
  }
}
