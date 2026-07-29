import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:test/test.dart';

void main() {
  tearDown(DeliveryPlatformProfile.resetForTest);

  group('DeliveryPlatformProfile', () {
    test('resolve maps Android/iOS to mobile, Win/Linux/macOS to desktop', () {
      expect(
        DeliveryPlatformProfile.resolve(
          isAndroid: true,
          isIOS: false,
          isLinux: false,
          isWindows: false,
          isMacOS: false,
        ).family,
        DeliveryPlatformFamily.mobile,
      );
      expect(
        DeliveryPlatformProfile.resolve(
          isAndroid: false,
          isIOS: true,
          isLinux: false,
          isWindows: false,
          isMacOS: false,
        ).family,
        DeliveryPlatformFamily.mobile,
      );
      expect(
        DeliveryPlatformProfile.resolve(
          isAndroid: false,
          isIOS: false,
          isLinux: true,
          isWindows: false,
          isMacOS: false,
        ).family,
        DeliveryPlatformFamily.desktop,
      );
      expect(
        DeliveryPlatformProfile.resolve(
          isAndroid: false,
          isIOS: false,
          isLinux: false,
          isWindows: true,
          isMacOS: false,
        ).family,
        DeliveryPlatformFamily.desktop,
      );
      expect(
        DeliveryPlatformProfile.resolve(
          isAndroid: false,
          isIOS: false,
          isLinux: false,
          isWindows: false,
          isMacOS: true,
        ).family,
        DeliveryPlatformFamily.desktop,
      );
    });

    test('unbound active defaults to desktop so package tests stay thick', () {
      DeliveryPlatformProfile.resetForTest();
      expect(
        DeliveryPlatformProfile.active.family,
        DeliveryPlatformFamily.desktop,
      );
      expect(
        DeliveryPlatformProfile.active.stripchatDefaultCdnDomain,
        'doppiocdn.net',
      );
    });

    test('mobile surface matches last-release CDN query', () {
      DeliveryPlatformProfile.bind(DeliveryPlatformProfile.mobile);
      expect(
        DeliveryPlatformProfile.active.stripchatDefaultCdnDomain,
        'doppiocdn.org',
      );
      expect(
        DeliveryPlatformProfile.active.stripchatMasterPlaylistQuery,
        '?minHeight=240',
      );
      expect(
        DeliveryPlatformProfile.active.stripchatPreferNetCdnFirst,
        isFalse,
      );
    });
  });

  group('HlsProxyDeliveryKnobs', () {
    test('mobile thickens delivery without desktop history pipeline', () {
      final k = HlsProxyDeliveryKnobs.mobile;
      expect(k.scSimplePublish, isTrue);
      expect(k.scWarmAssetPrefetchLimit, greaterThanOrEqualTo(6));
      expect(k.scAutoPrewarmTopVariants, greaterThanOrEqualTo(1));
      expect(k.scHighMaxHistoryExtras, 0);
      expect(k.scPlaylistStickyMaxAge, greaterThan(Duration.zero));
      expect(k.scConnectionTimeout, const Duration(seconds: 15));
      expect(k.twitchEnableStickyCandidate, isTrue);
      expect(k.twitchEnableAssetByteCache, isTrue);
      expect(k.twitchAssetWarmPrefetchLimit, greaterThanOrEqualTo(6));
      expect(k.twitchMaxConnectionsPerHost, greaterThanOrEqualTo(16));
      expect(k.twitchPreferStartupAutoLadder, isFalse);
      expect(k.twitchVariantPlaylistStickyTtl, greaterThan(Duration.zero));
      expect(k.twitchPrewarmStartupVariants, greaterThan(0));
    });

    test('desktop is current thick Linux pipeline', () {
      final k = HlsProxyDeliveryKnobs.desktop;
      expect(k.scSimplePublish, isFalse);
      expect(k.scWarmAssetPrefetchLimit, 16);
      expect(k.scAutoPrewarmTopVariants, 3);
      expect(k.scHighPreferPublishMediaSegments, 8);
      expect(k.scConnectionTimeout, const Duration(seconds: 5));
      expect(k.twitchEnableStickyCandidate, isTrue);
      expect(k.twitchEnableAssetByteCache, isTrue);
      expect(k.twitchAssetWarmPrefetchLimit, 4);
      expect(k.twitchMaxConnectionsPerHost, 16);
    });

    test('fromActiveProfile follows bind', () {
      DeliveryPlatformProfile.bind(DeliveryPlatformProfile.mobile);
      expect(
        HlsProxyDeliveryKnobs.fromActiveProfile().family,
        DeliveryPlatformFamily.mobile,
      );
      DeliveryPlatformProfile.bind(DeliveryPlatformProfile.desktop);
      expect(
        HlsProxyDeliveryKnobs.fromActiveProfile().family,
        DeliveryPlatformFamily.desktop,
      );
    });
  });
}
