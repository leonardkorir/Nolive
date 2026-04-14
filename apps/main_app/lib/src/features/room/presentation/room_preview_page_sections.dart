import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_panels.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'package:nolive_app/src/shared/presentation/widgets/streamer_avatar.dart';

@immutable
class RoomLoadingShellViewData {
  const RoomLoadingShellViewData({
    required this.providerLabel,
    required this.roomTitle,
    required this.streamerName,
    required this.avatarLabel,
    this.posterUrl,
  });

  final String providerLabel;
  final String roomTitle;
  final String streamerName;
  final String avatarLabel;
  final String? posterUrl;
}

class RoomLoadingRoomShell extends StatelessWidget {
  const RoomLoadingRoomShell({
    required this.data,
    super.key,
  });

  final RoomLoadingShellViewData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget buildTab(String label, Key key, bool selected) {
      return Expanded(
        child: RoomPanelTab(
          key: key,
          label: label,
          selected: selected,
          onTap: () {},
        ),
      );
    }

    return ColoredBox(
      color: colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black),
                  child: data.posterUrl == null
                      ? null
                      : PersistedNetworkImage(
                          imageUrl: data.posterUrl!,
                          bucket: PersistedImageBucket.roomCover,
                          fit: BoxFit.cover,
                          fallback: const SizedBox.shrink(),
                        ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x22000000),
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    key: const Key('room-loading-shell'),
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator.adaptive(),
                        const SizedBox(height: 14),
                        Text(
                          '正在进入 ${data.providerLabel} 房间',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.roomTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Text(
                      data.avatarLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.streamerName.isEmpty
                              ? '正在读取主播信息'
                              : data.streamerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.providerLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Material(
              color: colorScheme.surface,
              child: Row(
                children: [
                  buildTab('聊天', const Key('room-panel-tab-chat'), true),
                  buildTab(
                    'SC',
                    const Key('room-panel-tab-super-chat'),
                    false,
                  ),
                  buildTab('关注', const Key('room-panel-tab-follow'), false),
                  buildTab(
                    '设置',
                    const Key('room-panel-tab-settings'),
                    false,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '房间已经进入，后台继续加载播放和聊天数据',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '视频源解析中',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '弹幕与关注状态稍后补齐',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class RoomSectionsViewData {
  const RoomSectionsViewData({
    required this.providerLabel,
    required this.streamerName,
    required this.streamerAvatarUrl,
    required this.roomLive,
    required this.viewerLabel,
    required this.isFollowed,
    this.statusPresentation,
    this.qualityBadgeLabel,
  });

  final String providerLabel;
  final String streamerName;
  final String? streamerAvatarUrl;
  final bool roomLive;
  final String viewerLabel;
  final bool isFollowed;
  final RoomChaturbateStatusPresentation? statusPresentation;
  final String? qualityBadgeLabel;
}

class RoomPreviewSections extends StatelessWidget {
  const RoomPreviewSections({
    required this.data,
    required this.pageController,
    required this.selectedPanel,
    required this.onSelectPanel,
    required this.onPageChanged,
    required this.chatPanel,
    required this.superChatPanel,
    required this.followPanel,
    required this.controlsPanel,
    required this.playerSurface,
    required this.onToggleFollow,
    required this.onRefresh,
    required this.onShareRoom,
    super.key,
  });

  final RoomSectionsViewData data;
  final PageController pageController;
  final RoomPanel selectedPanel;
  final ValueChanged<RoomPanel> onSelectPanel;
  final ValueChanged<int> onPageChanged;
  final Widget chatPanel;
  final Widget superChatPanel;
  final Widget followPanel;
  final Widget controlsPanel;
  final Widget playerSurface;
  final VoidCallback onToggleFollow;
  final VoidCallback onRefresh;
  final VoidCallback onShareRoom;

  @override
  Widget build(BuildContext context) {
    final panelPager = RoomPanelPager(
      selectedPanel: selectedPanel,
      pageController: pageController,
      onSelectPanel: onSelectPanel,
      onPageChanged: onPageChanged,
      children: [
        chatPanel,
        _RoomPanelScrollPage(child: superChatPanel),
        _RoomPanelScrollPage(child: followPanel),
        _RoomPanelScrollPage(child: controlsPanel),
      ],
    );

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 680;
          if (compactHeight) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                playerSurface,
                _RoomHeader(data: data),
                SizedBox(
                  height: 348,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: panelPager,
                  ),
                ),
                _RoomBottomActions(
                  isFollowed: data.isFollowed,
                  onToggleFollow: onToggleFollow,
                  onRefresh: onRefresh,
                  onShareRoom: onShareRoom,
                ),
              ],
            );
          }

          return Column(
            children: [
              playerSurface,
              _RoomHeader(data: data),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: panelPager,
                ),
              ),
              _RoomBottomActions(
                isFollowed: data.isFollowed,
                onToggleFollow: onToggleFollow,
                onRefresh: onRefresh,
                onShareRoom: onShareRoom,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoomPanelScrollPage extends StatelessWidget {
  const _RoomPanelScrollPage({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      child: child,
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.data,
  });

  final RoomSectionsViewData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StreamerAvatar(
              size: 42,
              imageUrl: data.streamerAvatarUrl,
              fallbackText: data.streamerName,
              isLive: data.roomLive,
              outlineColor: colorScheme.outlineVariant,
              fallbackTextStyle: applyZhTextStyleOrNull(
                Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.streamerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 15.5,
                          height: 1.08,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.providerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 9.5,
                          height: 1.04,
                        ),
                  ),
                  if (data.statusPresentation != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        data.statusPresentation!.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.orange,
                      size: 15,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      data.viewerLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                    ),
                  ],
                ),
                if (data.qualityBadgeLabel?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.qualityBadgeLabel!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 9,
                          height: 1.02,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomBottomActions extends StatelessWidget {
  const _RoomBottomActions({
    required this.isFollowed,
    required this.onToggleFollow,
    required this.onRefresh,
    required this.onShareRoom,
  });

  final bool isFollowed;
  final VoidCallback onToggleFollow;
  final VoidCallback onRefresh;
  final VoidCallback onShareRoom;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 13.5,
          ),
    );
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('room-follow-toggle-button'),
                  style: buttonStyle,
                  onPressed: onToggleFollow,
                  icon: Icon(
                    isFollowed ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text(
                    isFollowed ? '取消关注' : '关注',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: buttonStyle,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    '刷新',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: buttonStyle,
                  onPressed: onShareRoom,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text(
                    '分享',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
