import 'package:test/test.dart';

import 'support/chaturbate_fixture_loader.dart';
import 'support/stripchat_fixture_loader.dart';
import 'support/twitch_fixture_loader.dart';
import 'support/youtube_fixture_loader.dart';

void main() {
  test('fixture skip reasons list the exact missing local artifacts', () {
    final loaders = <_FixtureSkipContract>[
      _FixtureSkipContract(
        providerName: 'Twitch',
        missingArtifacts: TwitchFixtureLoader.missingArtifacts,
        skipReason: TwitchFixtureLoader.skipReason,
      ),
      _FixtureSkipContract(
        providerName: 'Chaturbate',
        missingArtifacts: ChaturbateFixtureLoader.missingArtifacts,
        skipReason: ChaturbateFixtureLoader.skipReason,
      ),
      _FixtureSkipContract(
        providerName: 'YouTube',
        missingArtifacts: YouTubeFixtureLoader.missingArtifacts,
        skipReason: YouTubeFixtureLoader.skipReason,
      ),
      _FixtureSkipContract(
        providerName: 'Stripchat',
        missingArtifacts: StripchatFixtureLoader.missingArtifacts,
        skipReason: StripchatFixtureLoader.skipReason,
      ),
    ];

    for (final loader in loaders) {
      expect(
        loader.missingArtifacts.toSet(),
        hasLength(loader.missingArtifacts.length),
        reason: '${loader.providerName} missing artifact list must be stable.',
      );

      if (loader.missingArtifacts.isEmpty) {
        expect(
          loader.skipReason,
          isNull,
          reason:
              '${loader.providerName} should not skip when all fixtures exist.',
        );
        continue;
      }

      expect(loader.skipReason, isNotNull);
      expect(loader.skipReason, contains(loader.providerName));
      for (final artifact in loader.missingArtifacts) {
        expect(
          loader.skipReason,
          contains(artifact),
          reason:
              '${loader.providerName} skip reason must name every missing artifact.',
        );
      }
    }
  });
}

class _FixtureSkipContract {
  const _FixtureSkipContract({
    required this.providerName,
    required this.missingArtifacts,
    required this.skipReason,
  });

  final String providerName;
  final List<String> missingArtifacts;
  final String? skipReason;
}
