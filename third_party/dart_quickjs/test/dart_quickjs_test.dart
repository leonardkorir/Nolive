import 'package:dart_quickjs/dart_quickjs.dart';
import 'package:test/test.dart';

void main() {
  group('JsRuntime', () {
    late JsRuntime runtime;

    setUp(() {
      runtime = JsRuntime();
    });

    tearDown(() {
      runtime.dispose();
    });

    group('eval', () {
      test('evaluates simple expressions', () {
        expect(runtime.eval('1 + 2'), equals(3));
        expect(runtime.eval('10 * 5'), equals(50));
        expect(runtime.eval('100 / 4'), equals(25.0));
      });

      test('evaluates string expressions', () {
        expect(runtime.eval('"Hello, World!"'), equals('Hello, World!'));
        expect(runtime.eval('"foo" + "bar"'), equals('foobar'));
      });

      test('evaluates boolean expressions', () {
        expect(runtime.eval('true'), isTrue);
        expect(runtime.eval('false'), isFalse);
        expect(runtime.eval('1 < 2'), isTrue);
        expect(runtime.eval('1 > 2'), isFalse);
      });

      test('evaluates null and undefined', () {
        expect(runtime.eval('null'), isNull);
        expect(runtime.eval('undefined'), isNull);
      });

      test('evaluates arrays', () {
        expect(runtime.eval('[1, 2, 3]'), equals([1, 2, 3]));
        expect(runtime.eval('["a", "b", "c"]'), equals(['a', 'b', 'c']));
        expect(runtime.eval('[1, "two", true]'), equals([1, 'two', true]));
      });

      test('evaluates objects', () {
        final result = runtime.eval('({a: 1, b: 2})');
        expect(result, isA<Map>());
        expect(result['a'], equals(1));
        expect(result['b'], equals(2));
      });

      test('evaluates floating point numbers', () {
        expect(runtime.eval('3.14'), closeTo(3.14, 0.001));
        expect(runtime.eval('Math.PI'), closeTo(3.14159, 0.001));
      });

      test('throws JsException on syntax error', () {
        expect(
          () => runtime.eval('this is not valid js'),
          throwsA(isA<JsException>()),
        );
      });

      test('throws JsException on runtime error', () {
        expect(
          () => runtime.eval('throw new Error("test error")'),
          throwsA(isA<JsException>()),
        );
      });
    });

    group('evalFunction', () {
      test('returns callable function', () {
        final fn = runtime.evalFunction('(function(a, b) { return a + b; })');
        expect(fn.call([1, 2]), equals(3));
        fn.dispose();
      });

      test('arrow function', () {
        final fn = runtime.evalFunction('((x) => x * x)');
        expect(fn.call([5]), equals(25));
        fn.dispose();
      });
    });

    group('globals', () {
      test('setGlobal and getGlobal', () {
        runtime.setGlobal('testValue', 42);
        expect(runtime.getGlobal('testValue'), equals(42));

        runtime.setGlobal('testString', 'hello');
        expect(runtime.getGlobal('testString'), equals('hello'));
      });

      test('use global in eval', () {
        runtime.setGlobal('x', 10);
        runtime.setGlobal('y', 20);
        expect(runtime.eval('x + y'), equals(30));
      });
    });

    group('garbage collection', () {
      test('runGC does not throw', () {
        expect(() => runtime.runGC(), returnsNormally);
      });
    });

    group('disposed runtime', () {
      test('throws after dispose', () {
        final rt = JsRuntime();
        rt.dispose();

        expect(
          () => rt.eval('1 + 1'),
          throwsA(isA<JsRuntimeDisposedException>()),
        );
      });
    });
  });
}
