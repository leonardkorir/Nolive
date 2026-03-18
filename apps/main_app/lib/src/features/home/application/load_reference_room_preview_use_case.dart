import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class LoadReferenceRoomPreviewUseCase {
  const LoadReferenceRoomPreviewUseCase(this.registry);

  final ProviderRegistry registry;

  Future<ReferenceRoomPreview> call() async {
    final provider = registry.create(ProviderId.bilibili);
    final roomSearch = provider.requireContract<SupportsRoomSearch>(
      ProviderCapability.searchRooms,
    );
    final roomDetail = provider.requireContract<SupportsRoomDetail>(
      ProviderCapability.roomDetail,
    );
    final playQualities = provider.requireContract<SupportsPlayQualities>(
      ProviderCapability.playQualities,
    );
    final playUrls = provider.requireContract<SupportsPlayUrls>(
      ProviderCapability.playUrls,
    );

    final rooms = await roomSearch.searchRooms('架构');
    final room = rooms.items.first;
    final detail = await roomDetail.fetchRoomDetail(room.roomId);
    final qualities = await playQualities.fetchPlayQualities(detail);
    final urls = await playUrls.fetchPlayUrls(
      detail: detail,
      quality: qualities.first,
    );

    return ReferenceRoomPreview(
      providerName: provider.descriptor.displayName,
      roomTitle: detail.title,
      streamerName: detail.streamerName,
      defaultQualityLabel: qualities.first.label,
      playableUrlCount: urls.length,
    );
  }
}

class ReferenceRoomPreview {
  const ReferenceRoomPreview({
    required this.providerName,
    required this.roomTitle,
    required this.streamerName,
    required this.defaultQualityLabel,
    required this.playableUrlCount,
  });

  final String providerName;
  final String roomTitle;
  final String streamerName;
  final String defaultQualityLabel;
  final int playableUrlCount;
}
