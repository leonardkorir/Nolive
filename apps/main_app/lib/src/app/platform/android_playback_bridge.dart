import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidPlaybackBridge {
  AndroidPlaybackBridge({
    MethodChannel? channel,
    bool Function()? isAndroidPlatform,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _isAndroidPlatform = isAndroidPlatform ?? _defaultIsAndroidPlatform;

  static final AndroidPlaybackBridge instance = AndroidPlaybackBridge();
  static const String channelName = 'nolive/android_playback';

  final MethodChannel _channel;
  final bool Function() _isAndroidPlatform;

  static bool _defaultIsAndroidPlatform() => Platform.isAndroid;

  @visibleForTesting
  bool get isAndroidPlatform => _isAndroidPlatform();

  Future<bool> isPictureInPictureSupported() async {
    final supported = await _invokeBool('isPictureInPictureSupported');
    return supported ?? false;
  }

  Future<bool> isInPictureInPictureMode() async {
    final inPip = await _invokeBool('isInPictureInPictureMode');
    return inPip ?? false;
  }

  Future<double?> getMediaVolume() async {
    final volume = await _invokeDouble('getMediaVolume');
    return volume?.clamp(0.0, 1.0);
  }

  Future<bool> setMediaVolume(double value) async {
    final updated = await _invokeBool('setMediaVolume', {
      'value': value.clamp(0.0, 1.0),
    });
    return updated ?? false;
  }

  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) async {
    final entered = await _invokeBool(
      'enterPictureInPicture',
      {
        'width': width.clamp(1, 1 << 20),
        'height': height.clamp(1, 1 << 20),
      },
    );
    return entered ?? false;
  }

  Future<bool> lockPortrait() async {
    final locked = await _invokeBool('lockPortrait');
    return locked ?? false;
  }

  Future<bool> lockLandscape() async {
    final locked = await _invokeBool('lockLandscape');
    return locked ?? false;
  }

  Future<bool> prepareForPictureInPicture() async {
    final prepared = await _invokeBool('prepareForPictureInPicture');
    return prepared ?? false;
  }

  Future<bool?> _invokeBool(String method, [Object? arguments]) {
    return _invokeMethod<bool>(method, arguments);
  }

  Future<double?> _invokeDouble(String method, [Object? arguments]) {
    return _invokeMethod<double>(method, arguments);
  }

  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    if (!isAndroidPlatform) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
