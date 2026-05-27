import 'dart:math';

import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:test/test.dart';

void main() {
  test('constructor schedules douyu signer warmup', () {
    var warmupScheduled = false;
    HttpDouyuSignService(
      transport: _NoopDouyuTransport(),
      scheduleSignerWarmUp: () {
        warmupScheduled = true;
      },
    );

    expect(warmupScheduled, isTrue);
  });

  test('extendPlayBody keeps douyu origin-friendly playback flags', () {
    final service = HttpDouyuSignService(
      transport: _NoopDouyuTransport(),
      signExecutor: ({
        required String script,
        required String roomId,
        required String deviceId,
        required int timestamp,
      }) async =>
          '',
    );

    final body = service.extendPlayBody(
      'rid=5526219&did=test-device&tt=1700000000&sign=test-sign',
      cdn: 'hw-h5',
      rate: '0',
    );

    expect(body, contains('cdn=hw-h5'));
    expect(body, contains('rate=0'));
    expect(body, contains('ver=Douyu_223061205'));
    expect(body, contains('iar=0'));
    expect(body, contains('ive=0'));
    expect(body, contains('hevc=0'));
    expect(body, contains('fa=0'));
  });

  test('buildPlayContext rotates device ids and falls back to signed body',
      () async {
    final transport = _StubDouyuTransport(
      response: {
        'data': {
          'room5526219': 'function ub98484234() {}',
        },
      },
    );
    final diagnostics = <String>[];
    final service = HttpDouyuSignService(
      transport: transport,
      random: Random(1),
      diagnostics: diagnostics.add,
      signExecutor: ({
        required String script,
        required String roomId,
        required String deviceId,
        required int timestamp,
      }) async =>
          throw StateError('signer failed'),
    );

    final first = await service.buildPlayContext('5526219');
    final second = await service.buildPlayContext('5526219');

    expect(first.deviceId, hasLength(32));
    expect(second.deviceId, hasLength(32));
    expect(first.deviceId, isNot(equals(second.deviceId)));
    expect(first.body, contains('sign='));
    expect(
        service.buildRoomHeaders('5526219')['user-agent'], contains('Chrome/'));
    expect(
      service.buildRoomHeaders('5526219')['user-agent'],
      isNot(contains('Windows NT')),
    );
    expect(
      service.buildRoomHeaders('5526219')['user-agent'],
      isNot(contains('Edg/')),
    );
    expect(transport.lastHeaders?['user-agent'], contains('Chrome/'));
    expect(
      diagnostics,
      contains(contains('sign executor failed; using fallback body')),
    );
  });
}

class _NoopDouyuTransport implements DouyuTransport {
  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> postJson(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async =>
      throw UnimplementedError();
}

class _StubDouyuTransport extends _NoopDouyuTransport {
  _StubDouyuTransport({required this.response});

  final Map<String, dynamic> response;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    lastHeaders = headers;
    expect(url, 'https://www.douyu.com/swf_api/homeH5Enc');
    expect(queryParameters['rids'], '5526219');
    return response;
  }
}
