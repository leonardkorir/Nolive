import 'dart:math';

import 'package:live_providers/src/providers/douyu/douyu_quickjs_signer.dart';
import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:test/test.dart';

void main() {
  test('constructor runs injected signer warmup scheduler only', () {
    var warmupScheduled = false;
    HttpDouyuSignService(
      transport: _NoopDouyuTransport(),
      scheduleSignerWarmUp: () {
        warmupScheduled = true;
      },
    );

    expect(warmupScheduled, isTrue);

    // Without an injected scheduler, construction must not spawn QuickJS.
    HttpDouyuSignService(transport: _NoopDouyuTransport());
  });

  test('quickjs signer serializes concurrent sign requests', () async {
    final signer = DouyuQuickJsSigner();
    addTearDown(signer.dispose);
    const script = '''
function ub98484234(roomId, deviceId, timestamp) {
  return 'rid=' + roomId + '&did=' + deviceId + '&tt=' + timestamp;
}
''';

    final results = await Future.wait(
      List.generate(
        10,
        (index) => signer.sign(
          script,
          roomId: '$index',
          deviceId: 'device-$index',
          timestamp: 1700000000 + index,
        ),
      ),
    );

    expect(results, hasLength(10));
    for (var index = 0; index < results.length; index += 1) {
      expect(
        results[index],
        'rid=$index&did=device-$index&tt=${1700000000 + index}',
      );
    }
  });

  test('quickjs signer rejects work after dispose', () async {
    final signer = DouyuQuickJsSigner();
    const script = '''
function ub98484234(roomId, deviceId, timestamp) {
  return roomId + deviceId + timestamp;
}
''';

    await signer.sign(
      script,
      roomId: '1',
      deviceId: 'device',
      timestamp: 1700000000,
    );
    signer.dispose();

    await expectLater(
      signer.sign(
        script,
        roomId: '2',
        deviceId: 'device',
        timestamp: 1700000001,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('quickjs isolate signer recovers after script errors', () async {
    final signer = DouyuQuickJsSigner();
    addTearDown(signer.dispose);
    const validScript = '''
function ub98484234(roomId, deviceId, timestamp) {
  return 'rid=' + roomId + '&did=' + deviceId + '&tt=' + timestamp;
}
''';

    await expectLater(
      signer.sign(
        'function ub98484234() { throw new Error("boom"); }',
        roomId: 'broken',
        deviceId: 'device',
        timestamp: 1700000000,
      ),
      throwsA(isA<StateError>()),
    );

    final result = await signer.sign(
      validScript,
      roomId: 'restored',
      deviceId: 'device-restored',
      timestamp: 1700000001,
    );

    expect(result, 'rid=restored&did=device-restored&tt=1700000001');
  });

  test('extendPlayBody keeps douyu origin-friendly playback flags', () {
    final service = HttpDouyuSignService(
      transport: _NoopDouyuTransport(),
      signExecutor:
          ({
            required String script,
            required String roomId,
            required String deviceId,
            required int timestamp,
          }) async => '',
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

  test(
    'buildPlayContext rotates device ids and falls back to signed body',
    () async {
      final transport = _StubDouyuTransport(
        response: {
          'data': {'room5526219': 'function ub98484234() {}'},
        },
      );
      final diagnostics = <String>[];
      final service = HttpDouyuSignService(
        transport: transport,
        random: Random(1),
        diagnostics: diagnostics.add,
        signExecutor:
            ({
              required String script,
              required String roomId,
              required String deviceId,
              required int timestamp,
            }) async => throw StateError('signer failed'),
      );

      final first = await service.buildPlayContext('5526219');
      final second = await service.buildPlayContext('5526219');

      expect(first.deviceId, hasLength(32));
      expect(second.deviceId, hasLength(32));
      expect(first.deviceId, isNot(equals(second.deviceId)));
      expect(first.body, contains('sign='));
      expect(
        service.buildRoomHeaders('5526219')['user-agent'],
        contains('Chrome/'),
      );
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
    },
  );
}

class _NoopDouyuTransport implements DouyuTransport {
  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => throw UnimplementedError();

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> postJson(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => throw UnimplementedError();

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async => throw UnimplementedError();
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
