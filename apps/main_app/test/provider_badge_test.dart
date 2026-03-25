import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';

void main() {
  test('provider badge maps bundled logo assets for branded providers', () {
    expect(
      ProviderBadge.logoAssetOf(ProviderId.chaturbate),
      'assets/branding/chaturbate.png',
    );
    expect(
      ProviderBadge.logoAssetOf(ProviderId.twitch),
      'assets/branding/twitch.png',
    );
    expect(
      ProviderBadge.logoAssetOf(ProviderId.youtube),
      'assets/branding/youtube.png',
    );
  });
}
