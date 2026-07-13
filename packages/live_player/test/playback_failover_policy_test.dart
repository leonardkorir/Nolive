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
