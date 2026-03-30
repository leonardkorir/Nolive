import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';

void main() {
  testWidgets('category page can favorite and unfavorite the selected category',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kFavoriteCategoryDescriptor,
        builder: () => _FavoriteCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          bootstrap: bootstrap,
          providerId: _kFavoriteCategoryProviderId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final favoriteButton =
        find.byKey(const Key('provider-category-favorite-button'));
    expect(favoriteButton, findsOneWidget);

    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key(
          'provider-category-favorite-chip-favorite_categories-featured',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key(
          'provider-category-favorite-chip-favorite_categories-featured',
        ),
      ),
      findsNothing,
    );
  });
}

const _kFavoriteCategoryProviderId = ProviderId('favorite_categories');

const _kFavoriteCategoryDescriptor = ProviderDescriptor(
  id: _kFavoriteCategoryProviderId,
  displayName: 'Favorite Categories',
  capabilities: {
    ProviderCapability.categories,
  },
  supportedPlatforms: {ProviderPlatform.android},
);

class _FavoriteCategoryProvider extends LiveProvider
    implements SupportsCategories, SupportsCategoryRooms {
  @override
  ProviderDescriptor get descriptor => _kFavoriteCategoryDescriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return const [
      LiveCategory(
        id: 'games',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: 'featured',
            parentId: 'games',
            name: '精选',
            pic: 'https://example.com/featured.png',
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
          providerId: 'favorite_categories',
          roomId: 'room-1',
          title: '精选房间',
          streamerName: '测试主播',
          coverUrl: 'https://example.com/cover.png',
          isLive: true,
        ),
      ],
      hasMore: false,
      page: 1,
    );
  }
}
