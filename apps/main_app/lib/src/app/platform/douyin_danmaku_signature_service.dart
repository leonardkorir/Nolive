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

  static const String _scriptAsset = 'assets/js/douyin-webmssdk.js';
  static const String _scriptSha256 =
      '1947447062475c9f3edfedabea8f0fb888da1d469891311506f97ca2d28c7141';
  static const String _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';

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
        .convert(
          utf8.encode(
            params.entries
                .map((entry) => '${entry.key}=${entry.value}')
                .join(','),
          ),
        )
        .toString();
    final result = _runtime.evaluate("get_sign('$stub')");
    return result?.toString() ?? '';
  }

  Future<void> _ensureScriptLoaded() async {
    if (_scriptLoaded) {
      return;
    }
    final data = await rootBundle.load(_scriptAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    _verifyScriptIntegrity(bytes);
    final script = utf8.decode(bytes);
    _runtime.evaluate(
      'var __NOLIVE_DOUYIN_USER_AGENT__ = ${jsonEncode(_webUserAgent)};',
    );
    _runtime.evaluate(script);
    _scriptLoaded = true;
  }

  static void _verifyScriptIntegrity(Uint8List bytes) {
    final actual = sha256.convert(bytes).toString();
    if (actual != _scriptSha256) {
      throw StateError(
        'Douyin webmssdk integrity check failed: expected $_scriptSha256, '
        'got $actual.',
      );
    }
  }
}

mixin _DouyinWebsocketParams {
  static const String aidValue = '6383';
  static const String versionCodeValue = '180800';
  static const String sdkVersion = '1.0.14-beta.0';
}
