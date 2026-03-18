import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('huya provider returns deterministic preview migration slice', () async {
    final provider = HuyaProvider();

    final categories = await provider.fetchCategories();
    expect(categories, isNotEmpty);
    expect(categories.first.children, isNotEmpty);

    final categoryRooms =
        await provider.fetchCategoryRooms(categories.first.children.first);
    expect(categoryRooms.items, isNotEmpty);
    expect(categoryRooms.items.first.providerId, 'huya');

    final rooms = await provider.searchRooms('架构');
    expect(rooms.items, isNotEmpty);
    expect(rooms.items.first.providerId, 'huya');

    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    expect(detail.providerId, 'huya');
    expect(detail.sourceUrl, 'https://www.huya.com/${detail.roomId}');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.any((item) => item.isDefault), isTrue);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls.single.url, contains(detail.roomId));
  });
}
