import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_playback_startup_quality_policy.dart';

void main() {
  const auto = LivePlayQuality(id: 'auto', label: 'Auto', sortOrder: 0);
  const p720 = LivePlayQuality(id: '720', label: '720p', sortOrder: 720);
  const p1080 = LivePlayQuality(id: '1080', label: '1080p', sortOrder: 1080);

  test('youtube on android keeps auto startup quality to preserve HLS auto',
      () {
    final quality = resolveRoomStartupRequestedQuality(
      providerId: ProviderId.youtube,
      qualities: const [auto, p720, p1080],
      requestedQuality: auto,
      targetPlatform: TargetPlatform.android,
      explicitSelection: false,
      isWeb: false,
    );

    expect(quality.id, 'auto');
  });

  test('youtube explicit quality selection is preserved', () {
    final quality = resolveRoomStartupRequestedQuality(
      providerId: ProviderId.youtube,
      qualities: const [auto, p720, p1080],
      requestedQuality: auto,
      targetPlatform: TargetPlatform.android,
      explicitSelection: true,
      isWeb: false,
    );

    expect(quality.id, 'auto');
  });

  test('youtube fixed startup quality stays fixed on android', () {
    final quality = resolveRoomStartupRequestedQuality(
      providerId: ProviderId.youtube,
      qualities: const [auto, p720, p1080],
      requestedQuality: p1080,
      targetPlatform: TargetPlatform.android,
      explicitSelection: false,
      isWeb: false,
    );

    expect(quality.id, '1080');
  });

  test('non-youtube keeps auto startup quality', () {
    final quality = resolveRoomStartupRequestedQuality(
      providerId: ProviderId.bilibili,
      qualities: const [auto, p720, p1080],
      requestedQuality: auto,
      targetPlatform: TargetPlatform.android,
      explicitSelection: false,
      isWeb: false,
    );

    expect(quality.id, 'auto');
  });
}
