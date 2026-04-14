import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/library/presentation/library_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('library page applies imported follow display mode', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '系统演示主播',
    );

    final payload = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1773384011720,
      'config': {
        'FollowStyleNotGrid': false,
      },
      'shield': <String, String>{},
    });

    await bootstrap.importSyncSnapshotJson(payload);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LiveRoomGridCard), findsWidgets);
  });

  testWidgets(
      'library page renders persisted follow metadata before remote refresh completes',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    const descriptor = ProviderDescriptor(
      id: ProviderId('fixture'),
      displayName: 'Fixture',
      capabilities: {ProviderCapability.roomDetail},
      supportedPlatforms: {ProviderPlatform.android},
    );
    final provider = _ControlledFixtureProvider(descriptor);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: descriptor,
        builder: () => provider,
      ),
    );

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'fixture',
        roomId: 'offline-room',
        streamerName: '离线主播',
        lastTitle: '上次标题',
        lastAreaName: '上次分区',
        lastCoverUrl: 'https://example.com/local-cover.png',
        lastKeyframeUrl: 'https://example.com/local-keyframe.png',
      ),
    );

    final payload = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1773384011720,
      'config': {
        'FollowStyleNotGrid': false,
      },
      'shield': <String, String>{},
    });
    await bootstrap.importSyncSnapshotJson(payload);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final cardFinder =
        find.byKey(const Key('library-follow-card-fixture-offline-room'));
    expect(cardFinder, findsOneWidget);

    final card = tester.widget<LiveRoomGridCard>(cardFinder);
    expect(card.room.title, '上次标题');
    expect(card.room.areaName, '上次分区');
    expect(card.room.coverUrl, 'https://example.com/local-cover.png');
    expect(card.room.keyframeUrl, 'https://example.com/local-keyframe.png');
    expect(card.room.isLive, isFalse);

    provider.complete(
      LiveRoomDetail(
        providerId: 'fixture',
        roomId: 'offline-room',
        title: '远程标题',
        streamerName: '离线主播',
        areaName: '远程分区',
        coverUrl: 'https://example.com/remote-cover.png',
        keyframeUrl: 'https://example.com/remote-keyframe.png',
        isLive: true,
      ),
    );
    await tester.pump();
  });

  testWidgets('library page keeps unknown providers renderable in grid mode',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'legacy-provider',
        roomId: 'legacy-room',
        streamerName: '旧平台主播',
        lastTitle: '旧平台房间',
      ),
    );

    final payload = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1773384011720,
      'config': {
        'FollowStyleNotGrid': false,
      },
      'shield': <String, String>{},
    });
    await bootstrap.importSyncSnapshotJson(payload);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library-follow-card-legacy-provider-legacy-room')),
      findsOneWidget,
    );
    expect(find.byType(LiveRoomGridCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'library page refreshes local follow list on follow data revision',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无关注'), findsOneWidget);

    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '系统演示主播',
      title: '系统演示直播间',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('library-follow-card-bilibili-6')),
      findsOneWidget,
    );
  });

  testWidgets('library page confirms before removing a followed room',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    const record = FollowRecord(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '系统演示主播',
      lastTitle: '系统演示直播间',
    );
    await bootstrap.followRepository.upsert(record);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: record,
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );

    final payload = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1773384011720,
      'config': {
        'FollowStyleNotGrid': true,
      },
      'shield': <String, String>{},
    });
    await bootstrap.importSyncSnapshotJson(payload);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('取消关注'));
    await tester.pumpAndSettle();

    expect(find.text('确认取消'), findsOneWidget);
    expect(await bootstrap.followRepository.listAll(), hasLength(1));

    await tester.tap(find.text('保留关注'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library-follow-card-bilibili-6')),
      findsOneWidget,
    );
    expect(await bootstrap.followRepository.listAll(), hasLength(1));

    await tester.tap(find.byTooltip('取消关注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library-follow-card-bilibili-6')),
      findsNothing,
    );
    expect(await bootstrap.followRepository.listAll(), isEmpty);
  });

  testWidgets('library page does not classify error entries as offline',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    const descriptor = ProviderDescriptor(
      id: ProviderId('failing'),
      displayName: 'Failing',
      capabilities: {ProviderCapability.roomDetail},
      supportedPlatforms: {ProviderPlatform.android},
    );
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: descriptor,
        builder: () => _FailingFixtureProvider(descriptor),
      ),
    );

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'failing',
        roomId: 'error-room',
        streamerName: '异常主播',
        lastTitle: '上次标题',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('异常'), findsOneWidget);

    await tester.tap(find.text('未开播'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library-follow-card-failing-error-room')),
      findsNothing,
    );
    expect(find.text('当前筛选下没有结果'), findsOneWidget);
  });

  testWidgets(
      'library page reuses cached snapshot and skips remote refresh after settings return',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final navigatorKey = GlobalKey<NavigatorState>();
    var detailCalls = 0;

    const record = FollowRecord(
      providerId: 'cached-follow',
      roomId: 'room-1',
      streamerName: '缓存主播',
      lastTitle: '缓存标题',
    );
    await bootstrap.followRepository.upsert(record);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kCachedFollowDescriptor,
        builder: () => _CallbackFixtureProvider(
          _kCachedFollowDescriptor,
          onRoomDetail: (roomId) async {
            detailCalls += 1;
            return LiveRoomDetail(
              providerId: _kCachedFollowProviderId.value,
              roomId: roomId,
              title: '远程标题',
              streamerName: '缓存主播',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: [
        FollowWatchEntry(
          record: record,
          detail: const LiveRoomDetail(
            providerId: 'cached-follow',
            roomId: 'room-1',
            title: '缓存标题',
            streamerName: '缓存主播',
            isLive: true,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        routes: {
          AppRoutes.followSettings: (context) =>
              const Scaffold(body: Center(child: Text('关注设置页'))),
        },
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(detailCalls, 0);
    expect(
      find.byKey(const Key('library-follow-card-cached-follow-room-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注设置').last);
    await tester.pumpAndSettle();

    expect(find.text('关注设置页'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(detailCalls, 0);
  });

  testWidgets('library page keeps filter bar fixed while content scrolls',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    for (var index = 0; index < 20; index += 1) {
      await bootstrap.followRepository.upsert(
        FollowRecord(
          providerId: 'scroll-provider',
          roomId: 'room-$index',
          streamerName: '主播$index',
          lastTitle: '标题$index',
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          dependencies: buildLibraryFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final filterBarFinder = find.byKey(const Key('library-filter-bar'));
    final beforeScroll = tester.getTopLeft(filterBarFinder).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final afterScroll = tester.getTopLeft(filterBarFinder).dy;
    expect(afterScroll, beforeScroll);
  });
}

class _ControlledFixtureProvider extends LiveProvider
    implements SupportsRoomDetail {
  _ControlledFixtureProvider(this._descriptor);

  final ProviderDescriptor _descriptor;
  final Completer<LiveRoomDetail> _completer = Completer<LiveRoomDetail>();

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) {
    return _completer.future;
  }

  void complete(LiveRoomDetail detail) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(detail);
  }
}

class _FailingFixtureProvider extends LiveProvider
    implements SupportsRoomDetail {
  _FailingFixtureProvider(this._descriptor);

  final ProviderDescriptor _descriptor;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    throw StateError('network unavailable');
  }
}

const _kCachedFollowProviderId = ProviderId('cached-follow');

const _kCachedFollowDescriptor = ProviderDescriptor(
  id: _kCachedFollowProviderId,
  displayName: 'Cached Follow',
  capabilities: {ProviderCapability.roomDetail},
  supportedPlatforms: {ProviderPlatform.android},
);

class _CallbackFixtureProvider extends LiveProvider
    implements SupportsRoomDetail {
  _CallbackFixtureProvider(this._descriptor, {required this.onRoomDetail});

  final ProviderDescriptor _descriptor;
  final Future<LiveRoomDetail> Function(String roomId) onRoomDetail;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => onRoomDetail(roomId);
}
