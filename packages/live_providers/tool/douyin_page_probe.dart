import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<void> main() async {
  final provider = DouyinProvider.live();

  final categories = await provider
      .requireContract<SupportsCategories>(ProviderCapability.categories)
      .fetchCategories();
  final game = categories.firstWhere(
    (item) => item.name == '游戏',
    orElse: () => categories.first,
  );
  final fallback = game.children.isNotEmpty
      ? game.children.first
      : LiveSubCategory(id: game.id, parentId: game.id, name: game.name);
  final sub = game.children.firstWhere(
    (item) => item.name.contains('绝地求生'),
    orElse: () => fallback,
  );

  final api = provider.requireContract<SupportsCategoryRooms>(
    ProviderCapability.categories,
  );
  final page1 = await api.fetchCategoryRooms(sub, page: 1);
  final page2 = await api.fetchCategoryRooms(sub, page: 2);

  print('sub=${sub.name} id=${sub.id}');
  print('page1=${page1.items.length} hasMore=${page1.hasMore}');
  print('page2=${page2.items.length} hasMore=${page2.hasMore}');

  final ids1 = page1.items.map((e) => e.roomId).take(5).toList();
  final ids2 = page2.items.map((e) => e.roomId).take(5).toList();
  print('ids1=$ids1');
  print('ids2=$ids2');

  final page1Set = page1.items.map((e) => e.roomId).toSet();
  final overlap = page2.items.where((r) => page1Set.contains(r.roomId)).length;
  print('overlap=$overlap');
}
