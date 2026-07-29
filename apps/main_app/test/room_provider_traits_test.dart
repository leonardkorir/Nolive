import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_detail_override_policy.dart';
import 'package:nolive_app/src/features/room/application/room_generic_line_failover.dart';
import 'package:nolive_app/src/features/room/application/room_play_selection_policy.dart';
import 'package:nolive_app/src/features/room/application/room_playback_recovery_policy.dart';
import 'package:nolive_app/src/features/room/application/room_provider_traits.dart';

void main() {
  test('every known provider has an explicit room traits row', () {
    final missing = ProviderId.knownValues
        .where((id) => !roomProviderTraitsTable.containsKey(id))
        .map((id) => id.value)
        .toList(growable: false);

    expect(
      missing,
      isEmpty,
      reason:
          'Add a row to roomProviderTraitsTable for each new provider and '
          'decide every capability explicitly rather than inheriting defaults.',
    );
  });

  test('an unregistered provider falls back to generic handling', () {
    final traits = roomProviderTraitsFor(const ProviderId('brand-new-site'));

    expect(traits.usesGenericMultiLineFailover, isTrue);
    expect(traits.allowsRoomDetailOverride, isTrue);
    expect(traits.autoRecoversUnexpectedStop, isTrue);
    expect(traits.prefersMpvOnAndroid, isFalse);
    expect(traits.usesHeadlessStartupPromotion, isFalse);
    expect(traits.usesLadderStartupQualityPlan, isFalse);
    expect(traits.usesFixedLineRecovery, isFalse);
    expect(traits.supportsAdaptiveAutoQuality, isTrue);
    expect(traits.skipsEquivalentProxyRebind, isFalse);
    expect(traits.waitsForSurfaceOnInitialBootstrap, isFalse);
    expect(traits.retainsPlaybackOnReloadParseFailure, isFalse);
    expect(traits.playbackRebindSettleDelay, Duration.zero);
    expect(traits.initialBootstrapSettleDelay, Duration.zero);
  });

  group('traits preserve the behaviour the scattered checks encoded', () {
    test('providers owning specialized recovery skip generic failover', () {
      for (final id in ProviderId.knownValues) {
        final expected =
            id != ProviderId.twitch &&
            id != ProviderId.chaturbate &&
            id != ProviderId.stripchat;
        expect(
          shouldUseGenericMultiLineFailover(id),
          expected,
          reason: 'generic failover for ${id.value}',
        );
      }
    });

    test('only chaturbate blocks the room detail override', () {
      for (final id in ProviderId.knownValues) {
        expect(
          shouldAllowRoomDetailOverride(id),
          id != ProviderId.chaturbate,
          reason: 'detail override for ${id.value}',
        );
      }
    });

    test('only stripchat opts out of unexpected-stop auto-recovery', () {
      for (final id in ProviderId.knownValues) {
        expect(
          roomShouldRecoverUnexpectedPlaybackStop(
            providerId: id,
            refreshInFlight: false,
          ),
          id != ProviderId.stripchat,
          reason: 'auto-recovery for ${id.value}',
        );
      }
    });

    test('android mpv is forced for the four international providers', () {
      final forced = {
        ProviderId.youtube,
        ProviderId.twitch,
        ProviderId.chaturbate,
        ProviderId.stripchat,
      };
      for (final id in ProviderId.knownValues) {
        expect(
          roomProviderTraitsFor(id).prefersMpvOnAndroid,
          forced.contains(id),
          reason: 'mpv preference for ${id.value}',
        );
      }
    });

    test('headless startup promotion covers twitch and stripchat', () {
      final promoted = {ProviderId.twitch, ProviderId.stripchat};
      for (final id in ProviderId.knownValues) {
        expect(
          roomProviderTraitsFor(id).usesHeadlessStartupPromotion,
          promoted.contains(id),
          reason: 'startup promotion for ${id.value}',
        );
      }
    });

    test('only twitch carries post-bind settle delays', () {
      for (final id in ProviderId.knownValues) {
        final traits = roomProviderTraitsFor(id);
        if (id == ProviderId.twitch) {
          expect(
            traits.playbackRebindSettleDelay,
            const Duration(milliseconds: 120),
          );
          expect(
            traits.initialBootstrapSettleDelay,
            const Duration(milliseconds: 220),
          );
          expect(traits.waitsForSurfaceOnInitialBootstrap, isTrue);
        } else {
          expect(traits.playbackRebindSettleDelay, Duration.zero);
          expect(traits.initialBootstrapSettleDelay, Duration.zero);
          expect(traits.waitsForSurfaceOnInitialBootstrap, isFalse);
        }
      }
    });

    test('proxy-equivalent rebind skipping is chaturbate only', () {
      for (final id in ProviderId.knownValues) {
        expect(
          roomProviderTraitsFor(id).skipsEquivalentProxyRebind,
          id == ProviderId.chaturbate,
          reason: 'proxy rebind skip for ${id.value}',
        );
      }
    });

    test('reload parse-failure playback retention is youtube only', () {
      for (final id in ProviderId.knownValues) {
        expect(
          roomProviderTraitsFor(id).retainsPlaybackOnReloadParseFailure,
          id == ProviderId.youtube,
          reason: 'reload retention for ${id.value}',
        );
      }
    });

    test('ladder startup plan and fixed-line recovery are twitch only', () {
      for (final id in ProviderId.knownValues) {
        final traits = roomProviderTraitsFor(id);
        expect(
          traits.usesLadderStartupQualityPlan,
          id == ProviderId.twitch,
          reason: 'ladder startup plan for ${id.value}',
        );
        expect(
          traits.usesFixedLineRecovery,
          id == ProviderId.twitch,
          reason: 'fixed line recovery for ${id.value}',
        );
      }
    });

    test('only youtube lacks a usable adaptive auto ladder', () {
      for (final id in ProviderId.knownValues) {
        expect(
          supportsAdaptiveAutoQuality(id),
          id != ProviderId.youtube,
          reason: 'adaptive auto for ${id.value}',
        );
      }
    });

    test('android auto-quality startup promotion is youtube only', () {
      for (final id in ProviderId.knownValues) {
        expect(
          roomProviderTraitsFor(id).promotesAndroidAutoQualityAtStartup,
          id == ProviderId.youtube,
          reason: 'auto quality promotion for ${id.value}',
        );
      }
    });
  });
}
