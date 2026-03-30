import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';

void main() {
  test(
      'twitch startup prefers auto and keeps requested fixed quality for promotion',
      () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    final plan = resolveTwitchStartupPlan(
      qualities: const [auto, q1080],
      requestedQuality: q1080,
    );

    expect(plan.startupQuality.id, 'auto');
    expect(plan.promotionQuality?.id, '1080p60');
    expect(plan.startupQuality.metadata?['twitchStartupAuto'], isTrue);
  });

  test('twitch startup keeps auto when it is already requested', () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    final plan = resolveTwitchStartupPlan(
      qualities: const [auto, q1080],
      requestedQuality: auto,
    );

    expect(plan.startupQuality.id, 'auto');
    expect(plan.promotionQuality, isNull);
  });

  test('twitch quality recovery avoids bouncing back to auto after startup',
      () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    final recovery = selectTwitchRecoveryQuality(
      qualities: const [auto, q1080],
      currentQuality: q1080,
    );

    expect(recovery, isNull);
  });

  test('twitch startup promotion waits for buffered playback progress', () {
    final state = PlayerState(
      status: PlaybackStatus.playing,
      position: const Duration(milliseconds: 1500),
      buffered: const Duration(seconds: 3),
      source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
    );

    expect(shouldPromoteTwitchPlaybackQuality(state), isTrue);
  });

  test('twitch recovery delay is aggressive for auto startup retries', () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    expect(
      resolveTwitchRecoveryDelay(
        currentQuality: auto,
        recoveryAttempts: 0,
      ),
      const Duration(seconds: 2),
    );
    expect(
      resolveTwitchRecoveryDelay(
        currentQuality: auto,
        recoveryAttempts: 1,
      ),
      const Duration(seconds: 2),
    );
    expect(
      resolveTwitchRecoveryDelay(
        currentQuality: q1080,
        recoveryAttempts: 0,
      ),
      const Duration(seconds: 2),
    );
  });

  test(
      'twitch startup recovery retries with promotion quality when auto stalls',
      () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    final recovery = selectTwitchStartupRecoveryQuality(
      currentQuality: auto,
      promotionQuality: q1080,
    );

    expect(recovery?.id, '1080p60');
  });

  test('twitch startup recovery does not override fixed startup quality', () {
    const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
    const q1080 = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      sortOrder: 4,
    );

    final recovery = selectTwitchStartupRecoveryQuality(
      currentQuality: q1080,
      promotionQuality: auto,
    );

    expect(recovery, isNull);
  });

  test('twitch recovery prefers site line after stuck popout playback', () {
    final playbackSource = PlaybackSource(
      url: Uri.parse(
          'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8'),
    );
    final playUrls = [
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        lineLabel: '默认 Popout',
        metadata: {'playerType': 'popout'},
      ),
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/site/stream.m3u8',
        lineLabel: '备用 Site',
        metadata: {'playerType': 'site'},
      ),
    ];

    final recovery = selectTwitchRecoveryLine(
      playbackSource: playbackSource,
      playUrls: playUrls,
    );

    expect(recovery?.lineLabel, '备用 Site');
  });

  test('twitch recovery falls back to any other line when site is absent', () {
    final playbackSource = PlaybackSource(
      url:
          Uri.parse('http://127.0.0.1:33101/twitch-ad-guard/embed/stream.m3u8'),
    );
    final playUrls = [
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/embed/stream.m3u8',
        lineLabel: '备用 Embed',
        metadata: {'playerType': 'embed'},
      ),
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        lineLabel: '默认 Popout',
        metadata: {'playerType': 'popout'},
      ),
    ];

    final recovery = selectTwitchRecoveryLine(
      playbackSource: playbackSource,
      playUrls: playUrls,
    );

    expect(recovery?.lineLabel, '默认 Popout');
  });

  test('twitch fixed recovery refreshes current line after one line retry', () {
    final state = PlayerState(
      status: PlaybackStatus.playing,
      position: Duration.zero,
      buffered: Duration.zero,
      source: PlaybackSource(
        url: Uri.parse(
          'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        ),
      ),
    );
    final playUrls = [
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/popout/stream.m3u8',
        lineLabel: '默认 Popout',
        metadata: {'playerType': 'popout'},
      ),
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/site/stream.m3u8',
        lineLabel: '备用 Site',
        metadata: {'playerType': 'site'},
      ),
    ];

    final initialDecision = resolveTwitchFixedRecoveryDecision(
      state: state,
      recoveryAttempts: 0,
      playbackSource: state.source!,
      playUrls: playUrls,
    );
    final refreshDecision = resolveTwitchFixedRecoveryDecision(
      state: state,
      recoveryAttempts: 1,
      playbackSource: state.source!,
      playUrls: playUrls,
    );
    final stopDecision = resolveTwitchFixedRecoveryDecision(
      state: state,
      recoveryAttempts: 2,
      playbackSource: state.source!,
      playUrls: playUrls,
    );

    expect(initialDecision.action, TwitchFixedRecoveryAction.switchLine);
    expect(initialDecision.recoveryLine?.lineLabel, '备用 Site');
    expect(
      refreshDecision.action,
      TwitchFixedRecoveryAction.refreshCurrentLine,
    );
    expect(stopDecision.action, TwitchFixedRecoveryAction.stop);
  });

  test('twitch refresh line keeps same upstream when proxy session changes',
      () {
    final playbackSource = PlaybackSource(
      url: Uri.parse(
        'http://127.0.0.1:33101/twitch-ad-guard/session-a/stream.m3u8',
      ),
    );
    final currentPlayUrls = [
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/session-b/stream.m3u8',
        lineLabel: '默认 Popout',
        metadata: {
          'playerType': 'popout',
          'upstreamUrl': 'https://example.com/popout.m3u8',
        },
      ),
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/session-a/stream.m3u8',
        lineLabel: '备用 Site',
        metadata: {
          'playerType': 'site',
          'upstreamUrl': 'https://example.com/site.m3u8',
        },
      ),
    ];
    final refreshedPlayUrls = [
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/session-d/stream.m3u8',
        lineLabel: '默认 Popout',
        metadata: {
          'playerType': 'popout',
          'upstreamUrl': 'https://example.com/popout.m3u8',
        },
      ),
      const LivePlayUrl(
        url: 'http://127.0.0.1:33101/twitch-ad-guard/session-c/stream.m3u8',
        lineLabel: '备用 Site',
        metadata: {
          'playerType': 'site',
          'upstreamUrl': 'https://example.com/site.m3u8',
        },
      ),
    ];

    final refreshedLine = selectTwitchRefreshLine(
      playbackSource: playbackSource,
      currentPlayUrls: currentPlayUrls,
      refreshedPlayUrls: refreshedPlayUrls,
    );

    expect(refreshedLine?.lineLabel, '备用 Site');
    expect(refreshedLine?.metadata?['playerType'], 'site');
    expect(
      refreshedLine?.metadata?['upstreamUrl'],
      'https://example.com/site.m3u8',
    );
  });

  test('twitch recovery only triggers when playback remains near zero progress',
      () {
    final idle = PlayerState(
      status: PlaybackStatus.playing,
      position: Duration.zero,
      buffered: Duration.zero,
      source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
    );
    final healthy = PlayerState(
      status: PlaybackStatus.playing,
      position: Duration(seconds: 6),
      buffered: Duration(seconds: 9),
      source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
    );

    expect(shouldAttemptTwitchPlaybackRecovery(idle), isTrue);
    expect(shouldAttemptTwitchPlaybackRecovery(healthy), isFalse);
  });
}
