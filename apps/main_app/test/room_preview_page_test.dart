import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

void main() {
  testWidgets('room preview exposes quick actions and settings tab', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '系统演示主播',
        tags: ['常看'],
      ),
    );
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '3125893',
        streamerName: '斗鱼样例主播',
      ),
    );
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'huya',
        roomId: 'offline-demo',
        streamerName: '虎牙未开播主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
            tags: ['常看'],
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'douyu',
            roomId: '3125893',
            streamerName: '斗鱼样例主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'douyu',
            roomId: '3125893',
            title: '斗鱼样例直播间',
            streamerName: '斗鱼样例主播',
            isLive: true,
          ),
        ),
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'huya',
            roomId: 'offline-demo',
            streamerName: '虎牙未开播主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'huya',
            roomId: 'offline-demo',
            title: '虎牙未开播房间',
            streamerName: '虎牙未开播主播',
            isLive: false,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('room-appbar-more-button')), findsOneWidget);
    expect(find.byKey(const Key('room-danmaku-overlay')), findsNothing);

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
        find.byKey(const Key('room-inline-fullscreen-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('切换清晰度'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    expect(find.text('播放信息'), findsOneWidget);
    expect(
      find.byKey(const Key('room-quick-force-https-switch')),
      findsNothing,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('room-panel-tab-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('播放器中显示SC'), findsOneWidget);
    expect(find.text('关键词屏蔽'), findsOneWidget);
    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('定时关闭'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('关注列表'), findsOneWidget);
    expect(
        find.byKey(const Key('room-follow-entry-bilibili-6')), findsOneWidget);
    expect(find.byKey(const Key('room-follow-entry-douyu-3125893')),
        findsOneWidget);
    expect(find.byKey(const Key('room-follow-entry-huya-offline-demo')),
        findsNothing);
    expect(
        find.byKey(const Key('room-follow-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('room-follow-refresh-button')), findsOneWidget);
  });

  testWidgets('room preview panels can switch by horizontal swipe', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '系统演示主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
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

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    expect(find.text('播放器中显示SC'), findsOneWidget);
    expect(find.text('关键词屏蔽'), findsOneWidget);
  });

  testWidgets('room follow watchlist loads lazily after opening follow tab',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var detailCalls = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            detailCalls += 1;
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'widget_test_follow',
        roomId: 'follow-1',
        streamerName: '关注主播',
      ),
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(detailCalls, 1);

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(detailCalls, 2);
    expect(
      find.byKey(const Key('room-follow-entry-widget_test_follow-follow-1')),
      findsOneWidget,
    );
  });

  testWidgets('following current room updates follow panel snapshot',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'widget_test_follow',
        roomId: 'follow-1',
        streamerName: '关注主播',
      ),
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-follow-toggle-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('取消关注'), findsOneWidget);
    expect(
      bootstrap.followWatchlistSnapshot.value?.entries.any(
        (entry) => entry.roomId == 'current-1',
      ),
      isTrue,
    );
  });

  testWidgets('leaving room stops inline playback', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => RoomPreviewPage(
                        bootstrap: bootstrap,
                        providerId: ProviderId.bilibili,
                        roomId: '66666',
                      ),
                    ),
                  );
                },
                child: const Text('open room'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open room'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(bootstrap.player.currentState.status, PlaybackStatus.playing);

    await tester.tap(find.byKey(const Key('room-leave-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bootstrap.player.currentState.status, PlaybackStatus.ready);
  });

  testWidgets('chaturbate private show room opens with status marker',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kChaturbatePrivateShowDescriptor,
        builder: _ChaturbatePrivateShowProvider.new,
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: ProviderId.chaturbate,
          roomId: 'consuelabrasington',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('私密表演中'), findsWidgets);
    expect(find.textContaining('Private Show'), findsOneWidget);
    expect(find.textContaining('暂时没有公开播放流'), findsWidgets);
    expect(find.text('暂时打不开这个直播间'), findsNothing);
  });

  testWidgets('super chat empty state is plain text without surface card',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-panel-tab-super-chat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(AppSurfaceCard),
      findsNothing,
    );
  });
}

const _kChaturbatePrivateShowDescriptor = ProviderDescriptor(
  id: ProviderId.chaturbate,
  displayName: 'Chaturbate',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.inMigration,
);

class _ChaturbatePrivateShowProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kChaturbatePrivateShowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: roomId,
      streamerName: roomId,
      sourceUrl: 'https://chaturbate.com/$roomId/',
      isLive: false,
      metadata: const {
        'roomStatus': 'private show in progress',
      },
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [];
  }
}

const _kWidgetTestFollowProviderId = ProviderId('widget_test_follow');

const _kWidgetTestFollowDescriptor = ProviderDescriptor(
  id: _kWidgetTestFollowProviderId,
  displayName: 'Widget Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _WidgetTestFollowProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  _WidgetTestFollowProvider({required this.onRoomDetail});

  final Future<LiveRoomDetail> Function(String roomId) onRoomDetail;

  @override
  ProviderDescriptor get descriptor => _kWidgetTestFollowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => onRoomDetail(roomId);

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/live.m3u8',
      ),
    ];
  }
}
