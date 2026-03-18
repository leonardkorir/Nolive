import 'package:live_shared/live_shared.dart';
import 'package:test/test.dart';

void main() {
  test('success result stores value and marks success', () {
    const result = Result<int>.success(42);

    expect(result.isSuccess, isTrue);
    expect(result.value, 42);
    expect(result.error, isNull);
  });

  test('failure result stores error and clears value', () {
    final error = StateError('boom');
    final result = Result<int>.failure(error);

    expect(result.isSuccess, isFalse);
    expect(result.value, isNull);
    expect(result.error, same(error));
  });
}
