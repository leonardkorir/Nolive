import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/presentation/follow_progressive_ui_controller.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

FollowWatchlist _list(String roomId) {
  return FollowWatchlist(
    entries: [
      FollowWatchEntry(
        record: FollowRecord(
          providerId: const ProviderId('demo'),
          roomId: roomId,
          streamerName: roomId,
        ),
      ),
    ],
  );
}

void main() {
  test(
    'stale coalesced flush and commitFinal do not overwrite a newer generation',
    () async {
      var generation = 0;
      final snapshots = <String>[];
      final pagePaints = <String>[];

      final controller = FollowProgressiveUiController(
        isMounted: () => true,
        currentGeneration: () => generation,
        writeSnapshot: (w) => snapshots.add(w.entries.single.roomId),
        applyWatchlistToPage: (w) => pagePaints.add(w.entries.single.roomId),
        coalesceInterval: const Duration(milliseconds: 40),
      );

      // Generation 1 starts and schedules progressive UI.
      generation = 1;
      controller.beginGeneration(1);
      controller.onEntryResolved(1, _list('old'));
      expect(snapshots, ['old']);
      expect(pagePaints, isEmpty);
      expect(controller.hasPendingFlush, isTrue);

      // Generation 2 supersedes before the timer fires.
      generation = 2;
      controller.beginGeneration(2);
      expect(controller.hasPendingFlush, isFalse);

      // Stale gen-1 terminal commit must be ignored.
      controller.commitFinal(1, _list('old-final'));
      expect(snapshots, ['old']);
      expect(pagePaints, isEmpty);

      // Current gen paints immediately on final commit.
      controller.commitFinal(2, _list('new-final'));
      expect(snapshots.last, 'new-final');
      expect(pagePaints, ['new-final']);

      // Ensure any residual timer from gen 1 does not paint after wait.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(pagePaints, ['new-final']);

      controller.dispose();
    },
  );

  test('onEntryResolved ignores superseded generation without writing snapshot',
      () {
    var generation = 2;
    final snapshots = <String>[];
    final pagePaints = <String>[];
    final controller = FollowProgressiveUiController(
      isMounted: () => true,
      currentGeneration: () => generation,
      writeSnapshot: (w) => snapshots.add(w.entries.single.roomId),
      applyWatchlistToPage: (w) => pagePaints.add(w.entries.single.roomId),
    );

    controller.beginGeneration(2);
    controller.onEntryResolved(1, _list('stale'));
    expect(snapshots, isEmpty);
    expect(pagePaints, isEmpty);

    controller.onEntryResolved(2, _list('live'));
    expect(snapshots, ['live']);
    controller.dispose();
  });
}
