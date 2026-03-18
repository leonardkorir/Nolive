import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili provider returns deterministic mock migration slice',
      () async {
    final provider = BilibiliProvider();

    final categories = await provider.fetchCategories();
    expect(categories, isNotEmpty);
    expect(categories.first.children, isNotEmpty);

    final categoryRooms =
        await provider.fetchCategoryRooms(categories.first.children.first);
    expect(categoryRooms.items, isNotEmpty);

    final rooms = await provider.searchRooms('架构');
    expect(rooms.items, isNotEmpty);

    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    expect(detail.providerId, 'bilibili');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.first,
    );
    expect(urls.single.url, contains(detail.roomId));
  });
}
