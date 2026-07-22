import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/user_facing_error.dart';

void main() {
  test('formatUserFacingError maps socket-like errors to Chinese network copy',
      () {
    final message = formatUserFacingError(Exception('SocketException: failed'));
    expect(message, contains('网络'));
    expect(message.toLowerCase(), isNot(contains('socketexception')));
    expect(message, isNot(contains('Exception:')));
  });

  test('formatUserFacingError maps Chaturbate password rooms', () {
    expect(
      formatUserFacingError(
        Exception(
          'ProviderParseException(provider.parse_failure): '
          'Chaturbate room context request for kitayamachu: '
          'room requires a password.',
        ),
      ),
      contains('加锁'),
    );
  });

  test('formatUserFacingError maps timeout and keeps short Chinese passthrough',
      () {
    expect(
      formatUserFacingError(Exception('TimeoutException after 0:00:10')),
      contains('超时'),
    );
    expect(
      formatUserFacingError('暂时没有内容'),
      '暂时没有内容',
    );
  });

  test('formatUserFacingError falls back for long technical dumps', () {
    final dump = formatUserFacingError(
      StateError('Error:\n#0 foo.dart\n#1 bar.dart'),
      fallback: '加载失败，请稍后重试',
    );
    expect(dump, '加载失败，请稍后重试');
    expect(dump, isNot(contains('#0')));
  });
}
