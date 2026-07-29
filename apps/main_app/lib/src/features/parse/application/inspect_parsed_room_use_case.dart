import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

import 'parse_room_input_use_case.dart';

class InspectParsedRoomUseCase {
  const InspectParsedRoomUseCase(this.registry, {this.roomDetailOverride});

  final ProviderRegistry registry;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })?
  roomDetailOverride;

  Future<ParsedRoomInspection> call(ParsedRoomInput parsedRoom) async {
    return registry.use(parsedRoom.providerId, (provider) async {
      final overridden = await roomDetailOverride?.call(
        providerId: parsedRoom.providerId,
        roomId: parsedRoom.roomId,
      );
      final detail =
          overridden ??
          await provider
              .requireContract<SupportsRoomDetail>(
                ProviderCapability.roomDetail,
              )
              .fetchRoomDetail(parsedRoom.roomId);
      return ParsedRoomInspection(parsedRoom: parsedRoom, detail: detail);
    });
  }
}

class ParsedRoomInspection {
  const ParsedRoomInspection({required this.parsedRoom, required this.detail});

  final ParsedRoomInput parsedRoom;
  final LiveRoomDetail detail;
}
