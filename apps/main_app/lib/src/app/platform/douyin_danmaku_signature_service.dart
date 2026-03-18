import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

class DouyinDanmakuSignatureService {
  DouyinDanmakuSignatureService._();

  static final DouyinDanmakuSignatureService instance =
      DouyinDanmakuSignatureService._();

  FlutterQjs? _engine;
  bool _scriptLoaded = false;

  FlutterQjs get _runtime {
    final engine = _engine;
    if (engine != null) {
      return engine;
    }
    final created = FlutterQjs(stackSize: 1024 * 1024);
    created.dispatch();
    _engine = created;
    return created;
  }

  Future<String> buildSignature({
    required String roomId,
    required String userUniqueId,
  }) async {
    await _ensureScriptLoaded();
    final params = <String, String>{
      'live_id': '1',
      'aid': _DouyinWebsocketParams.aidValue,
      'version_code': _DouyinWebsocketParams.versionCodeValue,
      'webcast_sdk_version': _DouyinWebsocketParams.sdkVersion,
      'room_id': roomId,
      'sub_room_id': '',
      'sub_channel_id': '',
      'did_rule': '3',
      'user_unique_id': userUniqueId,
      'device_platform': 'web',
      'device_type': '',
      'ac': '',
      'identity': 'audience',
    };
    final stub = md5
        .convert(utf8.encode(params.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(',')))
        .toString();
    final result = _runtime.evaluate("get_sign('$stub')");
    return result?.toString() ?? '';
  }

  Future<void> _ensureScriptLoaded() async {
    if (_scriptLoaded) {
      return;
    }
    final script = await rootBundle.loadString('assets/js/douyin-webmssdk.js');
    _runtime.evaluate(script);
    _scriptLoaded = true;
  }
}

mixin _DouyinWebsocketParams {
  static const String aidValue = '6383';
  static const String versionCodeValue = '180800';
  static const String sdkVersion = '1.0.14-beta.0';
}
