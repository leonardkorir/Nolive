import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/category/application/manage_favorite_category_tags_use_case.dart';

void main() {
  test('favorite category tags load empty by default', () async {
    final settingsRepository = InMemorySettingsRepository();
    final load = LoadFavoriteCategoryTagsUseCase(settingsRepository);

    expect(await load(), isEmpty);
  });

  test('favorite category tags toggle and persist in newest first order',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    final load = LoadFavoriteCategoryTagsUseCase(settingsRepository);
    final toggle = ToggleFavoriteCategoryTagUseCase(settingsRepository);

    const douyuTag = FavoriteCategoryTag(
      providerId: ProviderId.douyu,
      categoryId: 'game',
      groupName: '网游',
      label: '英雄联盟',
      imageUrl: 'https://example.com/lol.png',
    );
    const bilibiliTag = FavoriteCategoryTag(
      providerId: ProviderId.bilibili,
      categoryId: 'mobile',
      groupName: '手游',
      label: '原神',
      imageUrl: 'https://example.com/ys.png',
    );

    expect(await toggle(douyuTag), [douyuTag]);
    expect(await toggle(bilibiliTag), [bilibiliTag, douyuTag]);

    final rawPayload = await settingsRepository
        .readValue<String>('browse_favorite_categories_v1');
    expect(rawPayload, isNotNull);
    expect(await load(), [bilibiliTag, douyuTag]);

    expect(await toggle(douyuTag), [bilibiliTag]);
  });

  test('favorite category tags drop duplicated persisted entries', () async {
    final settingsRepository = InMemorySettingsRepository();
    final load = LoadFavoriteCategoryTagsUseCase(settingsRepository);

    await settingsRepository.writeValue(
      'browse_favorite_categories_v1',
      jsonEncode([
        {
          'provider_id': 'douyu',
          'category_id': 'game',
          'group_name': '网游',
          'label': '英雄联盟',
          'image_url': 'https://example.com/lol.png',
        },
        {
          'provider_id': 'douyu',
          'category_id': 'game',
          'group_name': '网游',
          'label': '英雄联盟',
          'image_url': 'https://example.com/lol-2.png',
        },
      ]),
    );

    expect(await load(), hasLength(1));
    expect((await load()).single.categoryId, 'game');
  });
}
