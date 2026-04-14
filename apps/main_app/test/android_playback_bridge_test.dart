import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/platform/android_playback_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidPlaybackBridge', () {
    test('short-circuits on non-android platform', () async {
      final bridge = AndroidPlaybackBridge(
        isAndroidPlatform: () => false,
      );

      expect(await bridge.isPictureInPictureSupported(), isFalse);
      expect(await bridge.isInPictureInPictureMode(), isFalse);
      expect(await bridge.getMediaVolume(), isNull);
      expect(await bridge.setMediaVolume(0.4), isFalse);
      expect(await bridge.lockLandscape(), isFalse);
      expect(await bridge.prepareForPictureInPicture(), isFalse);
      expect(
        await bridge.enterPictureInPicture(width: 16, height: 9),
        isFalse,
      );
    });

    test('clamps outbound and inbound media values', () async {
      final channel =
          MethodChannel('${AndroidPlaybackBridge.channelName}/test');
      MethodCall? lastCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        lastCall = call;
        switch (call.method) {
          case 'setMediaVolume':
            return true;
          case 'getMediaVolume':
            return 1.7;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = AndroidPlaybackBridge(
        channel: channel,
        isAndroidPlatform: () => true,
      );

      expect(await bridge.setMediaVolume(2.4), isTrue);
      expect(lastCall?.method, 'setMediaVolume');
      expect((lastCall?.arguments as Map)['value'], 1.0);
      expect(await bridge.getMediaVolume(), 1.0);
    });

    test('clamps picture-in-picture aspect arguments before channel call',
        () async {
      final channel = MethodChannel('${AndroidPlaybackBridge.channelName}/pip');
      MethodCall? lastCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        lastCall = call;
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = AndroidPlaybackBridge(
        channel: channel,
        isAndroidPlatform: () => true,
      );

      expect(
        await bridge.enterPictureInPicture(width: 0, height: -20),
        isTrue,
      );
      expect(lastCall?.method, 'enterPictureInPicture');
      expect((lastCall?.arguments as Map)['width'], 1);
      expect((lastCall?.arguments as Map)['height'], 1);
    });

    test('returns safe fallback when method channel throws', () async {
      final channel =
          MethodChannel('${AndroidPlaybackBridge.channelName}/error');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = AndroidPlaybackBridge(
        channel: channel,
        isAndroidPlatform: () => true,
      );

      expect(await bridge.isPictureInPictureSupported(), isFalse);
      expect(await bridge.getMediaVolume(), isNull);
      expect(await bridge.lockPortrait(), isFalse);
      expect(await bridge.lockLandscape(), isFalse);
      expect(await bridge.prepareForPictureInPicture(), isFalse);
    });

    test('invokes orientation preparation methods over the channel', () async {
      final channel =
          MethodChannel('${AndroidPlaybackBridge.channelName}/orientation');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = AndroidPlaybackBridge(
        channel: channel,
        isAndroidPlatform: () => true,
      );

      expect(await bridge.lockLandscape(), isTrue);
      expect(await bridge.prepareForPictureInPicture(), isTrue);
      expect(calls, <String>['lockLandscape', 'prepareForPictureInPicture']);
    });
  });
}
