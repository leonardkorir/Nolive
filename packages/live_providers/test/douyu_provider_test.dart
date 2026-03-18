import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('douyu provider returns deterministic preview migration slice',
      () async {
    final provider = DouyuProvider();

    final rooms = await provider.searchRooms('架构');
    expect(rooms.items, isNotEmpty);
    expect(rooms.items.first.providerId, 'douyu');

    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    expect(detail.providerId, 'douyu');
    expect(detail.sourceUrl, 'https://www.douyu.com/${detail.roomId}');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.any((item) => item.isDefault), isTrue);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls.single.url, contains(detail.roomId));
    expect(urls.single.headers['referer'],
        'https://www.douyu.com/${detail.roomId}');
  });
}
