import 'package:flutter/material.dart';
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

  test(
    'provider badge returns exact icon for stripchat and other providers',
    () {
      expect(
        ProviderBadge.iconOf(ProviderId.stripchat),
        Icons.camera_alt_rounded,
      );
      expect(ProviderBadge.iconOf(ProviderId.bilibili), Icons.live_tv_rounded);
      expect(
        ProviderBadge.iconOf(ProviderId.twitch),
        Icons.videogame_asset_rounded,
      );
    },
  );

  test(
    'provider badge returns exact color for stripchat and other providers',
    () {
      expect(
        ProviderBadge.accentColorOf(ProviderId.stripchat),
        const Color(0xFFE74C3C),
      );
      expect(
        ProviderBadge.accentColorOf(ProviderId.bilibili),
        const Color(0xFF00A1D6),
      );
      expect(
        ProviderBadge.accentColorOf(ProviderId.twitch),
        const Color(0xFF9146FF),
      );
    },
  );

  test('provider badge returns monogram for stripchat', () {
    expect(ProviderBadge.monogramOf(ProviderId.stripchat), 'SC');
  });
}
