import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/provider_ticker_danmaku_session.dart';
import 'package:test/test.dart';

void main() {
  test('youtube provider returns deterministic preview migration slice',
      () async {
    final provider = YouTubeProvider.preview();

    final categories = await provider.fetchCategories();
    expect(categories, isNotEmpty);
    final gaming = categories.single.children.firstWhere(
      (item) => item.id == 'gaming',
    );

    final categoryRooms = await provider.fetchCategoryRooms(gaming);
    expect(categoryRooms.items, isNotEmpty);
    expect(categoryRooms.items.first.areaName, '游戏');

    final recommend = await provider.fetchRecommendRooms();
    expect(recommend.items, isNotEmpty);
    expect(recommend.items.first.providerId, 'youtube');

    final search = await provider.searchRooms('china');
    expect(search.items, isNotEmpty);
    expect(search.items.first.providerId, 'youtube');

    final detail = await provider.fetchRoomDetail('@ChinaStreetObserver/live');
    expect(detail.providerId, 'youtube');
    expect(detail.roomId, '@ChinaStreetObserver/live');
    expect(detail.sourceUrl, 'https://www.youtube.com/watch?v=Z3eFGbFcaXs');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities.length, greaterThan(1));
    expect(qualities.first.isDefault, isTrue);
    final selectedQuality = qualities.firstWhere((item) => !item.isDefault);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: selectedQuality,
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('.m3u8'));

    final session = await provider.createDanmakuSession(detail);
    expect(session, isA<ProviderTickerDanmakuSession>());
  });
}
