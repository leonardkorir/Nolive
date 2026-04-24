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
