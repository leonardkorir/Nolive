import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/parse/application/parse_room_input_use_case.dart';

/// Guards the dispatch points that must name every provider.
///
/// [ProviderId] is a class, not an enum, so `switch` over it can never be
/// exhaustive and the analyzer stays silent when a provider is added and a
/// branch is forgotten. Everything that would then fail *at runtime, quietly*
/// belongs here.
///
/// Two categories are deliberately absent. Per-site behaviour that degrades
/// gracefully (quality-id extraction, playback URL shaping, display-name
/// fallbacks) is designed to fall through to a generic path. And places whose
/// shape is checked by the compiler — [ProviderAccountDashboard] has one named
/// field per provider, so omitting one fails to compile — need no test.
void main() {
  ProviderRegistry buildRegistry() {
    final registry = ProviderRegistry();
    for (final registration in ReferenceProviderCatalog.previewRegistrations) {
      registry.register(registration);
    }
    return registry;
  }

  test('the reference catalog registers every known provider', () {
    final registered = ReferenceProviderCatalog.previewRegistrations
        .map((registration) => registration.descriptor.id)
        .toSet();

    final missing = ProviderId.knownValues
        .where((id) => !registered.contains(id))
        .map((id) => id.value)
        .toList(growable: false);

    expect(
      missing,
      isEmpty,
      reason: 'a provider nobody can construct is not usable at all',
    );
  });

  test('every provider is reachable through the "<id>:<room>" prefix', () {
    // A room id valid for that provider's descriptor patterns. Adding a
    // provider forces adding a sample here, which is the point: it makes the
    // author confirm the prefix branch exists rather than discovering later
    // that pasting a link for the new site silently says "未能识别平台".
    final sampleRoomIds = <ProviderId, String>{
      ProviderId.bilibili: '21144080',
      ProviderId.douyu: '6512',
      ProviderId.huya: '660000',
      ProviderId.douyin: '6753235366',
      ProviderId.chaturbate: 'demoroom',
      ProviderId.twitch: 'demoroom',
      ProviderId.youtube: '@demo-channel/live',
      ProviderId.stripchat: 'demoroom',
    };

    final unsampled = ProviderId.knownValues
        .where((id) => !sampleRoomIds.containsKey(id))
        .map((id) => id.value)
        .toList(growable: false);
    expect(
      unsampled,
      isEmpty,
      reason: 'add a valid sample room id for the new provider',
    );

    final parse = ParseRoomInputUseCase(buildRegistry());
    final unreachable = <String>[];

    for (final providerId in ProviderId.knownValues) {
      final roomId = sampleRoomIds[providerId]!;
      final result = parse(rawInput: '${providerId.value}:$roomId');
      if (!result.isSuccess || result.parsedRoom?.providerId != providerId) {
        unreachable.add('${providerId.value} (${result.errorMessage ?? '-'})');
      }
    }

    expect(
      unreachable,
      isEmpty,
      reason:
          'Add the provider to _tryParseProviderPrefix. Without it a user can '
          'never paste a room for that site, and nothing reports the gap.',
    );
  });

  test('clearing the provider cache covers every provider', () {
    // Credential clear/migration used to invalidate a hand-written list of
    // five providers, silently omitting Stripchat even though its cookie and
    // Mouflon keys are both secure credentials — so a cached Stripchat
    // provider kept serving values the user had just wiped. Those paths call
    // clearCache() now; this pins that clearCache really drops everything.
    final registry = buildRegistry();
    final firstPass = <ProviderId, LiveProvider>{};
    for (final providerId in ProviderId.knownValues) {
      firstPass[providerId] = registry.create(providerId);
    }

    registry.clearCache();

    final stale = <String>[];
    for (final providerId in ProviderId.knownValues) {
      if (identical(registry.create(providerId), firstPass[providerId])) {
        stale.add(providerId.value);
      }
    }

    expect(
      stale,
      isEmpty,
      reason: 'a provider surviving clearCache keeps stale credentials',
    );
  });
}
