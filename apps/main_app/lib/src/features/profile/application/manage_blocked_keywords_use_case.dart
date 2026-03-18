import 'package:live_storage/live_storage.dart';

class LoadBlockedKeywordsUseCase {
  const LoadBlockedKeywordsUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<List<String>> call() async {
    return await settingsRepository
            .readValue<List<String>>('blocked_keywords') ??
        const <String>[];
  }
}

class AddBlockedKeywordUseCase {
  const AddBlockedKeywordUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(String keyword) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) {
      return;
    }
    final current =
        await settingsRepository.readValue<List<String>>('blocked_keywords') ??
            const <String>[];
    final next = {...current, normalized}.toList(growable: false)..sort();
    await settingsRepository.writeValue('blocked_keywords', next);
  }
}

class RemoveBlockedKeywordUseCase {
  const RemoveBlockedKeywordUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(String keyword) async {
    final current =
        await settingsRepository.readValue<List<String>>('blocked_keywords') ??
            const <String>[];
    final next = [...current]..removeWhere((item) => item == keyword);
    await settingsRepository.writeValue('blocked_keywords', next);
  }
}
