import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPlaybackBridge {
  AndroidPlaybackBridge._();

  static final AndroidPlaybackBridge instance = AndroidPlaybackBridge._();
  static const MethodChannel _channel = MethodChannel(
    'nolive/android_playback',
  );

  Future<bool> isPictureInPictureSupported() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final supported =
        await _channel.invokeMethod<bool>('isPictureInPictureSupported');
    return supported ?? false;
  }

  Future<bool> isInPictureInPictureMode() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final inPip = await _channel.invokeMethod<bool>('isInPictureInPictureMode');
    return inPip ?? false;
  }

  Future<double?> getMediaVolume() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final volume = await _channel.invokeMethod<double>('getMediaVolume');
    return volume?.clamp(0.0, 1.0);
  }

  Future<bool> setMediaVolume(double value) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final updated = await _channel.invokeMethod<bool>('setMediaVolume', {
      'value': value.clamp(0.0, 1.0),
    });
    return updated ?? false;
  }

  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final entered = await _channel.invokeMethod<bool>(
      'enterPictureInPicture',
      {
        'width': width,
        'height': height,
      },
    );
    return entered ?? false;
  }

  Future<bool> enableSensorLandscape() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final enabled = await _channel.invokeMethod<bool>('enableSensorLandscape');
    return enabled ?? false;
  }

  Future<bool> lockPortrait() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final locked = await _channel.invokeMethod<bool>('lockPortrait');
    return locked ?? false;
  }
}
