import 'package:live_core/live_core.dart';

typedef ProviderRoomDetailOverride = Future<LiveRoomDetail?> Function({
  required ProviderId providerId,
  required String roomId,
});
