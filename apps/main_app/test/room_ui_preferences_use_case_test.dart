import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

void main() {
  test('room ui preferences load defaults and persist updates', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    final defaults = await bootstrap.loadRoomUiPreferences();
    expect(defaults.chatTextSize, 14);
    expect(defaults.chatTextGap, 4);
    expect(defaults.chatBubbleStyle, isFalse);
    expect(defaults.showPlayerSuperChat, isTrue);
    expect(defaults.playerSuperChatDisplaySeconds, 8);

    final next = defaults.copyWith(
      chatTextSize: 18,
      chatTextGap: 8,
      chatBubbleStyle: true,
      showPlayerSuperChat: false,
      playerSuperChatDisplaySeconds: 12,
    );
    await bootstrap.updateRoomUiPreferences(next);

    final reloaded = await bootstrap.loadRoomUiPreferences();
    expect(reloaded.chatTextSize, 18);
    expect(reloaded.chatTextGap, 8);
    expect(reloaded.chatBubbleStyle, isTrue);
    expect(reloaded.showPlayerSuperChat, isFalse);
    expect(reloaded.playerSuperChatDisplaySeconds, 12);
  });
}
