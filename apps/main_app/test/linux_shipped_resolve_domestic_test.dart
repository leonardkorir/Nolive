// Shipped ResolvePlaySource path for domestic sites (no WebView required).
// Run: flutter test test/linux_shipped_resolve_domestic_test.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shipped ResolvePlaySource douyu + huya',
    () async {
      // Live HTTP under TestWidgetsFlutterBinding returns 400 for all requests.
      // Opt-in only: NOLIVE_LIVE_PROVIDER_SMOKE=1 flutter test ...
      if (Platform.environment['NOLIVE_LIVE_PROVIDER_SMOKE'] != '1') {
        return;
      }
      final caps = AppPlatformCapabilities.current();
      final bridges = buildAppRuntimeBridgesForTesting(
        mode: AppRuntimeMode.live,
        platformCapabilities: caps,
        loadProviderAccountSettings: LoadProviderAccountSettingsUseCase(
          InMemorySettingsRepository(),
          InMemorySecureCredentialStore(),
        ),
      );
      final registry = ReferenceProviderCatalog.buildLiveRegistry(
        stringSetting: (_) => '',
        intSetting: (_) => 0,
        twitchPlaybackBootstrapResolver: bridges.twitchWebPlaybackBridge?.call,
        youtubeNSigSolver: bridges.youtubeNSigSolver,
      );
      final resolve = ResolvePlaySourceUseCase(
        registry,
        wrapChaturbatePlayUrls: bridges.chaturbateLlHlsProxy?.wrapPlayUrls,
        wrapStripchatPlayUrls: bridges.stripchatLlHlsProxy?.wrapPlayUrls,
        wrapTwitchPlayUrls: bridges.twitchAdGuardProxy?.wrapPlayUrls,
      );

      for (final id in [ProviderId.douyu, ProviderId.huya]) {
        final provider = registry.create(id);
        final recommend = provider.requireContract<SupportsRecommendRooms>(
          ProviderCapability.recommendRooms,
        );
        final rooms = await recommend.fetchRecommendRooms(page: 1);
        expect(rooms.items, isNotEmpty, reason: '$id no rooms');
        final detailApi = provider.requireContract<SupportsRoomDetail>(
          ProviderCapability.roomDetail,
        );
        final detail = await detailApi.fetchRoomDetail(
          rooms.items.first.roomId,
        );
        final qualitiesApi = provider.requireContract<SupportsPlayQualities>(
          ProviderCapability.playQualities,
        );
        final qualities = await qualitiesApi.fetchPlayQualities(detail);
        expect(qualities, isNotEmpty);
        final resolved = await resolve(
          providerId: id,
          detail: detail,
          quality: qualities.first,
        );
        expect(resolved.playUrls, isNotEmpty);
        final url = resolved.playUrls.first.url;
        debugPrint(
          'RESOLVE_OK site=${id.value} url=${url.substring(0, url.length.clamp(0, 100))}',
        );

        final headers = resolved.playUrls.first.headers;
        final args = <String>[
          'timeout',
          '20',
          'mpv',
          '--vo=null',
          '--ao=null',
          '--end=8',
          '--quiet',
          '--no-config',
          '--network-timeout=10',
        ];
        for (final e in headers.entries) {
          args.add('--http-header-fields=${e.key}: ${e.value}');
        }
        args.add(url);
        final r = await Process.run(args.first, args.skip(1).toList());
        final mixed = '${r.stderr}\n${r.stdout}';
        final ok = mixed.contains('VO:') || mixed.contains('Video --vid');
        debugPrint(
          ok ? 'MPV_OK site=${id.value}' : 'MPV_FAIL site=${id.value}',
        );
        expect(ok, isTrue, reason: '$id mpv after ResolvePlaySource');
        debugPrint('RESOLVE_SMOKE_DONE site=${id.value}');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
