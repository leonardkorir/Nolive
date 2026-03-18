import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<void> main() async {
  final registry = ReferenceProviderCatalog.buildLiveRegistry(
    stringSetting: (_) => '',
    intSetting: (_) => 0,
  );
  final provider = registry.create(ProviderId.bilibili);
  final categories = await provider
      .requireContract<SupportsCategories>(ProviderCapability.categories)
      .fetchCategories();
  print('categories=${categories.length}');

  final first = categories.firstWhere((c) => c.children.isNotEmpty);
  final sub = first.children.first;
  print('first=${first.name}/${sub.name}/${sub.parentId}/${sub.id}');

  final page = await provider
      .requireContract<SupportsCategoryRooms>(ProviderCapability.categories)
      .fetchCategoryRooms(sub, page: 1);
  print('rooms=${page.items.length} hasMore=${page.hasMore}');
  for (final item in page.items.take(3)) {
    print('${item.title} / ${item.roomId}');
  }
}
