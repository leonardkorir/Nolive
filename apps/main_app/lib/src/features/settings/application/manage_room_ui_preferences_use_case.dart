import 'package:live_storage/live_storage.dart';

class RoomUiPreferences {
  const RoomUiPreferences({
    required this.chatTextSize,
    required this.chatTextGap,
    required this.chatBubbleStyle,
    required this.showPlayerSuperChat,
    required this.playerSuperChatDisplaySeconds,
  });

  static const RoomUiPreferences defaults = RoomUiPreferences(
    chatTextSize: 14,
    chatTextGap: 4,
    chatBubbleStyle: false,
    showPlayerSuperChat: true,
    playerSuperChatDisplaySeconds: 8,
  );

  final double chatTextSize;
  final double chatTextGap;
  final bool chatBubbleStyle;
  final bool showPlayerSuperChat;
  final int playerSuperChatDisplaySeconds;

  RoomUiPreferences copyWith({
    double? chatTextSize,
    double? chatTextGap,
    bool? chatBubbleStyle,
    bool? showPlayerSuperChat,
    int? playerSuperChatDisplaySeconds,
  }) {
    return RoomUiPreferences(
      chatTextSize: chatTextSize ?? this.chatTextSize,
      chatTextGap: chatTextGap ?? this.chatTextGap,
      chatBubbleStyle: chatBubbleStyle ?? this.chatBubbleStyle,
      showPlayerSuperChat: showPlayerSuperChat ?? this.showPlayerSuperChat,
      playerSuperChatDisplaySeconds:
          playerSuperChatDisplaySeconds ?? this.playerSuperChatDisplaySeconds,
    );
  }
}

class LoadRoomUiPreferencesUseCase {
  const LoadRoomUiPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<RoomUiPreferences> call() async {
    final defaults = RoomUiPreferences.defaults;
    return RoomUiPreferences(
      chatTextSize: _clampDouble(
        await settingsRepository.readValue<double>('room_chat_text_size'),
        min: 12,
        max: 22,
        fallback: defaults.chatTextSize,
      ),
      chatTextGap: _clampDouble(
        await settingsRepository.readValue<double>('room_chat_text_gap'),
        min: 0,
        max: 12,
        fallback: defaults.chatTextGap,
      ),
      chatBubbleStyle:
          await settingsRepository.readValue<bool>('room_chat_bubble_style') ??
              defaults.chatBubbleStyle,
      showPlayerSuperChat: await settingsRepository
              .readValue<bool>('room_show_player_super_chat') ??
          defaults.showPlayerSuperChat,
      playerSuperChatDisplaySeconds: _clampInt(
        await settingsRepository
            .readValue<int>('room_player_super_chat_display_seconds'),
        min: 3,
        max: 30,
        fallback: defaults.playerSuperChatDisplaySeconds,
      ),
    );
  }

  double _clampDouble(
    double? value, {
    required double min,
    required double max,
    required double fallback,
  }) {
    return (value ?? fallback).clamp(min, max).toDouble();
  }

  int _clampInt(
    int? value, {
    required int min,
    required int max,
    required int fallback,
  }) {
    return (value ?? fallback).clamp(min, max).toInt();
  }
}

class UpdateRoomUiPreferencesUseCase {
  const UpdateRoomUiPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(RoomUiPreferences preferences) async {
    await settingsRepository.writeValue(
      'room_chat_text_size',
      preferences.chatTextSize.clamp(12, 22),
    );
    await settingsRepository.writeValue(
      'room_chat_text_gap',
      preferences.chatTextGap.clamp(0, 12),
    );
    await settingsRepository.writeValue(
      'room_chat_bubble_style',
      preferences.chatBubbleStyle,
    );
    await settingsRepository.writeValue(
      'room_show_player_super_chat',
      preferences.showPlayerSuperChat,
    );
    await settingsRepository.writeValue(
      'room_player_super_chat_display_seconds',
      preferences.playerSuperChatDisplaySeconds.clamp(3, 30),
    );
  }
}
