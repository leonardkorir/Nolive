import 'package:live_providers/src/providers/provider_json.dart';
import 'package:test/test.dart';

void main() {
  test('provider json decodes maps and lists defensively', () {
    expect(
      ProviderJson.asMap({'a': 1}),
      {'a': 1},
    );
    expect(
      ProviderJson.asMap({'a': 1, 'b': 'x'}),
      {'a': 1, 'b': 'x'},
    );
    expect(ProviderJson.asMap('bad'), isEmpty);

    expect(ProviderJson.asList([1, 2, 3]), [1, 2, 3]);
    expect(ProviderJson.asList('bad'), isEmpty);
  });

  test('provider json parses integer variants', () {
    expect(ProviderJson.asInt(42), 42);
    expect(ProviderJson.asInt('42'), 42);
    expect(ProviderJson.asInt(42.8), isNull);
    expect(ProviderJson.asInt(42.8, allowNum: true), 42);
    expect(ProviderJson.asInt(' 42 ', trim: true), 42);
  });

  test('provider json parses localized compact counts', () {
    expect(ProviderJson.asLocalizedCountInt('1.2万'), 12000);
    expect(ProviderJson.asLocalizedCountInt('3亿'), 300000000);
    expect(ProviderJson.asLocalizedCountInt('1,234'), 1234);
    expect(ProviderJson.asLocalizedCountInt(18.6), 19);
  });
}
