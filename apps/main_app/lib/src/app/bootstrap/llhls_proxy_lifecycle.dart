import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';

class LlhlsProxyRegistry {
  LlhlsProxyRegistry({
    required this.chaturbateProxy,
    required this.stripchatProxy,
    required this.twitchProxy,
    this.releaseRuntimeWebPressure,
  });

  final ChaturbateLlHlsProxy? chaturbateProxy;
  final StripchatLlHlsProxy? stripchatProxy;
  final TwitchAdGuardProxy? twitchProxy;

  /// Optional: dispose idle Twitch/YouTube headless WebViews after leave-room.
  final Future<void> Function()? releaseRuntimeWebPressure;

  Future<void> initialize() async {
    try {
      if (chaturbateProxy != null) {
        await chaturbateProxy!.ensureStarted();
      }
    } catch (e, st) {
      debugPrint('Failed to start Chaturbate LL-HLS proxy: $e\n$st');
    }
    try {
      if (stripchatProxy != null) {
        await stripchatProxy!.ensureStarted();
      }
    } catch (e, st) {
      debugPrint('Failed to start Stripchat LL-HLS proxy: $e\n$st');
    }
    try {
      if (twitchProxy != null) {
        await twitchProxy!.ensureStarted();
      }
    } catch (e, st) {
      debugPrint('Failed to start Twitch Ad-Guard proxy: $e\n$st');
    }
  }

  void registerSession({
    required String roomId,
    required ProviderId providerId,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[LlhlsProxyRegistry] registerSession roomId=$roomId providerId=${providerId.value}',
      );
    }
  }

  void unregisterSession({required String roomId}) {
    if (kDebugMode) {
      debugPrint('[LlhlsProxyRegistry] unregisterSession roomId=$roomId');
    }
    try {
      chaturbateProxy?.unregisterSession(roomId);
    } catch (e, st) {
      debugPrint(
        'Error unregistering Chaturbate session for roomId=$roomId: $e\n$st',
      );
    }
    try {
      stripchatProxy?.unregisterSession(roomId);
    } catch (e, st) {
      debugPrint(
        'Error unregistering Stripchat session for roomId=$roomId: $e\n$st',
      );
    }
    try {
      twitchProxy?.unregisterSession(roomId);
    } catch (e, st) {
      debugPrint(
        'Error unregistering Twitch session for roomId=$roomId: $e\n$st',
      );
    }
    final release = releaseRuntimeWebPressure;
    if (release != null) {
      unawaited(
        release().catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'Error releasing runtime web pressure after leave-room: $error\n$stackTrace',
          );
        }),
      );
    }
  }
}
