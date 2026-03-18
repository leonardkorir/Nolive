import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

void main() {
  test('DanmakuFilterService blocks configured keywords case-insensitively',
      () {
    const service = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: {'spam'}),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: 'hello world'),
      LiveMessage(type: LiveMessageType.chat, content: 'This is SPAM content'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.first.content, 'hello world');
  });

  test('DanmakuFilterService supports regex rules with re: prefix', () {
    const service = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: {'re:^抽奖.*\$'}),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: '正常聊天'),
      LiveMessage(type: LiveMessageType.chat, content: '抽奖开始啦'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.single.content, '正常聊天');
  });
}
