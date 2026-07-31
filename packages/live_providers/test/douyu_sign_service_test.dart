import 'dart:convert';

import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:test/test.dart';

void main() {
  test('extendPlayBody matches SlotSun Douyu_new origin flags', () {
    final service = HttpDouyuSignService(transport: _FakeDouyuTransport());
    final body = service.extendPlayBody(
      'enc_data=enc&tt=1700000000&did=${HttpDouyuSignService.kDefaultDeviceId}&auth=abc',
      cdn: 'tct-h5',
      rate: '0',
    );
    expect(body, contains('cdn=tct-h5'));
    expect(body, contains('rate=0'));
    expect(body, contains('ver=Douyu_new'));
  });

  test('buildSignedPlayBody uses websec encryption form fields', () async {
    final service = HttpDouyuSignService(
      transport: _FakeDouyuTransport(),
      deviceId: HttpDouyuSignService.kDefaultDeviceId,
    );
    final body = await service.buildSignedPlayBody(
      '12345',
      cdn: '',
      rate: '-1',
    );
    expect(body, contains('enc_data='));
    expect(body, contains('did='));
    expect(body, contains('auth='));
    expect(body, isNot(contains('sign=')));
  });

  test('buildPlayContext is websec-only', () async {
    final service = HttpDouyuSignService(
      transport: _FakeDouyuTransport(),
      deviceId: HttpDouyuSignService.kDefaultDeviceId,
    );
    final ctx = await service.buildPlayContext('99');
    expect(ctx.deviceId, HttpDouyuSignService.kDefaultDeviceId);
    expect(ctx.script, isEmpty);
    expect(ctx.body, contains('auth='));
  });
}

class _FakeDouyuTransport implements DouyuTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('getEncryption')) {
      return jsonEncode({
        'error': 0,
        'data': {
          'rand_str': 'rand',
          'enc_time': 1,
          'is_special': 0,
          'key': 'key',
          'enc_data': 'enc+data=',
          'expire_at': 9999999999,
        },
      });
    }
    return '{}';
  }

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => '{}';

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final text = await getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
    return jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => const {};
}
