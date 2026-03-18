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

  test('parse room input rejects unknown plain input without provider', () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final result = bootstrap.parseRoomInput(rawInput: 'not-a-room');

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('未能识别平台'));
  });
}
