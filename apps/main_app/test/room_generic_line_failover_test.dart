import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_generic_line_failover.dart';

void main() {
  final lines = [
    LivePlayUrl(url: 'https://a.example/1.flv', lineLabel: '1'),
    LivePlayUrl(url: 'https://a.example/2.flv', lineLabel: '2'),
  ];

  PlaybackSource sourceOf(LivePlayUrl line) =>
      PlaybackSource(url: Uri.parse(line.url));

  test('generic multi-line failover retries then advances then terminals', () {
    final controller = RoomGenericLineFailoverController(
      policy: const PlaybackFailoverPolicy(maxRetriesPerLine: 2),
    );
    controller.reset(
      playUrls: lines,
      sourceBuilder: sourceOf,
    );

    final first = controller.nextStep()!;
    expect(first.action, PlaybackFailoverAction.retryCurrentLine);
    expect(first.lineIndex, 0);
    expect(first.playbackSource?.url.toString(), lines[0].url);

    final second = controller.nextStep()!;
    expect(second.action, PlaybackFailoverAction.retryCurrentLine);

    final third = controller.nextStep()!;
    expect(third.action, PlaybackFailoverAction.switchToNextLine);
    expect(third.lineIndex, 1);
    expect(third.playbackSource?.url.toString(), lines[1].url);

    controller.nextStep(); // retry line 1
    controller.nextStep(); // retry line 1 again
    final terminal = controller.nextStep()!;
    expect(terminal.action, PlaybackFailoverAction.terminalFailure);
  });

  test(
    'ensureSession with same playUrls does not zero retry across multi-stop',
    () {
      final controller = RoomGenericLineFailoverController(
        policy: const PlaybackFailoverPolicy(maxRetriesPerLine: 2),
      );
      // Simulate room_preview_page: ensureSession then nextStep on every stop.

      expect(
        controller.ensureSession(playUrls: lines, sourceBuilder: sourceOf),
        isTrue,
      );
      expect(controller.retryCount, 0);

      // Stop 1 → first retry of line 0
      expect(
        controller.ensureSession(playUrls: lines, sourceBuilder: sourceOf),
        isFalse,
      );
      final step1 = controller.nextStep()!;
      expect(step1.action, PlaybackFailoverAction.retryCurrentLine);
      expect(step1.retryCount, 1);
      expect(controller.retryCount, 1);

      // Stop 2 → second retry (must NOT re-reset to retryCount=1)
      expect(
        controller.ensureSession(playUrls: lines, sourceBuilder: sourceOf),
        isFalse,
      );
      final step2 = controller.nextStep()!;
      expect(step2.action, PlaybackFailoverAction.retryCurrentLine);
      expect(step2.retryCount, 2);
      expect(controller.retryCount, 2);

      // Stop 3 → advance to next line
      expect(
        controller.ensureSession(playUrls: lines, sourceBuilder: sourceOf),
        isFalse,
      );
      final step3 = controller.nextStep()!;
      expect(step3.action, PlaybackFailoverAction.switchToNextLine);
      expect(step3.lineIndex, 1);
      expect(step3.retryCount, 0);

      // Different playlist (e.g. quality change) does reset.
      final otherLines = [
        LivePlayUrl(url: 'https://b.example/x.flv', lineLabel: 'x'),
      ];
      expect(
        controller.ensureSession(
          playUrls: otherLines,
          sourceBuilder: sourceOf,
        ),
        isTrue,
      );
      expect(controller.retryCount, 0);
      expect(controller.lineIndex, 0);
    },
  );

  test('specialized providers skip generic multi-line failover', () {
    expect(shouldUseGenericMultiLineFailover(ProviderId.bilibili), isTrue);
    expect(shouldUseGenericMultiLineFailover(ProviderId.twitch), isFalse);
    expect(shouldUseGenericMultiLineFailover(ProviderId.chaturbate), isFalse);
    expect(shouldUseGenericMultiLineFailover(ProviderId.stripchat), isFalse);
  });
}
