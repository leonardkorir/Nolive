import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';

void main() {
  test('provider badge maps chaturbate to bundled logo asset', () {
    expect(
      ProviderBadge.logoAssetOf(ProviderId.chaturbate),
      'assets/branding/chaturbate.png',
    );
  });
}
