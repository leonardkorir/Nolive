import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';

import 'room_preview_page_follow.dart';

class RoomLoadErrorPresentation {
  const RoomLoadErrorPresentation({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

Future<bool?> confirmRoomUnfollowDialog(
  BuildContext context, {
  required String displayName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取消关注'),
      content: Text('确认取消关注“$displayName”吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('保留关注'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认取消'),
        ),
      ],
    ),
  );
}

RoomLoadErrorPresentation describeRoomLoadError(Object? error) {
  if (error case final ProviderParseException providerError
      when providerError.providerId == ProviderId.chaturbate) {
    final message = providerError.message;
    if (message.contains('Cloudflare challenge') ||
        message.contains('status 403') ||
        message.contains('status 401')) {
      return const RoomLoadErrorPresentation(
        title: 'Chaturbate 请求被拦截',
        description:
            '当前房间页请求被 Chaturbate 或 Cloudflare 拦截。请回到账号管理，优先使用 Chaturbate 的“网页登录”重新完成验证并保存 Cookie；如果仍手动粘贴，也请复制能正常打开该房间的浏览器完整 Cookie。',
      );
    }
    if (message.contains('initialRoomDossier') ||
        message.contains('push_services') ||
        message.contains('csrftoken')) {
      return const RoomLoadErrorPresentation(
        title: 'Chaturbate 房间页解析失败',
        description:
            '当前房间页没有返回预期的初始化数据，通常是页面结构变化或返回了异常页。建议先重试；如果持续出现，需要按最新页面结构调整解析器。',
      );
    }
  }
  return const RoomLoadErrorPresentation(
    title: '暂时打不开这个直播间',
    description: '请稍后重试，或者切换线路与播放器设置后再回来。',
  );
}

Widget buildRoomFollowPanel({
  required BuildContext context,
  required RoomFollowWatchlistState followState,
  required List<RoomFollowEntryViewData> entries,
  required VoidCallback onRefresh,
  required VoidCallback onOpenSettings,
  required ValueChanged<FollowWatchEntry> onOpenEntry,
}) {
  return RoomFollowPanel(
    followState: followState,
    entries: entries,
    onRefresh: onRefresh,
    onOpenSettings: onOpenSettings,
    onOpenEntry: onOpenEntry,
  );
}

Widget buildRoomFullscreenFollowDrawer({
  required BuildContext context,
  required bool showDrawer,
  required RoomFollowWatchlistState followState,
  required List<RoomFollowEntryViewData> entries,
  required VoidCallback onClose,
  required ValueChanged<FollowWatchEntry> onOpenEntry,
}) {
  return RoomFullscreenFollowDrawer(
    showDrawer: showDrawer,
    followState: followState,
    entries: entries,
    onClose: onClose,
    onOpenEntry: onOpenEntry,
  );
}
