import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('twitch provider returns deterministic preview migration slice',
      () async {
    final provider = TwitchProvider.preview();

    final categories = await provider.fetchCategories();
    expect(categories, isNotEmpty);
    final justChatting = categories.single.children.firstWhere(
      (item) => item.id == 'just_chatting',
    );

    final categoryRooms = await provider.fetchCategoryRooms(justChatting);
    expect(categoryRooms.items, isNotEmpty);
    expect(categoryRooms.items.first.areaName, 'Just Chatting');

    final rooms = await provider.fetchRecommendRooms();
    expect(rooms.items, isNotEmpty);
    expect(rooms.items.first.providerId, 'twitch');

    final search = await provider.searchRooms('xqc');
    expect(search.items, isNotEmpty);
    expect(search.items.first.roomId, 'xqc');

    final detail = await provider.fetchRoomDetail('xqc');
    expect(detail.providerId, 'twitch');
    expect(detail.roomId, 'xqc');
    expect(detail.sourceUrl, 'https://www.twitch.tv/xqc');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.first.isDefault, isTrue);
    final selectedQuality = qualities.firstWhere((item) => !item.isDefault);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: selectedQuality,
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('.m3u8'));
  });
}
