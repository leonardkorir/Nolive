import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('stripchat registration stays aligned with declared capabilities', () async {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();
    final provider = registry.create(ProviderId.stripchat);
    final descriptor = provider.descriptor;

    expect(descriptor.validate(), isEmpty);

    // SupportsCategories
    final categoriesContract = provider.requireContract<SupportsCategories>(
      ProviderCapability.categories,
    );
    expect(categoriesContract, isA<SupportsCategories>());
    final categories = await categoriesContract.fetchCategories();
    expect(categories, isNotEmpty);
    final category = categories.first;

    // SupportsCategoryRooms
    final categoryRoomsContract = provider.requireContract<SupportsCategoryRooms>(
      ProviderCapability.categories,
    );
    expect(categoryRoomsContract, isA<SupportsCategoryRooms>());
    final subCategory = category.children.first;
    final categoryRooms = await categoryRoomsContract.fetchCategoryRooms(subCategory);
    expect(categoryRooms.items, isNotEmpty);

    // SupportsRecommendRooms
    final recommendRoomsContract = provider.requireContract<SupportsRecommendRooms>(
      ProviderCapability.recommendRooms,
    );
    expect(recommendRoomsContract, isA<SupportsRecommendRooms>());
    final recommendRooms = await recommendRoomsContract.fetchRecommendRooms();
    expect(recommendRooms.items, isNotEmpty);

    // SupportsRoomSearch
    final roomSearchContract = provider.requireContract<SupportsRoomSearch>(
      ProviderCapability.searchRooms,
    );
    expect(roomSearchContract, isA<SupportsRoomSearch>());
    final searchResults = await roomSearchContract.searchRooms('alice');
    expect(searchResults.items, isNotEmpty);

    // SupportsRoomDetail
    final roomDetailContract = provider.requireContract<SupportsRoomDetail>(
      ProviderCapability.roomDetail,
    );
    expect(roomDetailContract, isA<SupportsRoomDetail>());
    final detail = await roomDetailContract.fetchRoomDetail('alice_demo');
    expect(detail.roomId, equals('alice_demo'));

    // SupportsPlayQualities
    final playQualitiesContract = provider.requireContract<SupportsPlayQualities>(
      ProviderCapability.playQualities,
    );
    expect(playQualitiesContract, isA<SupportsPlayQualities>());
    final qualities = await playQualitiesContract.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    final quality = qualities.first;

    // SupportsPlayUrls
    final playUrlsContract = provider.requireContract<SupportsPlayUrls>(
      ProviderCapability.playUrls,
    );
    expect(playUrlsContract, isA<SupportsPlayUrls>());
    final playUrls = await playUrlsContract.fetchPlayUrls(detail: detail, quality: quality);
    expect(playUrls, isNotEmpty);

    // SupportsDanmaku
    final danmakuContract = provider.requireContract<SupportsDanmaku>(
      ProviderCapability.danmaku,
    );
    expect(danmakuContract, isA<SupportsDanmaku>());
    final danmakuSession = await danmakuContract.createDanmakuSession(detail);
    expect(danmakuSession, isA<DanmakuSession>());
    await danmakuSession.disconnect();
  });

  test('ProviderId.knownValues contains stripchat', () {
    expect(
      ProviderId.knownValues,
      contains(ProviderId.stripchat),
    );
  });
}

