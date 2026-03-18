import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('preview bilibili provider exposes danmaku session stream', () async {
    final provider = BilibiliProvider();
    final rooms = await provider.searchRooms('架构');
    final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
    final session = await provider.createDanmakuSession(detail);
    final firstMessage = session.messages.first;

    await session.connect();
    final resolved = await firstMessage.timeout(const Duration(seconds: 2));

    expect(resolved.type, anyOf(LiveMessageType.notice, LiveMessageType.chat));
    expect(resolved.content, isNotEmpty);

    await session.disconnect();
  });
}
