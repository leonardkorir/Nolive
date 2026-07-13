import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_detail_override_policy.dart';

void main() {
  test('shared override policy blocks chaturbate and allows others', () {
    expect(shouldAllowRoomDetailOverride(ProviderId.chaturbate), isFalse);
    expect(shouldAllowRoomDetailOverride(ProviderId.bilibili), isTrue);
    expect(shouldAllowRoomDetailOverride(ProviderId.twitch), isTrue);
    expect(shouldAllowRoomDetailOverride(ProviderId.douyu), isTrue);
  });
}
