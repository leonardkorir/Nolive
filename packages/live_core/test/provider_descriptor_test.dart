import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('ProviderDescriptor reports supported capabilities', () {
    const descriptor = ProviderDescriptor(
      id: ProviderId('demo'),
      displayName: 'Demo',
      capabilities: {
        ProviderCapability.searchRooms,
        ProviderCapability.playUrls,
      },
      supportedPlatforms: {
        ProviderPlatform.android,
      },
    );

    expect(descriptor.supports(ProviderCapability.searchRooms), isTrue);
    expect(descriptor.supports(ProviderCapability.playUrls), isTrue);
    expect(descriptor.supports(ProviderCapability.danmaku), isFalse);
    expect(descriptor.validate(), isEmpty);
  });

  test('ProviderDescriptor validates incomplete metadata', () {
    const descriptor = ProviderDescriptor(
      id: ProviderId('broken'),
      displayName: '',
      capabilities: {},
      supportedPlatforms: {},
    );

    expect(descriptor.validate(), hasLength(3));
  });
}
