import 'package:live_storage/live_storage.dart';

class RemoveHistoryRecordUseCase {
  const RemoveHistoryRecordUseCase(this.historyRepository);

  final HistoryRepository historyRepository;

  Future<void> call({required String providerId, required String roomId}) {
    return historyRepository.remove(providerId, roomId);
  }
}
