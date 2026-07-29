import 'package:live_core/live_core.dart';
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

  test('result helpers map fold and expose failure state', () {
    const success = Result<int>.success(21);
    final failure = Result<int>.failure(StateError('boom'));

    expect(success.isFailure, isFalse);
    expect(success.map((value) => value! * 2).value, 42);
    expect(success.fold((value) => 'ok:$value', (_) => 'bad'), 'ok:21');

    expect(failure.isFailure, isTrue);
    expect(failure.map((value) => value! * 2).error, same(failure.error));
    expect(failure.when(success: (_) => 'ok', failure: (_) => 'bad'), 'bad');
  });

  test('result helpers preserve nullable success values', () {
    const success = Result<int>.success(null);

    expect(success.when(success: (value) => value, failure: (_) => 1), isNull);
    expect(
      success.map((value) => value == null ? 'empty' : '$value').value,
      'empty',
    );
    expect(success.fold((value) => value, (_) => 1), isNull);
  });
}
