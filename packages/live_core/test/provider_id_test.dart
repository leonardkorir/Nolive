import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderId', () {
    test('reuses known constants when parsing legacy string values', () {
      expect(ProviderId.from('bilibili'), same(ProviderId.bilibili));
      expect(ProviderId.from('douyu'), same(ProviderId.douyu));
      expect(ProviderId.from('youtube'), same(ProviderId.youtube));
    });

    test('preserves custom provider ids and serializes to legacy strings', () {
      const providerId = ProviderId('custom-provider');

      expect(ProviderId.from(providerId), same(providerId));
      expect(ProviderId.from('custom-provider'), providerId);
      expect(providerId.toJson(), 'custom-provider');
      expect(providerId.isNotEmpty, isTrue);
    });
  });
}
