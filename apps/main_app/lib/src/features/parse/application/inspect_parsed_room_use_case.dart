import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

import 'parse_room_input_use_case.dart';
import '../../settings/application/manage_provider_accounts_use_case.dart';

class InspectParsedRoomUseCase {
  const InspectParsedRoomUseCase(
    this.registry, {
    this.loadProviderAccountSettings,
    this.requireChaturbateCookiePreflight = false,
    this.roomDetailOverride,
  });

  final ProviderRegistry registry;
  final LoadProviderAccountSettingsUseCase? loadProviderAccountSettings;
  final bool requireChaturbateCookiePreflight;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })? roomDetailOverride;

  Future<ParsedRoomInspection> call(ParsedRoomInput parsedRoom) async {
    await _preflightChaturbate(parsedRoom);
    final provider = registry.create(parsedRoom.providerId);
    final overridden = await roomDetailOverride?.call(
      providerId: parsedRoom.providerId,
      roomId: parsedRoom.roomId,
    );
    final detail = overridden ??
        await provider
            .requireContract<SupportsRoomDetail>(
              ProviderCapability.roomDetail,
            )
            .fetchRoomDetail(parsedRoom.roomId);
    return ParsedRoomInspection(
      parsedRoom: parsedRoom,
      detail: detail,
    );
  }

  Future<void> _preflightChaturbate(ParsedRoomInput parsedRoom) async {
    if (!requireChaturbateCookiePreflight ||
        parsedRoom.providerId != ProviderId.chaturbate ||
        loadProviderAccountSettings == null) {
      return;
    }
    final settings = await loadProviderAccountSettings!();
    if (settings.chaturbateCookie.trim().isNotEmpty) {
      return;
    }
    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message:
          'Chaturbate 这次房间检查需要浏览器 Cookie 才能通过房间页 / Cloudflare 预热。请先在账号管理粘贴可正常打开该房间的浏览器完整 Cookie，再进行房间检查。',
    );
  }
}

class ParsedRoomInspection {
  const ParsedRoomInspection({
    required this.parsedRoom,
    required this.detail,
  });

  final ParsedRoomInput parsedRoom;
  final LiveRoomDetail detail;
}
