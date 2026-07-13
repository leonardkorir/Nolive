import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_play_selection_policy.dart';

void main() {
  test('chaturbate startup quality prefers highest fixed tier', () {
    final selected = selectRoomStartupQuality(
      providerId: ProviderId.chaturbate,
      qualities: [
        LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        LivePlayQuality(id: '720', label: '720p', sortOrder: 720),
        LivePlayQuality(id: '1080', label: '1080p', sortOrder: 1080),
      ],
    );
    expect(selected.id, '1080');
  });

  test('bilibili preferred urls favor exact qn and penalize mcdn', () {
    final urls = preferredPlayUrlsForQuality(
      providerId: ProviderId.bilibili,
      requestedQuality: LivePlayQuality(id: '10000', label: '原画'),
      urls: [
        LivePlayUrl(
          url: 'https://mcdn.example/live.m3u8?qn=10000',
          metadata: const {'qn': 10000},
        ),
        LivePlayUrl(
          url: 'https://cn-gotcha.example/live.m3u8?qn=10000',
          metadata: const {'qn': 10000},
        ),
        LivePlayUrl(
          url: 'https://cn-gotcha.example/live.m3u8?qn=80',
          metadata: const {'qn': 80},
        ),
      ],
    );
    expect(urls.first.url, contains('cn-gotcha'));
    expect(urls.first.metadata?['qn'], 10000);
  });

  test('twitch preferred urls order popout before site player types', () {
    final urls = preferredPlayUrlsForQuality(
      providerId: ProviderId.twitch,
      requestedQuality: LivePlayQuality(id: 'auto', label: 'Auto'),
      urls: [
        LivePlayUrl(
          url: 'https://example.com/site.m3u8',
          metadata: const {'playerType': 'site'},
        ),
        LivePlayUrl(
          url: 'https://example.com/popout.m3u8',
          metadata: const {'playerType': 'popout'},
        ),
      ],
    );
    expect(urls.first.url, contains('popout'));
  });
}
