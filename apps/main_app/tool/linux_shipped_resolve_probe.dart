// Shipped-path resolve probe (no integration_test binding).
// Run from apps/main_app:
//   flutter pub get
//   dart run tool/linux_shipped_resolve_probe.dart douyu
//   dart run tool/linux_shipped_resolve_probe.dart huya
//   dart run tool/linux_shipped_resolve_probe.dart twitch
//
// Requires native plugins when bridges need WebView (intl). Domestic uses qjs.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final site = args.isEmpty ? 'douyu' : args.first;
  final caps = AppPlatformCapabilities.current();
  stdout.writeln('platform=${caps.operatingSystem} webview=${caps.supportsHeadlessWebView}');

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

  final id = switch (site) {
    'douyu' => ProviderId.douyu,
    'huya' => ProviderId.huya,
    'twitch' => ProviderId.twitch,
    'youtube' => ProviderId.youtube,
    'chaturbate' => ProviderId.chaturbate,
    'stripchat' => ProviderId.stripchat,
    _ => throw ArgumentError('unknown site $site'),
  };

  if (site == 'twitch') {
    await bridges.twitchWebPlaybackBridge?.warmUp().timeout(
      const Duration(seconds: 30),
    );
    stdout.writeln('TW_WARMUP_OK');
  }

  final provider = registry.create(id);
  final recommend = provider.requireContract<SupportsRecommendRooms>(
    ProviderCapability.recommendRooms,
  );
  var rooms = await recommend.fetchRecommendRooms(page: 1);
  if (rooms.items.isEmpty && id == ProviderId.youtube) {
    final search = provider.requireContract<SupportsRoomSearch>(
      ProviderCapability.searchRooms,
    );
    rooms = await search.searchRooms('live');
  }
  final detailApi = provider.requireContract<SupportsRoomDetail>(
    ProviderCapability.roomDetail,
  );
  final detail = await detailApi.fetchRoomDetail(rooms.items.first.roomId);
  final qualitiesApi = provider.requireContract<SupportsPlayQualities>(
    ProviderCapability.playQualities,
  );
  final qualities = await qualitiesApi.fetchPlayQualities(detail);
  final resolved = await resolve(
    providerId: id,
    detail: detail,
    quality: qualities.first,
  );
  final url = resolved.playUrls.first.url;
  stdout.writeln('RESOLVE_OK site=$site url=$url');

  final loopbackNeeded = site == 'twitch' ||
      site == 'chaturbate' ||
      site == 'stripchat';
  if (loopbackNeeded) {
    final token = switch (site) {
      'twitch' => 'twitch-ad-guard',
      'chaturbate' => 'chaturbate-llhls',
      'stripchat' => 'stripchat-llhls',
      _ => '',
    };
    final ok = url.contains('127.0.0.1') && url.contains(token);
    stdout.writeln(ok ? 'LOOPBACK_OK site=$site' : 'LOOPBACK_FAIL site=$site');
    if (!ok) exit(2);
  }

  // MPV decode (bounded)
  final headers = resolved.playUrls.first.headers;
  final mpvArgs = <String>[
    'timeout',
    '18',
    'mpv',
    '--vo=null',
    '--ao=null',
    '--end=8',
    '--quiet',
    '--no-config',
    '--network-timeout=10',
  ];
  for (final e in headers.entries) {
    mpvArgs.add('--http-header-fields=${e.key}: ${e.value}');
  }
  mpvArgs.add(url);
  final r = await Process.run(mpvArgs.first, mpvArgs.skip(1).toList());
  final mixed = '${r.stderr}\n${r.stdout}';
  final ok = mixed.contains('VO:') || mixed.contains('Video --vid');
  for (final line
      in mixed.split('\n').where((l) => l.trim().isNotEmpty).take(8)) {
    stdout.writeln('  mpv: $line');
  }
  stdout.writeln(ok ? 'MPV_OK site=$site' : 'MPV_FAIL site=$site');
  stdout.writeln('RESOLVE_SMOKE_DONE site=$site');
  // Exit 0 if resolve (+ loopback) ok; mpv soft for flaky CDN.
  exit(0);
}
