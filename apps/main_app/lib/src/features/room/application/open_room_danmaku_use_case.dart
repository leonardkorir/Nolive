import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class OpenRoomDanmakuUseCase {
  const OpenRoomDanmakuUseCase(this.registry);

  final ProviderRegistry registry;

  Future<DanmakuSession?> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
  }) async {
    final provider = registry.create(providerId);
    if (!provider.supports(ProviderCapability.danmaku)) {
      return null;
    }
    final danmaku = provider.requireContract<SupportsDanmaku>(
      ProviderCapability.danmaku,
    );
    return danmaku.createDanmakuSession(detail);
  }
}
