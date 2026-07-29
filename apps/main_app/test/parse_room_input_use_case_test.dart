import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

void main() {
  test('parse room input accepts bilibili url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://live.bilibili.com/66666',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.bilibili);
    expect(result.parsedRoom?.roomId, '66666');
  });

  test('parse room input rejects only real douyin short-link hosts', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final shortLink = bootstrap.parseRoomInput(
      rawInput: 'https://v.douyin.com/abc123/',
      fallbackProvider: ProviderId.bilibili,
    );
    final lookalike = bootstrap.parseRoomInput(
      rawInput: 'https://not-v.douyin.com.example/abc123/',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(shortLink.isSuccess, isFalse);
    expect(shortLink.errorMessage, contains('暂不支持抖音短链接'));
    expect(lookalike.isSuccess, isFalse);
    expect(lookalike.errorMessage, isNot(contains('抖音短链接')));
  });

  test('parse room input accepts provider prefix', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'douyu:3125893',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.douyu);
    expect(result.parsedRoom?.roomId, '3125893');
  });

  test('parse room input accepts chaturbate provider prefix', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'chaturbate:kittengirlxo',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.chaturbate);
    expect(result.parsedRoom?.roomId, 'kittengirlxo');
  });

  test('parse room input accepts chaturbate url with trailing slash', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://chaturbate.com/kittengirlxo/',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.chaturbate);
    expect(result.parsedRoom?.roomId, 'kittengirlxo');
  });

  test('parse room input accepts chaturbate url without trailing slash', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://chaturbate.com/kittengirlxo',
      fallbackProvider: ProviderId.bilibili,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.chaturbate);
    expect(result.parsedRoom?.roomId, 'kittengirlxo');
  });

  test('parse room input normalizes huya long yyid to yy prefix', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.huya.com/35184442792200',
      fallbackProvider: ProviderId.huya,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.huya);
    expect(result.parsedRoom?.roomId, 'yy/35184442792200');
  });

  test('parse room input accepts huya custom host path', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.huya.com/xlxluexue',
      fallbackProvider: ProviderId.huya,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.huya);
    expect(result.parsedRoom?.roomId, 'xlxluexue');
  });

  test('parse room input extracts douyu topic rid query parameter', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.douyu.com/topic/KPL?rid=3125893',
      fallbackProvider: ProviderId.douyu,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.douyu);
    expect(result.parsedRoom?.roomId, '3125893');
  });

  test('parse room input accepts twitch channel url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.twitch.tv/xQc',
      fallbackProvider: ProviderId.twitch,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.twitch);
    expect(result.parsedRoom?.roomId, 'xqc');
  });

  test('parse room input accepts twitch popout chat url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.twitch.tv/popout/arky/chat',
      fallbackProvider: ProviderId.twitch,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.twitch);
    expect(result.parsedRoom?.roomId, 'arky');
  });

  test('parse room input accepts youtube watch url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      fallbackProvider: ProviderId.youtube,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.youtube);
    expect(result.parsedRoom?.roomId, 'Z3eFGbFcaXs');
  });

  test('parse room input accepts youtube shorthand url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://youtu.be/Z3eFGbFcaXs',
      fallbackProvider: ProviderId.youtube,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.youtube);
    expect(result.parsedRoom?.roomId, 'Z3eFGbFcaXs');
  });

  test('parse room input normalizes youtube handle page to live room id', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://www.youtube.com/@Wenzel_TCG',
      fallbackProvider: ProviderId.youtube,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.youtube);
    expect(result.parsedRoom?.roomId, '@Wenzel_TCG/live');
  });

  test('parse room input accepts stripchat url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://stripchat.com/test_model',
      fallbackProvider: ProviderId.stripchat,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.stripchat);
    expect(result.parsedRoom?.roomId, 'test_model');
  });

  test('parse room input accepts stripchat locale subdomain url', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'https://zh.stripchat.com/test_model',
      fallbackProvider: ProviderId.stripchat,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.stripchat);
    expect(result.parsedRoom?.roomId, 'test_model');
  });

  test('parse room input accepts stripchat: prefix', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(
      rawInput: 'stripchat:test_model',
      fallbackProvider: ProviderId.stripchat,
    );

    expect(result.isSuccess, isTrue);
    expect(result.parsedRoom?.providerId, ProviderId.stripchat);
    expect(result.parsedRoom?.roomId, 'test_model');
  });

  test('parse room input rejects stripchat reserved segments', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final reservedResults = ['api', 'search', 'login', 'models'].map(
      (segment) => bootstrap.parseRoomInput(
        rawInput: 'https://stripchat.com/$segment',
        fallbackProvider: ProviderId.stripchat,
      ),
    );

    for (final result in reservedResults) {
      expect(
        result.isSuccess,
        isFalse,
        reason: 'Reserved segment should be rejected',
      );
    }
  });

  test('parse room input rejects unknown plain input without provider', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(rawInput: 'not-a-room');

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('未能识别平台'));
  });

  test('parse room input boundary cases', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    // Empty input
    final emptyResult = bootstrap.parseRoomInput(rawInput: '');
    expect(emptyResult.isSuccess, isFalse);
    expect(emptyResult.errorMessage, contains('请输入房间号'));

    // Whitespace only
    final whitespaceResult = bootstrap.parseRoomInput(rawInput: '   ');
    expect(whitespaceResult.isSuccess, isFalse);
    expect(whitespaceResult.errorMessage, contains('请输入房间号'));

    // Case-insensitive prefixes
    final upperPrefixResult = bootstrap.parseRoomInput(
      rawInput: 'STRIPCHAT:test_model',
      fallbackProvider: ProviderId.bilibili,
    );
    expect(upperPrefixResult.isSuccess, isTrue);
    expect(upperPrefixResult.parsedRoom?.providerId, ProviderId.stripchat);
    expect(upperPrefixResult.parsedRoom?.roomId, 'test_model');

    final mixedPrefixResult = bootstrap.parseRoomInput(
      rawInput: 'BiLiBiLi:12345',
      fallbackProvider: ProviderId.stripchat,
    );
    expect(mixedPrefixResult.isSuccess, isTrue);
    expect(mixedPrefixResult.parsedRoom?.providerId, ProviderId.bilibili);
    expect(mixedPrefixResult.parsedRoom?.roomId, '12345');

    // Extremely long input
    final longInput = 'a' * 5000;
    final longResult = bootstrap.parseRoomInput(
      rawInput: 'stripchat:$longInput',
      fallbackProvider: ProviderId.stripchat,
    );
    expect(longResult.isSuccess, isTrue);
    expect(longResult.parsedRoom?.roomId, longInput);

    // Special characters in URL that could cause parsing error
    final specialUrlResult = bootstrap.parseRoomInput(
      rawInput: 'https://stripchat.com/some_model_name%20with%20spaces',
      fallbackProvider: ProviderId.stripchat,
    );
    expect(specialUrlResult.isSuccess, isFalse);
    expect(specialUrlResult.errorMessage, contains('格式不合法'));
  });
}
