import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  const policy = PlaybackFailoverPolicy(maxRetriesPerLine: 2);

  test('retries current line before advancing', () {
    final first = policy.decide(
      currentLineIndex: 0,
      lineCount: 3,
      retryCountOnCurrentLine: 0,
    );
    expect(first.action, PlaybackFailoverAction.retryCurrentLine);
    expect(first.nextRetryCount, 1);
    expect(first.nextLineIndex, 0);

    final second = policy.decide(
      currentLineIndex: 0,
      lineCount: 3,
      retryCountOnCurrentLine: 1,
    );
    expect(second.action, PlaybackFailoverAction.retryCurrentLine);
    expect(second.nextRetryCount, 2);
    expect(second.delay, const Duration(seconds: 1));
  });

  test('switches to next line after retries exhausted', () {
    final decision = policy.decide(
      currentLineIndex: 0,
      lineCount: 3,
      retryCountOnCurrentLine: 2,
    );
    expect(decision.action, PlaybackFailoverAction.switchToNextLine);
    expect(decision.nextLineIndex, 1);
    expect(decision.nextRetryCount, 0);
  });

  test('terminal failure on last line after retries', () {
    final decision = policy.decide(
      currentLineIndex: 2,
      lineCount: 3,
      retryCountOnCurrentLine: 2,
    );
    expect(decision.action, PlaybackFailoverAction.terminalFailure);
    expect(decision.nextLineIndex, 2);
  });

  test('default policy soft-retries once then switches', () {
    const liveDefault = PlaybackFailoverPolicy();
    final soft = liveDefault.decide(
      currentLineIndex: 0,
      lineCount: 2,
      retryCountOnCurrentLine: 0,
    );
    expect(soft.action, PlaybackFailoverAction.retryCurrentLine);
    expect(soft.nextRetryCount, 1);

    final afterSoft = liveDefault.decide(
      currentLineIndex: 0,
      lineCount: 2,
      retryCountOnCurrentLine: 1,
    );
    expect(afterSoft.action, PlaybackFailoverAction.switchToNextLine);
    expect(afterSoft.nextLineIndex, 1);
  });

  test('preferSwitchLine skips same-line retries on hard open failure', () {
    const policyWithRetries = PlaybackFailoverPolicy(maxRetriesPerLine: 2);
    final decision = policyWithRetries.decide(
      currentLineIndex: 0,
      lineCount: 2,
      retryCountOnCurrentLine: 0,
      preferSwitchLine: true,
    );
    expect(decision.action, PlaybackFailoverAction.switchToNextLine);
    expect(decision.nextLineIndex, 1);
  });

  test('preferSwitchLine on last line goes terminal without free retry', () {
    const liveDefault = PlaybackFailoverPolicy();
    final decision = liveDefault.decide(
      currentLineIndex: 1,
      lineCount: 2,
      retryCountOnCurrentLine: 0,
      preferSwitchLine: true,
    );
    expect(decision.action, PlaybackFailoverAction.terminalFailure);
  });

  test('isHardOpenFailure detects Douyu/mpv open errors', () {
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'Failed to open https://hw3.douyucdn2.cn/live/x.flv',
      ),
      isTrue,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'tcp: ffurl_read returned 0xdfb9b0bb',
      ),
      isTrue,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure('connection refused'),
      isTrue,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure('HTTP 404 Not Found'),
      isTrue,
    );
    expect(PlaybackFailoverPolicy.isHardOpenFailure('status code 403'), isTrue);
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'Failed to open: connection timed out',
      ),
      isTrue,
    );
  });

  test('isHardOpenFailure demotes mid-stream glitches after playing', () {
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'tcp: ffurl_read returned 0xdfb9b0bb',
        hasReachedPlaying: true,
      ),
      isFalse,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'connection reset by peer',
        hasReachedPlaying: true,
      ),
      isFalse,
    );
    // Explicit open failure stays hard even after playing.
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'Failed to open https://hw3.example/a.flv',
        hasReachedPlaying: true,
      ),
      isTrue,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'HTTP 404 Not Found',
        hasReachedPlaying: true,
      ),
      isTrue,
    );
  });

  test('isHardOpenFailure rejects soft stalls and path false positives', () {
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure('buffering underrun'),
      isFalse,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure('read timeout while demuxing'),
      isFalse,
    );
    expect(
      PlaybackFailoverPolicy.isHardOpenFailure(
        'https://cdn.example/path/v404/segment.ts',
      ),
      isFalse,
    );
    expect(PlaybackFailoverPolicy.isHardOpenFailure(null), isFalse);
    expect(PlaybackFailoverPolicy.isHardOpenFailure(''), isFalse);
  });

  test('selectQualityIndex maps ladder correctly', () {
    expect(
      selectQualityIndex(
        qualityCount: 5,
        preference: NetworkQualityPreference.highest,
      ),
      0,
    );
    expect(
      selectQualityIndex(
        qualityCount: 5,
        preference: NetworkQualityPreference.lowest,
      ),
      4,
    );
    expect(
      selectQualityIndex(
        qualityCount: 5,
        preference: NetworkQualityPreference.middle,
      ),
      2,
    );
  });

  test('resolveNetworkQualityPreference prefers cellular when mobile', () {
    expect(
      resolveNetworkQualityPreference(
        isCellular: true,
        wifiPreference: NetworkQualityPreference.highest,
        cellularPreference: NetworkQualityPreference.lowest,
      ),
      NetworkQualityPreference.lowest,
    );
    expect(
      resolveNetworkQualityPreference(
        isCellular: false,
        wifiPreference: NetworkQualityPreference.highest,
        cellularPreference: NetworkQualityPreference.lowest,
      ),
      NetworkQualityPreference.highest,
    );
  });
}
