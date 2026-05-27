import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/features/settings/application/stripchat_mouflon_key_store.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test('stripchat mouflon key cache keeps newest 16 records', () {
    var cache = const StripchatMouflonKeyCache();
    for (var index = 0; index < 20; index += 1) {
      cache = cache.mergeRecords(
        <StripchatMouflonKeyRecord>[
          StripchatMouflonKeyRecord(
            pkey: 'p$index',
            pdkey: 'd$index',
            capturedAt: DateTime.utc(2026, 5, 7, 12, index),
            source: StripchatCalibrationSource.auto,
          ),
        ],
        source: StripchatCalibrationSource.auto,
        capturedAt: DateTime.utc(2026, 5, 7, 12, index),
      );
    }

    expect(cache.records, hasLength(16));
    expect(cache.lookup('p19')?.pdkey, 'd19');
    expect(cache.lookup('p0'), isNull);
  });

  test('stripchat mouflon key import rejects malformed rows', () {
    expect(
      () => parseStripchatMouflonImport(
        'broken-line',
        source: StripchatCalibrationSource.manual,
      ),
      throwsFormatException,
    );
  });

  test(
    'stripchat mouflon key cache round-trips through secure settings',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();
      final updateSettings = UpdateProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      );
      final loadSettings = LoadProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      );

      final cache = const StripchatMouflonKeyCache().mergeRecords(
        <StripchatMouflonKeyRecord>[
          StripchatMouflonKeyRecord(
            pkey: 'alpha',
            pdkey: 'beta',
            capturedAt: DateTime.utc(2026, 5, 7, 12),
            source: StripchatCalibrationSource.manual,
          ),
        ],
        source: StripchatCalibrationSource.manual,
        capturedAt: DateTime.utc(2026, 5, 7, 12),
      );

      await updateSettings(
        ProviderAccountSettings(
          bilibiliCookie: '',
          bilibiliUserId: 0,
          chaturbateCookie: '',
          douyinCookie: '',
          stripchatCookie: 'cookie',
          stripchatMouflonKeys: cache,
          twitchCookie: '',
          youtubeCookie: '',
        ),
      );

      final raw = await secureCredentialStore.read(
        SensitiveSettingKeys.accountStripchatMouflonKeys,
      );
      final loaded = await loadSettings();

      expect(raw, contains('"pkey":"ahpla"'));
      expect(raw, contains('"captureSource":"manual"'));
      expect(loaded.stripchatMouflonKeys.lookup('alpha')?.pdkey, 'beta');
      expect(
        loaded.stripchatMouflonKeys.lookup('alpha')?.captureSource,
        'manual',
      );
    },
  );

  test(
    'stripchat mouflon key cache round-trips multiple records from one calibration save',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();
      final updateSettings = UpdateProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      );
      final loadSettings = LoadProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      );

      final cache = const StripchatMouflonKeyCache().mergeRecords(
        <StripchatMouflonKeyRecord>[
          StripchatMouflonKeyRecord(
            pkey: 'Ook7quaiNgiyuhai',
            pdkey: '8iPRUU0AnxoOSif9',
            capturedAt: DateTime.utc(2026, 5, 8, 1, 2, 10),
            source: StripchatCalibrationSource.auto,
          ),
          StripchatMouflonKeyRecord(
            pkey: 'Zeechoej4aleeshi',
            pdkey: 'ubahjae7goPoodi6',
            capturedAt: DateTime.utc(2026, 5, 8, 1, 2, 10),
            source: StripchatCalibrationSource.auto,
          ),
        ],
        source: StripchatCalibrationSource.auto,
        capturedAt: DateTime.utc(2026, 5, 8, 1, 2, 10),
      );

      await updateSettings(
        ProviderAccountSettings(
          bilibiliCookie: '',
          bilibiliUserId: 0,
          chaturbateCookie: '',
          douyinCookie: '',
          stripchatCookie: 'cookie',
          stripchatMouflonKeys: cache,
          twitchCookie: '',
          youtubeCookie: '',
        ),
      );

      final raw = await secureCredentialStore.read(
        SensitiveSettingKeys.accountStripchatMouflonKeys,
      );
      final loaded = await loadSettings();

      expect(raw, contains('"pkey":"iahuyigNiauq7koO"'));
      expect(raw, contains('"pkey":"ihseela4jeohceeZ"'));
      expect(loaded.stripchatMouflonKeys.records, hasLength(2));
      expect(
        loaded.stripchatMouflonKeys.lookup('Ook7quaiNgiyuhai')?.pdkey,
        '8iPRUU0AnxoOSif9',
      );
      expect(
        loaded.stripchatMouflonKeys.lookup('Zeechoej4aleeshi')?.pdkey,
        'ubahjae7goPoodi6',
      );
    },
  );

  test('stripchat mouflon key cache keeps higher-priority capture source', () {
    final older = const StripchatMouflonKeyCache().mergeRecords(
      <StripchatMouflonKeyRecord>[
        StripchatMouflonKeyRecord(
          pkey: 'Ook7quaiNgiyuhai',
          pdkey: 'EQueeGh2kaewa3ch',
          capturedAt: DateTime.utc(2026, 5, 8, 13, 0, 0),
          source: StripchatCalibrationSource.auto,
          captureSource: 'hash-cache-key',
        ),
      ],
      source: StripchatCalibrationSource.auto,
      capturedAt: DateTime.utc(2026, 5, 8, 13, 0, 0),
    );

    final merged = older.mergeRecords(
      <StripchatMouflonKeyRecord>[
        StripchatMouflonKeyRecord(
          pkey: 'Ook7quaiNgiyuhai',
          pdkey: '8iPRUU0AnxoOSif9',
          capturedAt: DateTime.utc(2026, 5, 8, 13, 5, 0),
          source: StripchatCalibrationSource.auto,
          captureSource: 'known-keys-map',
        ),
      ],
      source: StripchatCalibrationSource.auto,
      capturedAt: DateTime.utc(2026, 5, 8, 13, 5, 0),
    );

    expect(
      merged.lookup('Ook7quaiNgiyuhai')?.pdkey,
      'EQueeGh2kaewa3ch',
    );
    expect(
      merged.lookup('Ook7quaiNgiyuhai')?.captureSource,
      'hash-cache-key',
    );
  });

  test('stripchat mouflon key source priority normalizes suffixed sources', () {
    expect(
      stripchatMouflonKeySourcePriority('hash-cache-key:object'),
      stripchatMouflonKeySourcePriority('hash-cache-key'),
    );
    expect(
      stripchatMouflonKeySourcePriority('trusted-fallback:playlist'),
      stripchatMouflonKeySourcePriority('trusted-fallback'),
    );
  });

  test('stripchat mouflon key cache overlays trusted fallbacks over weak cache', () {
    final cache = const StripchatMouflonKeyCache().mergeRecords(
      <StripchatMouflonKeyRecord>[
        StripchatMouflonKeyRecord(
          pkey: 'Ook7quaiNgiyuhai',
          pdkey: '8iPRUU0AnxoOSif9',
          capturedAt: DateTime.utc(2026, 5, 9, 5, 24),
          source: StripchatCalibrationSource.auto,
          captureSource: 'known-keys-active',
        ),
      ],
      source: StripchatCalibrationSource.auto,
      capturedAt: DateTime.utc(2026, 5, 9, 5, 24),
    );

    final merged = cache.withTrustedFallbacks(
      capturedAt: DateTime.utc(2026, 5, 9, 5, 25),
    );

    expect(merged.lookup('Ook7quaiNgiyuhai')?.pdkey, 'EQueeGh2kaewa3ch');
    expect(
      merged.lookup('Ook7quaiNgiyuhai')?.captureSource,
      'trusted-fallback',
    );
  });

  test('stripchat mouflon key cache includes current gray trusted fallback', () {
    final merged = const StripchatMouflonKeyCache().withTrustedFallbacks(
      capturedAt: DateTime.utc(2026, 5, 15, 11, 30),
    );

    expect(merged.lookup('Ook7quaiNgiyuhai')?.pdkey, 'EQueeGh2kaewa3ch');
    expect(merged.lookup('Fq6m2TO2ZeBkRPm9')?.pdkey, 'xb6di1NF9EFXHUwb');
    expect(
      merged.lookup('Fq6m2TO2ZeBkRPm9')?.captureSource,
      'trusted-fallback',
    );
  });

}
