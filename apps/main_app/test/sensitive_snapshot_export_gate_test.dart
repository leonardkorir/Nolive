import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';

void main() {
  test(
    'repository sync snapshot export excludes account cookies and webdav password',
    () async {
      final settings = InMemorySettingsRepository();
      await settings.writeValue('theme_mode', 'dark');
      await settings.writeValue(
        SensitiveSettingKeys.accountBilibiliCookie,
        'SESSDATA=secret',
      );
      await settings.writeValue(
        SensitiveSettingKeys.accountChaturbateCookie,
        'csrftoken=secret',
      );
      await settings.writeValue(
        SensitiveSettingKeys.syncWebDavPassword,
        'webdav-secret',
      );
      await settings.writeValue(
        SensitiveSettingKeys.syncLocalAccessToken,
        'local-token',
      );
      await settings.writeValue('blocked_keywords', <String>['spam']);

      final service = RepositorySyncSnapshotService(
        settingsRepository: settings,
        historyRepository: InMemoryHistoryRepository(),
        followRepository: InMemoryFollowRepository(),
        tagRepository: InMemoryTagRepository(),
        shouldIncludeSettingInSnapshot: (key) {
          return !SensitiveSettingKeys.isSnapshotExcludedKey(key);
        },
      );

      final snapshot = await service.exportSnapshot();

      expect(snapshot.settings['theme_mode'], 'dark');
      expect(snapshot.blockedKeywords, ['spam']);
      for (final key in SensitiveSettingKeys.snapshotExcludedKeys) {
        expect(
          snapshot.settings.containsKey(key),
          isFalse,
          reason: 'export must not include $key',
        );
      }
    },
  );
}
