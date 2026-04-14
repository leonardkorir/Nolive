import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_playback_actions.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_settings_return_actions.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_utility_actions.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

export 'room_controls_action_context.dart'
    show
        RoomControlsActionContext,
        RoomPersistScreenshot,
        shouldRefreshRoomAfterPlayerSettingsReturn;

class RoomControlsActionCoordinator extends ChangeNotifier {
  RoomControlsActionCoordinator({
    required this.context,
    RoomPersistScreenshot? persistScreenshot,
  })  : _playbackActions = RoomControlsPlaybackActions(context: context),
        _settingsReturnActions =
            RoomControlsSettingsReturnActions(context: context),
        _utilityActions = RoomControlsUtilityActions(
          context: context,
          notifyChanged: _noopNotifyChanged,
          persistScreenshot: persistScreenshot,
        ) {
    _utilityActions.notifyChanged = notifyListeners;
  }

  static void _noopNotifyChanged() {}

  final RoomControlsActionContext context;
  final RoomControlsPlaybackActions _playbackActions;
  final RoomControlsSettingsReturnActions _settingsReturnActions;
  late final RoomControlsUtilityActions _utilityActions;

  DateTime? get scheduledCloseAt => _utilityActions.scheduledCloseAt;
  bool get supportsPlayerCapture => _utilityActions.supportsPlayerCapture;

  @override
  void dispose() {
    _utilityActions.dispose();
    super.dispose();
  }

  Future<void> switchQuality(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    bool resetTwitchRecoveryAttempts = true,
    LivePlayQuality? twitchStartupPromotionQuality,
  }) {
    return _playbackActions.switchQuality(
      snapshot,
      quality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
    );
  }

  Future<void> refreshPlaybackSource(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = false,
    PlaybackSource? preferredPlaybackSource,
    List<LivePlayUrl>? currentPlayUrls,
  }) {
    return _playbackActions.refreshPlaybackSource(
      snapshot,
      quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
      preferredPlaybackSource: preferredPlaybackSource,
      currentPlayUrls: currentPlayUrls,
    );
  }

  Future<void> switchLine(
    LivePlayUrl playUrl, {
    bool resetTwitchRecoveryAttempts = true,
  }) {
    return _playbackActions.switchLine(
      playUrl,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
  }

  Future<void> handlePlayerSettingsReturn({
    required PlayerPreferences previousPreferences,
  }) {
    return _settingsReturnActions.handlePlayerSettingsReturn(
      previousPreferences: previousPreferences,
    );
  }

  Future<void> handleDanmakuSettingsReturn() {
    return _settingsReturnActions.handleDanmakuSettingsReturn();
  }

  Future<void> copyRoomLink({
    required LiveRoomDetail room,
    PlaybackSource? playbackSource,
  }) {
    return _utilityActions.copyRoomLink(
      room: room,
      playbackSource: playbackSource,
    );
  }

  Future<void> shareRoomLink({
    required LiveRoomDetail room,
    PlaybackSource? playbackSource,
  }) {
    return _utilityActions.shareRoomLink(
      room: room,
      playbackSource: playbackSource,
    );
  }

  Future<void> captureScreenshot() {
    return _utilityActions.captureScreenshot();
  }

  void setAutoCloseTimer(Duration? duration) {
    _utilityActions.setAutoCloseTimer(duration);
  }
}
