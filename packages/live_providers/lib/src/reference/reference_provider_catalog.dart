import 'package:live_core/live_core.dart';

import '../provider_registry.dart';
import '../danmaku/douyin_danmaku_session.dart'
    show DouyinWebsocketSignatureBuilder;
import '../providers/bilibili/bilibili_provider.dart';
import '../providers/chaturbate/chaturbate_provider.dart';
import '../providers/douyin/douyin_provider.dart';
import '../providers/douyu/douyu_provider.dart';
import '../providers/huya/huya_provider.dart';
import '../providers/migration_placeholder_provider.dart';
import '../providers/twitch/twitch_playback_bootstrap.dart';
import '../providers/twitch/twitch_provider.dart';
import '../providers/youtube/youtube_provider.dart';

class ReferenceProviderCatalog {
  static ProviderRegistry buildDefaultRegistry() => buildPreviewRegistry();

  static ProviderRegistry buildPreviewRegistry() {
    return _buildRegistry(previewRegistrations);
  }

  static ProviderRegistry buildLiveRegistry({
    String Function(String key)? stringSetting,
    int Function(String key)? intSetting,
    DouyinWebsocketSignatureBuilder? douyinDanmakuSignatureBuilder,
    TwitchPlaybackBootstrapResolver? twitchPlaybackBootstrapResolver,
  }) {
    return _buildRegistry(
      liveRegistrations(
        stringSetting: stringSetting,
        intSetting: intSetting,
        douyinDanmakuSignatureBuilder: douyinDanmakuSignatureBuilder,
        twitchPlaybackBootstrapResolver: twitchPlaybackBootstrapResolver,
      ),
    );
  }

  static ProviderRegistry _buildRegistry(
    List<ProviderRegistration> registrations,
  ) {
    final registry = ProviderRegistry();
    for (final registration in registrations) {
      registry.register(registration);
    }
    return registry;
  }

  static final List<ProviderRegistration> previewRegistrations = [
    const ProviderRegistration(
      descriptor: BilibiliProvider.kDescriptor,
      builder: BilibiliProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: ChaturbateProvider.kDescriptor,
      builder: ChaturbateProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: DouyuProvider.kDescriptor,
      builder: DouyuProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: HuyaProvider.kDescriptor,
      builder: HuyaProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: DouyinProvider.kDescriptor,
      builder: DouyinProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: TwitchProvider.kDescriptor,
      builder: TwitchProvider.preview,
    ),
    const ProviderRegistration(
      descriptor: YouTubeProvider.kDescriptor,
      builder: YouTubeProvider.preview,
    ),
  ];

  static List<ProviderRegistration> liveRegistrations({
    String Function(String key)? stringSetting,
    int Function(String key)? intSetting,
    DouyinWebsocketSignatureBuilder? douyinDanmakuSignatureBuilder,
    TwitchPlaybackBootstrapResolver? twitchPlaybackBootstrapResolver,
  }) =>
      [
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () => BilibiliProvider.live(
            cookie: stringSetting?.call('account_bilibili_cookie') ?? '',
            userId: intSetting?.call('account_bilibili_user_id') ?? 0,
          ),
        ),
        ProviderRegistration(
          descriptor: ChaturbateProvider.kDescriptor,
          builder: () => ChaturbateProvider.live(
            cookie: stringSetting?.call('account_chaturbate_cookie') ?? '',
          ),
        ),
        ProviderRegistration(
          descriptor: DouyuProvider.kDescriptor,
          builder: DouyuProvider.live,
        ),
        ProviderRegistration(
          descriptor: HuyaProvider.kDescriptor,
          builder: HuyaProvider.live,
        ),
        ProviderRegistration(
          descriptor: DouyinProvider.kDescriptor,
          builder: () => DouyinProvider.live(
            cookie: stringSetting?.call('account_douyin_cookie') ?? '',
            websocketSignatureBuilder: douyinDanmakuSignatureBuilder,
          ),
        ),
        ProviderRegistration(
          descriptor: TwitchProvider.kDescriptor,
          builder: () => TwitchProvider.live(
            cookie: stringSetting?.call('account_twitch_cookie') ?? '',
            playbackBootstrapResolver: twitchPlaybackBootstrapResolver,
          ),
        ),
        ProviderRegistration(
          descriptor: YouTubeProvider.kDescriptor,
          builder: YouTubeProvider.live,
        ),
      ];

  static LiveProvider createPlaceholder(ProviderId providerId) {
    final registration = previewRegistrations.firstWhere(
      (item) => item.descriptor.id == providerId,
    );
    return MigrationPlaceholderProvider(
      providerDescriptor: registration.descriptor,
    );
  }
}
