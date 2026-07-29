import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class RoomSuperChatPanel extends StatelessWidget {
  const RoomSuperChatPanel({
    required this.messagesListenable,
    required this.hasDanmakuSession,
    super.key,
  });

  final ValueListenable<List<LiveMessage>> messagesListenable;
  final bool hasDanmakuSession;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LiveMessage>>(
      valueListenable: messagesListenable,
      builder: (context, superChatMessages, _) {
        final messages = superChatMessages.take(24).toList(growable: false);
        if (messages.isEmpty) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hasDanmakuSession ? '暂时还没有 SC 消息。' : '当前没有 SC 会话。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < messages.length; index += 1) ...[
              DanmakuFeedTile(
                icon: Icons.stars_outlined,
                title: messages[index].content,
                subtitle: [
                  if (messages[index].userName?.isNotEmpty ?? false)
                    messages[index].userName!,
                  if (messages[index].timestamp != null)
                    formatRoomMessageTimestamp(messages[index].timestamp!),
                ].join(' · '),
              ),
              if (index != messages.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class RoomChatPanel extends StatelessWidget {
  const RoomChatPanel({
    required this.messagesListenable,
    required this.filteredDroppedListenable,
    required this.statusListenable,
    required this.resolveAncillaryLoading,
    required this.resolveHasDanmakuSession,
    required this.resolveDanmakuUnavailableReason,
    required this.room,
    required this.scrollController,
    required this.chatTextSize,
    required this.chatTextGap,
    required this.chatBubbleStyle,
    required this.onRefreshRoom,
    super.key,
  });

  final ValueListenable<List<LiveMessage>> messagesListenable;

  /// How many messages the user's blocked keywords have hidden this session.
  final ValueListenable<int> filteredDroppedListenable;
  final Listenable statusListenable;
  final bool Function() resolveAncillaryLoading;
  final bool Function() resolveHasDanmakuSession;

  /// Why chat can never arrive, or null for a real connection. A placeholder
  /// session must not be shown as established.
  final String? Function() resolveDanmakuUnavailableReason;
  final LiveRoomDetail room;
  final ScrollController scrollController;
  final double chatTextSize;
  final double chatTextGap;
  final bool chatBubbleStyle;
  final VoidCallback onRefreshRoom;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        messagesListenable,
        filteredDroppedListenable,
        statusListenable,
      ]),
      builder: (context, _) {
        final messages = messagesListenable.value;
        final filteredDropped = filteredDroppedListenable.value;
        final ancillaryLoading = resolveAncillaryLoading();
        final hasDanmakuSession = resolveHasDanmakuSession();
        final unavailableReason = resolveDanmakuUnavailableReason();
        // A placeholder session exists but will never deliver a message, so it
        // must not be presented as an established connection.
        final danmakuConnected = hasDanmakuSession && unavailableReason == null;
        final showLoadingState = ancillaryLoading && !hasDanmakuSession;
        final theme = Theme.of(context);
        final statusPresentation = resolveRoomChaturbateStatusPresentation(
          room,
        );
        if (!hasDanmakuSession || messages.isEmpty) {
          if (statusPresentation != null) {
            return AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusPresentation.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: chatTextGap + 6),
                  Text(
                    statusPresentation.description,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  SizedBox(height: chatTextGap + 6),
                  FilledButton.tonalIcon(
                    onPressed: onRefreshRoom,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新房间状态'),
                  ),
                ],
              ),
            );
          }
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showLoadingState
                          ? '房间页已进入，正在补齐聊天数据'
                          : unavailableReason != null
                          ? '当前房间无法接收弹幕'
                          : filteredDropped > 0
                          ? '消息已全部被屏蔽词过滤'
                          : '当前还没有聊天消息',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: chatTextSize,
                        height: 1.28,
                      ),
                    ),
                    SizedBox(height: chatTextGap + 6),
                    Text(
                      showLoadingState
                          ? '正在连接弹幕服务器'
                          : unavailableReason ??
                                (filteredDropped > 0
                                    ? '本次已隐藏 $filteredDropped 条，弹幕连接正常'
                                    : danmakuConnected
                                    ? '弹幕连接已建立，等待新消息'
                                    : '可以稍后手动刷新房间状态'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: chatTextSize,
                        height: 1.28,
                      ),
                    ),
                    SizedBox(height: chatTextGap + 6),
                    Text(
                      showLoadingState
                          ? '视频和关注状态会继续在后台加载'
                          : filteredDropped > 0
                          ? '可在「设置 → 弹幕」调整屏蔽关键词'
                          : danmakuConnected
                          ? '新消息到达后会在这里继续滚动'
                          : '弹幕建立后会在这里继续滚动',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: chatTextSize,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final visibleMessages =
            messages
                .skip(math.max(0, messages.length - 36))
                .toList(growable: true)
              ..sort((left, right) {
                final leftTime =
                    left.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                final rightTime =
                    right.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                return leftTime.compareTo(rightTime);
              });
        // Messages are showing, but a wide keyword rule can still be swallowing
        // most of the room. Say so, quietly, instead of letting a thin chat
        // look like a weak stream.
        final hiddenNotice = filteredDropped > 0
            ? Padding(
                padding: EdgeInsets.only(bottom: chatTextGap),
                child: Text(
                  '已按屏蔽词隐藏 $filteredDropped 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : null;
        final chatList = ListView.separated(
          controller: scrollController,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: visibleMessages.length,
          separatorBuilder: (_, __) => SizedBox(height: chatTextGap),
          itemBuilder: (context, index) {
            return RoomChatMessageTile(
              message: visibleMessages[index],
              fontSize: chatTextSize,
              gap: 0,
              bubbleStyle: chatBubbleStyle,
            );
          },
        );
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: double.infinity,
            child: hiddenNotice == null
                ? chatList
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      hiddenNotice,
                      Expanded(child: chatList),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
