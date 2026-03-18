import 'package:live_core/live_core.dart';

class ProviderSmokeCase {
  const ProviderSmokeCase({
    required this.name,
    required this.provider,
    required this.query,
  });

  final String name;
  final LiveProvider provider;
  final String query;
}

class ProviderSmokeResult {
  const ProviderSmokeResult({
    required this.smokeCase,
    required this.rooms,
    this.selectedRoom,
    this.detail,
    this.qualities = const <LivePlayQuality>[],
    this.urls = const <LivePlayUrl>[],
  });

  final ProviderSmokeCase smokeCase;
  final PagedResponse<LiveRoom> rooms;
  final LiveRoom? selectedRoom;
  final LiveRoomDetail? detail;
  final List<LivePlayQuality> qualities;
  final List<LivePlayUrl> urls;
}

Future<ProviderSmokeResult> runProviderSmokeCase(
    ProviderSmokeCase smokeCase) async {
  final provider = smokeCase.provider;
  final detailApi = provider.requireContract<SupportsRoomDetail>(
    ProviderCapability.roomDetail,
  );
  final qualityApi = provider.requireContract<SupportsPlayQualities>(
    ProviderCapability.playQualities,
  );
  final urlApi = provider.requireContract<SupportsPlayUrls>(
    ProviderCapability.playUrls,
  );

  final rooms = await _loadSmokeRooms(provider, smokeCase);
  if (rooms.items.isEmpty) {
    return ProviderSmokeResult(
      smokeCase: smokeCase,
      rooms: rooms,
    );
  }

  final room = rooms.items.first;
  final detail = await detailApi.fetchRoomDetail(room.roomId);
  final qualities = await qualityApi.fetchPlayQualities(detail);
  if (qualities.isEmpty) {
    return ProviderSmokeResult(
      smokeCase: smokeCase,
      rooms: rooms,
      selectedRoom: room,
      detail: detail,
    );
  }

  final selected = qualities.firstWhere(
    (item) => item.isDefault,
    orElse: () => qualities.first,
  );
  final urls = await urlApi.fetchPlayUrls(
    detail: detail,
    quality: selected,
  );
  return ProviderSmokeResult(
    smokeCase: smokeCase,
    rooms: rooms,
    selectedRoom: room,
    detail: detail,
    qualities: qualities,
    urls: urls,
  );
}

String? validateProviderSmokeResult(ProviderSmokeResult result) {
  final smokeCase = result.smokeCase;
  if (result.rooms.items.isEmpty) {
    return '${smokeCase.name}: search returned 0 rooms for "${smokeCase.query}"';
  }
  if (result.detail == null) {
    return '${smokeCase.name}: room detail did not resolve';
  }
  if (result.qualities.isEmpty) {
    return '${smokeCase.name}: no playable qualities were returned';
  }
  if (result.urls.isEmpty) {
    return '${smokeCase.name}: no playable urls were returned';
  }
  return null;
}

Future<PagedResponse<LiveRoom>> _loadSmokeRooms(
  LiveProvider provider,
  ProviderSmokeCase smokeCase,
) async {
  final search = provider.requireContract<SupportsRoomSearch>(
    ProviderCapability.searchRooms,
  );
  final normalizedQuery = smokeCase.query.trim();
  try {
    return await search.searchRooms(normalizedQuery);
  } on ProviderParseException catch (error) {
    if (!_isKnownTransientSearchFailure(provider, error)) {
      rethrow;
    }
  }

  await Future<void>.delayed(const Duration(milliseconds: 250));
  try {
    return await search.searchRooms(normalizedQuery);
  } on ProviderParseException catch (error) {
    if (!_shouldFallbackToRecommend(provider, error)) {
      rethrow;
    }
  }

  final recommend = provider.requireContract<SupportsRecommendRooms>(
    ProviderCapability.recommendRooms,
  );
  return recommend.fetchRecommendRooms();
}

bool _isKnownTransientSearchFailure(
  LiveProvider provider,
  ProviderParseException error,
) {
  return provider.descriptor.id == ProviderId.douyu &&
      error.message.contains('kw不能为空');
}

bool _shouldFallbackToRecommend(
  LiveProvider provider,
  ProviderParseException error,
) {
  return _isKnownTransientSearchFailure(provider, error) &&
      provider.supports(ProviderCapability.recommendRooms);
}
