import 'dart:async';

import 'package:flutter/widgets.dart';

/// Flutter frame-pipeline hooks the room playback controller needs.
///
/// These are the only reason RoomPlaybackController used to import
/// `flutter/widgets.dart`. Keeping them here lets the controller — and the
/// three controls files that depend on it — live in the application layer,
/// while production still gets real frame synchronisation.
///
/// The controller's own fallbacks are `dart:async`-only, so a caller that
/// forgets to inject degrades to microtask ordering rather than crashing
/// outside a Flutter binding.
void scheduleRoomPlaybackAfterFrame(Future<void> Function() action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(action());
  });
}

Future<void> waitForRoomPlaybackEndOfFrame() {
  return WidgetsBinding.instance.endOfFrame;
}
