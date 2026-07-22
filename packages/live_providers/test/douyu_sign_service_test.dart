import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

  test('extendPlayBody matches SlotSun Douyu_new origin flags', () {
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
      'enc_data=enc&tt=1700000000&did=${HttpDouyuSignService.kDefaultDeviceId}&auth=abc',
      cdn: 'hw-h5',
      rate: '0',
    );

    expect(body, contains('cdn=hw-h5'));
    expect(body, contains('rate=0'));
    expect(body, contains('ver=Douyu_new'));
    expect(body, contains('iar=0'));
    expect(body, contains('ive=0'));
    expect(body, contains('hevc=0'));
    expect(body, contains('fa=0'));
    expect(body, isNot(contains('ver=Douyu_223061205')));
  });

  test('stream headers empty like SlotSun bare Douyu URL playback', () {
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

    final play = service.buildPlayHeaders('5526219');
    final stream = service.buildStreamHeaders('5526219');

    expect(play['content-type'], 'application/x-www-form-urlencoded');
    expect(play['user-agent'], contains('Windows NT'));
    // SlotSun getH5Play: no cookie / referer on API headers.
    expect(play.containsKey('cookie'), isFalse);
    expect(play.containsKey('referer'), isFalse);
    // SlotSun LivePlayUrl(urls:) — no stream headers.
    expect(stream, isEmpty);
  });

  test('buildSignedPlayBody matches SlotSun full form shape', () async {
    DouyuDeviceId.clearSessionCacheForTest();
    final transport = _StubEncryptionTransport();
    const did = HttpDouyuSignService.kDefaultDeviceId;
    final service = HttpDouyuSignService(
      transport: transport,
      random: Random(1),
      deviceId: did,
    );

    final body = await service.buildSignedPlayBody(
      '5526219',
      cdn: 'ws-h5',
      rate: '0',
    );

    expect(body, startsWith('enc_data='));
    expect(body, contains('&tt='));
    expect(body, contains('&did=$did'));
    expect(body, contains('&auth='));
    expect(body, contains('&cdn=ws-h5'));
    expect(body, contains('&rate=0'));
    expect(body, contains('&hevc=0&fa=0&ive=0&ver=Douyu_new&iar=0'));
  });

  test(
    'buildPlayContext uses SlotSun websec getEncryption + per-install did',
    () async {
      DouyuDeviceId.clearSessionCacheForTest();
      final transport = _StubEncryptionTransport();
      const did = HttpDouyuSignService.kDefaultDeviceId;
      final service = HttpDouyuSignService(
        transport: transport,
        random: Random(1),
        deviceId: did,
      );

      final first = await service.buildPlayContext('5526219');
      final second = await service.buildPlayContext('5526219');

      expect(first.deviceId, did);
      expect(second.deviceId, did);
      expect(first.deviceId, equals(second.deviceId));
      expect(first.body, contains('enc_data=enc-payload'));
      expect(first.body, contains('did=$did'));
      expect(first.body, contains('auth='));
      // SlotSun sign() always includes cdn/rate in the same body.
      expect(first.body, contains('cdn='));
      expect(first.body, contains('rate=-1'));
      expect(first.body, contains('ver=Douyu_new'));
      expect(first.script, isEmpty);

      // Second call should reuse cached encryption key (single GET).
      expect(transport.encryptionGets, 1);
      expect(
        transport.lastUrl,
        'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption',
      );
      expect(transport.lastQuery?['did'], did);

      final extended = service.extendPlayBody(
        first.body,
        cdn: 'hw-h5',
        rate: '0',
      );
      expect(extended, contains('cdn=hw-h5'));
      expect(extended, contains('ver=Douyu_new'));

      // Auth matches SlotSun: secret=md5(rand+key), auth=md5(secret+key+rid+tt)
      final secret = md5.convert(utf8.encode('randkey')).toString();
      final auth = md5
          .convert(utf8.encode('${secret}key5526219${first.timestamp}'))
          .toString();
      expect(first.body, contains('auth=$auth'));

      expect(
        service.buildRoomHeaders('5526219')['user-agent'],
        contains('Windows NT'),
      );
    },
  );

  test('websec form percent-encodes Base64 reserved characters', () async {
    DouyuDeviceId.clearSessionCacheForTest();
    final transport = _StubEncryptionTransport(
      encData: 'abc+def/ghi=',
    );
    final service = HttpDouyuSignService(
      transport: transport,
      deviceId: HttpDouyuSignService.kDefaultDeviceId,
    );

    final body = await service.buildSignedPlayBody('1', cdn: 'x', rate: '0');
    expect(body, contains('enc_data=abc%2Bdef%2Fghi%3D'));
    expect(body, isNot(contains('enc_data=abc+def/ghi=')));
  });

  test('past expire_at falls back to local TTL without refetch thrash', () async {
    DouyuDeviceId.clearSessionCacheForTest();
    final transport = _StubEncryptionTransport();
    final service = HttpDouyuSignService(
      transport: transport,
      deviceId: HttpDouyuSignService.kDefaultDeviceId,
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    service.seedEncryptionKeyForTest(
      {
        'rand_str': 'rand',
        'enc_time': 1,
        'is_special': 0,
        'key': 'key',
        'enc_data': 'enc-payload',
        'expire_at': now - 10, // already past
      },
      localExpireAtSeconds: now + 3600,
    );

    await service.buildSignedPlayBody('1');
    await service.buildSignedPlayBody('1');
    expect(transport.encryptionGets, 0);
  });

  test('concurrent ensureEncryptionKey coalesces to one GET', () async {
    DouyuDeviceId.clearSessionCacheForTest();
    final transport = _SlowEncryptionTransport();
    final service = HttpDouyuSignService(
      transport: transport,
      deviceId: HttpDouyuSignService.kDefaultDeviceId,
    );

    await Future.wait([
      service.buildSignedPlayBody('1'),
      service.buildSignedPlayBody('2'),
      service.buildSignedPlayBody('3'),
    ]);
    expect(transport.encryptionGets, 1);
  });

  test(
    'buildPlayContext falls back to legacy homeH5Enc when websec fails',
    () async {
      DouyuDeviceId.clearSessionCacheForTest();
      final transport = _LegacyFallbackTransport();
      final diagnostics = <String>[];
      final service = HttpDouyuSignService(
        transport: transport,
        deviceId: HttpDouyuSignService.kDefaultDeviceId,
        diagnostics: diagnostics.add,
        signExecutor:
            ({
              required String script,
              required String roomId,
              required String deviceId,
              required int timestamp,
            }) async => throw StateError('signer failed'),
      );

      final ctx = await service.buildPlayContext('5526219');
      expect(ctx.deviceId, HttpDouyuSignService.kDefaultDeviceId);
      expect(ctx.body, contains('sign='));
      expect(transport.hitHomeH5Enc, isTrue);
      expect(
        diagnostics,
        contains(contains('websec encryption failed')),
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

class _StubEncryptionTransport extends _NoopDouyuTransport {
  _StubEncryptionTransport({this.encData = 'enc-payload'});

  final String encData;
  int encryptionGets = 0;
  String? lastUrl;
  Map<String, String>? lastQuery;

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    lastUrl = url;
    lastQuery = queryParameters;
    if (url.contains('getEncryption')) {
      encryptionGets += 1;
      return {
        'data': {
          'rand_str': 'rand',
          'enc_time': 1,
          'is_special': 0,
          'key': 'key',
          'enc_data': encData,
        },
      };
    }
    fail('Unexpected GET $url');
  }
}

class _SlowEncryptionTransport extends _StubEncryptionTransport {
  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return super.getJson(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _LegacyFallbackTransport extends _NoopDouyuTransport {
  bool hitHomeH5Enc = false;

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('getEncryption')) {
      throw StateError('encryption unavailable');
    }
    if (url.contains('homeH5Enc')) {
      hitHomeH5Enc = true;
      return {
        'data': {'room5526219': 'function ub98484234() {}'},
      };
    }
    fail('Unexpected GET $url');
  }
}
