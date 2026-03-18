import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'douyu_quickjs_signer.dart';
import 'douyu_transport.dart';

typedef DouyuSignExecutor = Future<String> Function({
  required String script,
  required String roomId,
  required String deviceId,
  required int timestamp,
});

class DouyuSignedPlayContext {
  const DouyuSignedPlayContext({
    required this.body,
    required this.deviceId,
    required this.timestamp,
    this.script = '',
  });

  final String body;
  final String deviceId;
  final int timestamp;
  final String script;
}

abstract class DouyuSignService {
  Map<String, String> buildSearchHeaders();

  Map<String, String> buildRoomHeaders(String roomId);

  Map<String, String> buildPlayHeaders(
    String roomId, {
    String? deviceId,
  });

  Future<DouyuSignedPlayContext> buildPlayContext(String roomId);

  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  });
}

class HttpDouyuSignService implements DouyuSignService {
  HttpDouyuSignService({
    required DouyuTransport transport,
    DouyuSignExecutor? signExecutor,
    Random? random,
  })  : _transport = transport,
        _signExecutor = signExecutor ?? _defaultSignExecutor,
        _random = random ?? Random.secure();

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';
  static const String _searchReferer = 'https://www.douyu.com/search/';
  static const String _defaultDeviceId = '10000000000000000000000000001501';

  final DouyuTransport _transport;
  final DouyuSignExecutor _signExecutor;
  final Random _random;

  @override
  Map<String, String> buildSearchHeaders() {
    final deviceId = _generateDeviceId();
    return {
      'user-agent': defaultUserAgent,
      'referer': _searchReferer,
      'cookie': 'dy_did=$deviceId;acf_did=$deviceId',
    };
  }

  @override
  Map<String, String> buildRoomHeaders(String roomId) {
    return {
      'user-agent': defaultUserAgent,
      'referer': 'https://www.douyu.com/$roomId',
    };
  }

  @override
  Map<String, String> buildPlayHeaders(
    String roomId, {
    String? deviceId,
  }) {
    final resolvedDeviceId = deviceId ?? _generateDeviceId();
    return {
      'user-agent': defaultUserAgent,
      'referer': 'https://www.douyu.com/$roomId',
      'cookie': 'dy_did=$resolvedDeviceId;acf_did=$resolvedDeviceId',
      'content-type': 'application/x-www-form-urlencoded',
    };
  }

  @override
  Future<DouyuSignedPlayContext> buildPlayContext(String roomId) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/swf_api/homeH5Enc',
      queryParameters: {'rids': roomId},
      headers: buildRoomHeaders(roomId),
    );
    final data = _asMap(response['data']);
    final script = data['room$roomId']?.toString() ?? '';
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deviceId = _defaultDeviceId;

    final body = script.isNotEmpty
        ? await _signExecutor(
            script: script,
            roomId: roomId,
            deviceId: deviceId,
            timestamp: timestamp,
          )
        : _buildFallbackBody(
            roomId: roomId,
            deviceId: deviceId,
            timestamp: timestamp,
          );

    return DouyuSignedPlayContext(
      body: body,
      deviceId: deviceId,
      timestamp: timestamp,
      script: script,
    );
  }

  @override
  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  }) {
    final normalizedBody = baseBody.trim();
    final prefix = normalizedBody.isEmpty || normalizedBody.endsWith('&')
        ? normalizedBody
        : '$normalizedBody&';
    return '${prefix}cdn=$cdn&rate=$rate&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0';
  }

  String _generateDeviceId([int length = 32]) {
    final buffer = StringBuffer();
    for (var index = 0; index < length; index += 1) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  String _buildFallbackBody({
    required String roomId,
    required String deviceId,
    required int timestamp,
  }) {
    final signature = md5
        .convert(utf8.encode('$roomId|$deviceId|$timestamp|simplelive-douyu'))
        .toString();
    return 'rid=$roomId&did=$deviceId&tt=$timestamp&sign=$signature';
  }

  static Future<String> _defaultSignExecutor({
    required String script,
    required String roomId,
    required String deviceId,
    required int timestamp,
  }) async {
    try {
      return DouyuQuickJsSigner.getSign(
        script,
        roomId: roomId,
        deviceId: deviceId,
        timestamp: timestamp,
      ).trim();
    } catch (_) {
      return 'rid=$roomId&did=$deviceId&tt=$timestamp';
    }
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }
}
