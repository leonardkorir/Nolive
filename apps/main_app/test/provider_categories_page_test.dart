import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('chaturbate category page retries first room load automatically',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.chaturbate,
          displayName: 'Chaturbate',
          capabilities: {
            ProviderCapability.categories,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _FlakyChaturbateCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          dependencies: buildCategoryFeatureDependencies(bootstrap),
          providerId: ProviderId.chaturbate,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(
        const Key('provider-category-room-chaturbate-room-1'),
      ),
      findsOneWidget,
    );
    expect(find.text('分区房间加载失败'), findsNothing);
  });

  testWidgets('douyin category page keeps loading when duplicate page appears',
      (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.douyin,
          displayName: '抖音',
          capabilities: {
            ProviderCapability.categories,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _FakeDouyinCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          dependencies: buildCategoryFeatureDependencies(bootstrap),
          providerId: ProviderId.douyin,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('provider-category-room-douyin-room-1')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('provider-category-room-douyin-room-2')),
        findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('douyin category page retries first category load automatically',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.douyin,
          displayName: '抖音',
          capabilities: {
            ProviderCapability.categories,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _FlakyDouyinCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          dependencies: buildCategoryFeatureDependencies(bootstrap),
          providerId: ProviderId.douyin,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('provider-category-room-douyin-room-1')),
        findsOneWidget);
    expect(find.text('分区加载失败'), findsNothing);
  });

  testWidgets('category page follows provider resolved page after sparse page',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.douyin,
          displayName: '抖音',
          capabilities: {
            ProviderCapability.categories,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _SparseDouyinCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          dependencies: buildCategoryFeatureDependencies(bootstrap),
          providerId: ProviderId.douyin,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('provider-category-room-douyin-room-1')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('provider-category-room-douyin-room-3')),
        findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('category page sanitizes malformed utf16 category labels',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.douyu,
          displayName: '斗鱼',
          capabilities: {
            ProviderCapability.categories,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _MalformedCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          dependencies: buildCategoryFeatureDependencies(bootstrap),
          providerId: ProviderId.douyu,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('热门'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _FlakyChaturbateCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.chaturbate,
    displayName: 'Chaturbate',
    capabilities: {
      ProviderCapability.categories,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  var _fetchCount = 0;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return const [
      LiveCategory(
        id: 'genders',
        name: 'Genders',
        children: [
          LiveSubCategory(
            id: 'female',
            parentId: 'genders',
            name: 'Female',
          ),
        ],
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    _fetchCount += 1;
    if (_fetchCount == 1) {
      throw StateError('transient category failure');
    }
    return PagedResponse(
      items: const [
        LiveRoom(
          providerId: 'chaturbate',
          roomId: 'room-1',
          title: '第一页',
          streamerName: '主播一',
          coverUrl: 'https://example.com/cover-1.png',
          isLive: true,
        ),
      ],
      hasMore: false,
      page: page,
    );
  }
}

class _FakeDouyinCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.douyin,
    displayName: '抖音',
    capabilities: {
      ProviderCapability.categories,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return const [
      LiveCategory(
        id: '720,1',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: '720,1',
            parentId: '720,1',
            name: '热门',
            pic: 'https://example.com/icon.png',
          ),
        ],
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return switch (page) {
      1 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-1',
              title: '第一页',
              streamerName: '主播一',
              coverUrl: 'https://example.com/cover-1.png',
              streamerAvatarUrl: 'https://example.com/avatar-1.png',
              isLive: true,
            ),
          ],
          hasMore: true,
          page: 1,
        ),
      2 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-1',
              title: '第一页重复',
              streamerName: '主播一',
              coverUrl: 'https://example.com/cover-1.png',
              streamerAvatarUrl: 'https://example.com/avatar-1.png',
              isLive: true,
            ),
          ],
          hasMore: true,
          page: 2,
        ),
      _ => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-2',
              title: '第三页新增',
              streamerName: '主播二',
              coverUrl: 'https://example.com/cover-2.png',
              streamerAvatarUrl: 'https://example.com/avatar-2.png',
              isLive: true,
            ),
          ],
          hasMore: false,
          page: page,
        ),
    };
  }
}

class _FlakyDouyinCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.douyin,
    displayName: '抖音',
    capabilities: {
      ProviderCapability.categories,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  var _fetchCount = 0;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    _fetchCount += 1;
    if (_fetchCount == 1) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message: 'transient douyin category parse failure',
      );
    }
    return const [
      LiveCategory(
        id: '720,1',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: '720,1',
            parentId: '720,1',
            name: '热门',
            pic: 'https://example.com/icon.png',
          ),
        ],
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return PagedResponse(
      items: const [
        LiveRoom(
          providerId: 'douyin',
          roomId: 'room-1',
          title: '重试成功',
          streamerName: '主播一',
          coverUrl: 'https://example.com/cover-1.png',
          isLive: true,
        ),
      ],
      hasMore: false,
      page: page,
    );
  }
}

class _SparseDouyinCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.douyin,
    displayName: '抖音',
    capabilities: {
      ProviderCapability.categories,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return const [
      LiveCategory(
        id: '720,1',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: '720,1',
            parentId: '720,1',
            name: '热门',
            pic: 'https://example.com/icon.png',
          ),
        ],
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return switch (page) {
      1 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-1',
              title: '第一页',
              streamerName: '主播一',
              coverUrl: 'https://example.com/cover-1.png',
              streamerAvatarUrl: 'https://example.com/avatar-1.png',
              isLive: true,
            ),
          ],
          hasMore: true,
          page: 1,
        ),
      2 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-2',
              title: '跳过空页后的第三页',
              streamerName: '主播二',
              coverUrl: 'https://example.com/cover-2.png',
              streamerAvatarUrl: 'https://example.com/avatar-2.png',
              isLive: true,
            ),
          ],
          hasMore: true,
          page: 3,
        ),
      4 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'douyin',
              roomId: 'room-3',
              title: '第四页',
              streamerName: '主播三',
              coverUrl: 'https://example.com/cover-3.png',
              streamerAvatarUrl: 'https://example.com/avatar-3.png',
              isLive: true,
            ),
          ],
          hasMore: false,
          page: 4,
        ),
      _ => PagedResponse(
          items: const [],
          hasMore: false,
          page: page,
        ),
    };
  }
}

class _MalformedCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.douyu,
    displayName: '斗鱼',
    capabilities: {
      ProviderCapability.categories,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return [
      LiveCategory(
        id: 'group-1',
        name: '游${String.fromCharCode(0xD800)}戏',
        children: [
          LiveSubCategory(
            id: 'hot',
            parentId: 'group-1',
            name: '热${String.fromCharCode(0xDC00)}门',
          ),
        ],
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return const PagedResponse(
      items: [
        LiveRoom(
          providerId: 'douyu',
          roomId: 'room-1',
          title: '第一页',
          streamerName: '主播一',
          isLive: true,
        ),
      ],
      hasMore: false,
      page: 1,
    );
  }
}
