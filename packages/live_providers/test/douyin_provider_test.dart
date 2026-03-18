import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('douyin provider returns deterministic preview migration slice',
      () async {
    final provider = DouyinProvider();

    final rooms = await provider.searchRooms('架构');
    expect(rooms.items, isNotEmpty);
    expect(rooms.items.first.providerId, 'douyin');

    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    expect(detail.providerId, 'douyin');
    expect(detail.sourceUrl, 'https://live.douyin.com/${detail.roomId}');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('douyin.local'));
  });
}
