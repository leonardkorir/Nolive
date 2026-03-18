import 'package:live_storage/live_storage.dart';

class ClearHistoryUseCase {
  const ClearHistoryUseCase(this.historyRepository);

  final HistoryRepository historyRepository;

  Future<void> call() => historyRepository.clear();
}
