import 'dart:async';
import 'dart:io';

import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';

import 'sync_preferences_use_case.dart';

class PushLocalSyncSnapshotUseCase {
  const PushLocalSyncSnapshotUseCase({
    required this.snapshotService,
    required this.client,
    this.loadSensitiveCredentials,
  });

  final RepositorySyncSnapshotService snapshotService;
  final LocalSyncClient client;

  /// 返回可迁移的敏感凭证（平台 Cookie、WebDAV 密码等）。
  final Future<Map<String, String>> Function()? loadSensitiveCredentials;

  Future<void> call(
    SyncPreferences preferences, {
    DiscoveredPeer? peer,
    Set<SyncDataCategory>? categories,
    bool includeSensitiveCredentials = false,
  }) async {
    final targetPeer = peer ?? await _resolvePeerFromPreferences(preferences);
    final selectedCategories = categories ?? const <SyncDataCategory>{};
    final credentials = includeSensitiveCredentials
        ? await _loadCredentials()
        : const <String, String>{};

    final isFullSync = selectedCategories.isEmpty ||
        selectedCategories.length == SyncDataCategory.values.length;

    if (isFullSync) {
      final snapshot = _mergeCredentials(
        await snapshotService.exportSnapshot(),
        credentials,
      );
      try {
        await client.pushSnapshot(peer: targetPeer, snapshot: snapshot);
        return;
      } on Object catch (error) {
        if (!_shouldFallbackToCategoryBatch(error)) {
          rethrow;
        }
        // 全量路径超时/超限时，拆成四类批量推送（用户感知的「下面分类同步能成功」）。
        final batch = <SyncDataCategory, SyncSnapshot>{};
        for (final category in SyncDataCategory.values) {
          batch[category] = _mergeCredentials(
            await snapshotService.exportCategory(category),
            category == SyncDataCategory.settings ? credentials : const {},
          );
        }
        await client.pushCategories(peer: targetPeer, snapshots: batch);
        return;
      }
    }

    if (selectedCategories.length > 1) {
      final snapshots = <SyncDataCategory, SyncSnapshot>{};
      for (final category in selectedCategories) {
        snapshots[category] = _mergeCredentials(
          await snapshotService.exportCategory(category),
          category == SyncDataCategory.settings ? credentials : const {},
        );
      }
      await client.pushCategories(peer: targetPeer, snapshots: snapshots);
      return;
    }

    for (final category in selectedCategories) {
      final partial = _mergeCredentials(
        await snapshotService.exportCategory(category),
        category == SyncDataCategory.settings ? credentials : const {},
      );
      await client.pushCategory(
        peer: targetPeer,
        category: category,
        snapshot: partial,
      );
    }
  }

  Future<Map<String, String>> _loadCredentials() async {
    final loader = loadSensitiveCredentials;
    if (loader == null) {
      return const {};
    }
    final raw = await loader();
    return {
      for (final entry in raw.entries)
        if (SensitiveSettingKeys.isTransferableCredentialKey(entry.key) &&
            entry.value.trim().isNotEmpty)
          entry.key.trim(): entry.value.trim(),
    };
  }

  SyncSnapshot _mergeCredentials(
    SyncSnapshot snapshot,
    Map<String, String> credentials,
  ) {
    if (credentials.isEmpty) {
      return snapshot;
    }
    return SyncSnapshot(
      settings: <String, Object?>{
        ...snapshot.settings,
        ...credentials,
      },
      history: snapshot.history,
      follows: snapshot.follows,
      tags: snapshot.tags,
      blockedKeywords: snapshot.blockedKeywords,
    );
  }

  bool _shouldFallbackToCategoryBatch(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    if (error is! HttpException) {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('status 413') ||
        message.contains('payload_too_large') ||
        message.contains('request entity too large');
  }

  DiscoveredPeer _peerFromPreferences(SyncPreferences preferences) {
    final peerAddress = preferences.localPeerAddress.trim();
    if (peerAddress.isEmpty) {
      throw const FormatException('请先选择或填写局域网目标设备');
    }
    if (preferences.localPeerAccessToken.trim().isEmpty) {
      throw const FormatException('请先填写局域网同步配对码（可点发现设备或扫码）');
    }
    return DiscoveredPeer(
      deviceId: 'manual-peer',
      displayName: '手动同步目标',
      address: peerAddress,
      port: preferences.localPeerPort,
      platform: 'unknown',
      accessToken: preferences.localPeerAccessToken,
      lastSeenAt: DateTime.now(),
    );
  }

  Future<DiscoveredPeer> _resolvePeerFromPreferences(
    SyncPreferences preferences,
  ) async {
    final peer = _peerFromPreferences(preferences);
    final info = await client.fetchInfo(peer: peer);
    return peer.copyWith(
      deviceId: info.deviceId,
      displayName: info.displayName,
      platform: info.platform,
      accessToken: peer.accessToken,
    );
  }
}
