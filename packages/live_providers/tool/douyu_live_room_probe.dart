import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<void> main() async {
  final registry = ReferenceProviderCatalog.buildLiveRegistry(
    stringSetting: (_) => '',
    intSetting: (_) => 0,
  );
  final provider = registry.create(ProviderId.douyu);
  final categories = await provider
      .requireContract<SupportsCategories>(ProviderCapability.categories)
      .fetchCategories();
  final sub =
      categories.firstWhere((c) => c.children.isNotEmpty).children.firstWhere(
            (s) => s.id != '0',
            orElse: () => categories.first.children.first,
          );
  final rooms = await provider
      .requireContract<SupportsCategoryRooms>(ProviderCapability.categories)
      .fetchCategoryRooms(sub, page: 1);
  print('category=${sub.name} rooms=${rooms.items.length}');

  final room = rooms.items.firstWhere(
    (r) => r.roomId.isNotEmpty,
    orElse: () => rooms.items.first,
  );
  print('room=${room.roomId} title=${room.title}');

  final detail = await provider
      .requireContract<SupportsRoomDetail>(ProviderCapability.roomDetail)
      .fetchRoomDetail(room.roomId);
  print(
      'detail live=${detail.isLive} room=${detail.roomId} title=${detail.title}');

  final qualities = await provider
      .requireContract<SupportsPlayQualities>(ProviderCapability.playQualities)
      .fetchPlayQualities(detail);
  print('qualities=${qualities.length}');
  for (final q in qualities) {
    final urls = await provider
        .requireContract<SupportsPlayUrls>(ProviderCapability.playUrls)
        .fetchPlayUrls(detail: detail, quality: q);
    print('Q ${q.id} ${q.label} urls=${urls.length}');
    for (final u in urls.take(1)) {
      print('  ${u.url}');
    }
  }
}
