import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('chaturbate provider returns deterministic preview migration slice',
      () async {
    final provider = ChaturbateProvider.preview();

    final categories = await provider.fetchCategories();
    expect(categories, isNotEmpty);
    expect(categories.single.children, isNotEmpty);

    final categoryRooms =
        await provider.fetchCategoryRooms(categories.single.children.first);
    expect(categoryRooms.items, isNotEmpty);

    final rooms = await provider.searchRooms('kitt');
    expect(rooms.items, isNotEmpty);
    expect(rooms.items.first.providerId, 'chaturbate');

    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    expect(detail.providerId, 'chaturbate');
    expect(detail.sourceUrl, 'https://chaturbate.com/${detail.roomId}/');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('${detail.roomId}-sd-preview'));
  });
}
