import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/features/sync/application/manage_local_sync_use_case.dart';
import 'package:nolive_app/src/features/sync/application/sync_feature_dependencies.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_local_page.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_webdav_page.dart';

void main() {
  testWidgets('sync webdav page shows configure, test and upload actions', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncWebDavPage(
          dependencies: SyncFeatureDependencies.fromBootstrap(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WebDAV 同步'), findsWidgets);
    expect(
      find.byKey(const Key('sync-webdav-configure-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sync-webdav-test-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-webdav-upload-button')), findsOneWidget);
  });

  testWidgets('sync local page shows local actions', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: SyncFeatureDependencies.fromBootstrap(bootstrap),
          readLocalAddresses: () async => const ['192.168.50.1'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('局域网数据同步'), findsWidgets);
    expect(find.byKey(const Key('sync-local-toggle-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-edit-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-test-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-push-button')), findsOneWidget);
  });

  testWidgets(
    'sync local page edits target, probes peer, and pushes snapshot',
    (tester) async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      final discoveryService = _FakeLocalDiscoveryService();
      final localSyncServer = _FakeLocalSyncServer();
      final localSyncClient = _RecordingLocalSyncClient(
        infoResult: const LocalSyncPeerInfo(
          deviceId: 'peer-1',
          displayName: '客厅平板',
          platform: 'android',
        ),
      );
      addTearDown(discoveryService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SyncLocalPage(
            dependencies: _buildSyncDependencies(
              bootstrap,
              discoveryService: discoveryService,
              localSyncServer: localSyncServer,
              localSyncClient: localSyncClient,
            ),
            readLocalAddresses: () async => const ['192.168.50.1'],
            platformName: () => 'android',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync-local-edit-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sync-local-scan-pairing-button')),
        findsOneWidget,
      );
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '客厅平板');
      await tester.enterText(dialogFields.at(1), '192.168.50.2');
      await tester.enterText(dialogFields.at(2), '24444');
      await tester.enterText(
        find.byKey(const Key('sync-local-pairing-code-field')),
        'sync-token-1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('192.168.50.2:24444'), findsOneWidget);
      expect(
        discoveryService.currentPeers.any(
          (peer) =>
              peer.deviceId == 'manual-peer' &&
              peer.address == '192.168.50.2' &&
              peer.port == 24444,
        ),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('sync-local-test-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('目标在线：客厅平板'), findsOneWidget);
      expect(localSyncClient.fetchedPeers, hasLength(2));
      expect(localSyncClient.fetchedPeers.last.address, '192.168.50.2');
      expect(localSyncClient.fetchedPeers.last.port, 24444);

      await tester.tap(find.byKey(const Key('sync-local-push-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(localSyncClient.pushedSnapshots, hasLength(1));
      expect(
        localSyncClient.pushedSnapshots.single.peer.address,
        '192.168.50.2',
      );
      expect(localSyncClient.pushedSnapshots.single.peer.port, 24444);
      expect(
        localSyncClient.pushedSnapshots.single.peer.accessToken,
        'synctoken1234',
      );

      await tester.tap(find.byKey(const Key('sync-local-category-settings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(localSyncClient.pushedCategories, hasLength(1));
      expect(
        localSyncClient.pushedCategories.single.category,
        SyncDataCategory.settings,
      );
    },
  );

  testWidgets(
    'sync local page explains scanner fallback on unsupported platform',
    (tester) async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      final discoveryService = _FakeLocalDiscoveryService();
      final localSyncServer = _FakeLocalSyncServer();
      final localSyncClient = _RecordingLocalSyncClient();
      addTearDown(discoveryService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SyncLocalPage(
            dependencies: _buildSyncDependencies(
              bootstrap,
              discoveryService: discoveryService,
              localSyncServer: localSyncServer,
              localSyncClient: localSyncClient,
            ),
            readLocalAddresses: () async => const ['192.168.50.1'],
            supportsPairingScanner: () => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync-local-edit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-local-scan-pairing-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('当前平台不支持扫码，请手动输入配对码'), findsOneWidget);
    },
  );

  testWidgets('sync local page does not publish loopback self peer', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final discoveryService = _FakeLocalDiscoveryService();
    final localSyncServer = _FakeLocalSyncServer();
    final localSyncClient = _RecordingLocalSyncClient();
    addTearDown(discoveryService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: _buildSyncDependencies(
            bootstrap,
            discoveryService: discoveryService,
            localSyncServer: localSyncServer,
            localSyncClient: localSyncClient,
          ),
          readLocalAddresses: () async => const [],
          platformName: () => 'linux',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-local-toggle-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      discoveryService.currentPeers.any((peer) => peer.deviceId == 'self'),
      isFalse,
    );
    expect(find.textContaining('未检测到可分享的局域网地址'), findsOneWidget);
    expect(find.textContaining('127.0.0.1'), findsNothing);
  });

  testWidgets('sync local page removes real self peer when server stops', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final discoveryService = _FakeLocalDiscoveryService();
    final localSyncServer = _FakeLocalSyncServer();
    final localSyncClient = _RecordingLocalSyncClient();
    addTearDown(discoveryService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: _buildSyncDependencies(
            bootstrap,
            discoveryService: discoveryService,
            localSyncServer: localSyncServer,
            localSyncClient: localSyncClient,
          ),
          readLocalAddresses: () async => const ['10.0.0.8'],
          platformName: () => 'linux',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-local-toggle-button')));
    await tester.pumpAndSettle();

    expect(
      discoveryService.currentPeers.any(
        (peer) => peer.deviceId == 'nolive-device',
      ),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('sync-local-toggle-button')));
    await tester.pumpAndSettle();

    expect(
      discoveryService.currentPeers.any(
        (peer) => peer.deviceId == 'nolive-device' || peer.deviceId == 'self',
      ),
      isFalse,
    );
  });

  testWidgets('sync local page marks real self peer and does not select it', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final discoveryService = _FakeLocalDiscoveryService();
    final localSyncServer = _FakeLocalSyncServer();
    final localSyncClient = _RecordingLocalSyncClient();
    addTearDown(discoveryService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: _buildSyncDependencies(
            bootstrap,
            discoveryService: discoveryService,
            localSyncServer: localSyncServer,
            localSyncClient: localSyncClient,
          ),
          readLocalAddresses: () async => const ['10.0.0.8'],
          platformName: () => 'linux',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-local-toggle-button')));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final selfPeerSubtitle = find.text('linux · 10.0.0.8:23234');
    expect(find.text('本机'), findsOneWidget);
    await tester.tap(selfPeerSubtitle, warnIfMissed: false);
    await tester.pumpAndSettle();

    final preferences = await bootstrap.loadSyncPreferences();
    expect(preferences.localPeerAddress, isEmpty);
  });

  testWidgets('sync local page surfaces probe errors', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.updateSyncPreferences(
      const SyncPreferences(
        webDavBaseUrl: '',
        webDavRemotePath: 'nolive/snapshot.json',
        webDavUsername: '',
        webDavPassword: '',
        localDeviceName: 'nolive-device',
        localPeerAddress: '10.0.0.8',
        localPeerPort: 25555,
        localPeerAccessToken: 'sync-token',
      ),
    );
    final discoveryService = _FakeLocalDiscoveryService();
    final localSyncServer = _FakeLocalSyncServer();
    final localSyncClient = _RecordingLocalSyncClient(
      infoError: StateError('probe failed'),
      snapshotError: StateError('push failed'),
    );
    addTearDown(discoveryService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: _buildSyncDependencies(
            bootstrap,
            discoveryService: discoveryService,
            localSyncServer: localSyncServer,
            localSyncClient: localSyncClient,
          ),
          readLocalAddresses: () async => const ['192.168.50.1'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10.0.0.8:25555'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-local-test-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('probe failed'), findsOneWidget);
  });

  testWidgets('sync local page surfaces push errors', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.updateSyncPreferences(
      const SyncPreferences(
        webDavBaseUrl: '',
        webDavRemotePath: 'nolive/snapshot.json',
        webDavUsername: '',
        webDavPassword: '',
        localDeviceName: 'nolive-device',
        localPeerAddress: '10.0.0.8',
        localPeerPort: 25555,
        localPeerAccessToken: 'sync-token',
      ),
    );
    final discoveryService = _FakeLocalDiscoveryService();
    final localSyncServer = _FakeLocalSyncServer();
    final localSyncClient = _RecordingLocalSyncClient(
      snapshotError: StateError('push failed'),
    );
    addTearDown(discoveryService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          dependencies: _buildSyncDependencies(
            bootstrap,
            discoveryService: discoveryService,
            localSyncServer: localSyncServer,
            localSyncClient: localSyncClient,
          ),
          readLocalAddresses: () async => const ['192.168.50.1'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-local-push-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('push failed'), findsOneWidget);
  });

  test(
    'push local sync snapshot batches multiple selected categories',
    () async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      await bootstrap.updateThemeMode(ThemeMode.dark);
      final localSyncClient = _RecordingLocalSyncClient();
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: bootstrap.settingsRepository,
        historyRepository: bootstrap.historyRepository,
        followRepository: bootstrap.followRepository,
        tagRepository: bootstrap.tagRepository,
      );
      final useCase = PushLocalSyncSnapshotUseCase(
        snapshotService: snapshotService,
        client: localSyncClient,
      );

      await useCase(
        const SyncPreferences(
          webDavBaseUrl: '',
          webDavRemotePath: 'nolive/snapshot.json',
          webDavUsername: '',
          webDavPassword: '',
          localDeviceName: 'nolive-device',
          localPeerAddress: '192.168.50.2',
          localPeerPort: 24444,
          localPeerAccessToken: 'sync-token',
        ),
        categories: const {SyncDataCategory.settings, SyncDataCategory.history},
      );

      expect(localSyncClient.pushedCategories, isEmpty);
      expect(localSyncClient.pushedCategoryBatches, hasLength(1));
      expect(
        localSyncClient.pushedCategoryBatches.single.snapshots.keys,
        containsAll([SyncDataCategory.settings, SyncDataCategory.history]),
      );
      expect(
        localSyncClient.pushedCategoryBatches.single.peer.accessToken,
        'sync-token',
      );
    },
  );
}

SyncFeatureDependencies _buildSyncDependencies(
  AppBootstrap bootstrap, {
  required _FakeLocalDiscoveryService discoveryService,
  required _FakeLocalSyncServer localSyncServer,
  required _RecordingLocalSyncClient localSyncClient,
}) {
  final snapshotService = RepositorySyncSnapshotService(
    settingsRepository: bootstrap.settingsRepository,
    historyRepository: bootstrap.historyRepository,
    followRepository: bootstrap.followRepository,
    tagRepository: bootstrap.tagRepository,
    shouldIncludeSettingInSnapshot: (key) {
      return !SensitiveSettingKeys.isSnapshotExcludedKey(key);
    },
  );
  return SyncFeatureDependencies(
    loadSyncSnapshot: bootstrap.loadSyncSnapshot,
    loadSyncPreferences: bootstrap.loadSyncPreferences,
    updateSyncPreferences: bootstrap.updateSyncPreferences,
    verifyWebDavConnection: bootstrap.verifyWebDavConnection,
    uploadWebDavSnapshot: bootstrap.uploadWebDavSnapshot,
    restoreWebDavSnapshot: bootstrap.restoreWebDavSnapshot,
    pushLocalSyncSnapshot: PushLocalSyncSnapshotUseCase(
      snapshotService: snapshotService,
      client: localSyncClient,
    ),
    localDiscoveryService: discoveryService,
    localSyncServer: localSyncServer,
    localSyncClient: localSyncClient,
  );
}

class _FakeLocalDiscoveryService extends UdpLocalDiscoveryService {
  _FakeLocalDiscoveryService()
    : super(
        readInfo: () async => const LocalSyncPeerInfo(
          deviceId: 'self',
          displayName: 'nolive-device',
          platform: 'android',
        ),
      );

  final StreamController<List<DiscoveredPeer>> _controller =
      StreamController<List<DiscoveredPeer>>.broadcast();
  List<DiscoveredPeer> _peers = const [];

  List<DiscoveredPeer> get currentPeers => _peers;

  @override
  Stream<List<DiscoveredPeer>> watchPeers() async* {
    yield _peers;
    yield* _controller.stream;
  }

  @override
  Future<void> start() async {
    _emit();
  }

  @override
  Future<void> stop() async {
    updatePeers(const []);
  }

  @override
  void addOrReplacePeer(DiscoveredPeer peer) {
    final nextPeers = [..._peers]
      ..removeWhere((item) => item.deviceId == peer.deviceId)
      ..add(peer.copyWith(lastSeenAt: DateTime.now()));
    updatePeers(nextPeers);
  }

  @override
  void removePeer(String deviceId) {
    updatePeers(
      _peers.where((item) => item.deviceId != deviceId).toList(growable: false),
    );
  }

  void updatePeers(List<DiscoveredPeer> peers) {
    _peers = List<DiscoveredPeer>.unmodifiable(peers);
    _emit();
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_peers);
    }
  }
}

class _FakeLocalSyncServer extends HttpLocalSyncServer {
  _FakeLocalSyncServer()
    : super(
        host: '127.0.0.1',
        exportSnapshot: () async => const SyncSnapshot(),
        importSnapshot: (_) async {},
        exportCategory: (_) async => const SyncSnapshot(),
        importCategory: (_, __) async {},
        accessToken: 'self-sync-token',
      );

  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Uri get endpoint => Uri.parse('http://127.0.0.1:23234/snapshot');

  @override
  Future<void> start() async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }
}

class _RecordingLocalSyncClient extends HttpLocalSyncClient {
  _RecordingLocalSyncClient({
    this.infoResult,
    this.infoError,
    this.snapshotError,
  });

  final LocalSyncPeerInfo? infoResult;
  final Object? infoError;
  final Object? snapshotError;

  final List<DiscoveredPeer> fetchedPeers = <DiscoveredPeer>[];
  final List<_PushedSnapshotRecord> pushedSnapshots = <_PushedSnapshotRecord>[];
  final List<_PushedCategoryRecord> pushedCategories =
      <_PushedCategoryRecord>[];
  final List<_PushedCategoryBatchRecord> pushedCategoryBatches =
      <_PushedCategoryBatchRecord>[];

  @override
  Future<LocalSyncPeerInfo> fetchInfo({required DiscoveredPeer peer}) async {
    fetchedPeers.add(peer);
    if (infoError != null) {
      throw infoError!;
    }
    return infoResult ??
        const LocalSyncPeerInfo(
          deviceId: 'peer',
          displayName: 'peer',
          platform: 'android',
        );
  }

  @override
  Future<void> pushSnapshot({
    required DiscoveredPeer peer,
    required SyncSnapshot snapshot,
  }) async {
    if (snapshotError != null) {
      throw snapshotError!;
    }
    pushedSnapshots.add(_PushedSnapshotRecord(peer: peer, snapshot: snapshot));
  }

  @override
  Future<void> pushCategory({
    required DiscoveredPeer peer,
    required SyncDataCategory category,
    required SyncSnapshot snapshot,
  }) async {
    pushedCategories.add(
      _PushedCategoryRecord(peer: peer, category: category, snapshot: snapshot),
    );
  }

  @override
  Future<void> pushCategories({
    required DiscoveredPeer peer,
    required Map<SyncDataCategory, SyncSnapshot> snapshots,
  }) async {
    pushedCategoryBatches.add(
      _PushedCategoryBatchRecord(
        peer: peer,
        snapshots: Map<SyncDataCategory, SyncSnapshot>.from(snapshots),
      ),
    );
  }
}

class _PushedSnapshotRecord {
  const _PushedSnapshotRecord({required this.peer, required this.snapshot});

  final DiscoveredPeer peer;
  final SyncSnapshot snapshot;
}

class _PushedCategoryRecord {
  const _PushedCategoryRecord({
    required this.peer,
    required this.category,
    required this.snapshot,
  });

  final DiscoveredPeer peer;
  final SyncDataCategory category;
  final SyncSnapshot snapshot;
}

class _PushedCategoryBatchRecord {
  const _PushedCategoryBatchRecord({
    required this.peer,
    required this.snapshots,
  });

  final DiscoveredPeer peer;
  final Map<SyncDataCategory, SyncSnapshot> snapshots;
}
