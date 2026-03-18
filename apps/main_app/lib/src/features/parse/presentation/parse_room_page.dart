import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/parse/application/inspect_parsed_room_use_case.dart';
import 'package:nolive_app/src/features/parse/application/parse_room_input_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class ParseRoomPage extends StatefulWidget {
  const ParseRoomPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<ParseRoomPage> createState() => _ParseRoomPageState();
}

class _ParseRoomPageState extends State<ParseRoomPage> {
  late final TextEditingController _controller;
  late final List<ProviderDescriptor> _providers;
  ProviderId _selectedProvider = ProviderId.bilibili;
  ParseRoomInputResult? _result;
  ParsedRoomInspection? _inspection;
  Object? _inspectionError;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: 'https://live.bilibili.com/66666');
    _providers = widget.bootstrap.providerRegistry.descriptors
        .toList(growable: false)
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final fallback =
        _providers.where((item) => item.id == ProviderId.bilibili).firstOrNull;
    if (fallback != null) {
      _selectedProvider = fallback.id;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final result = widget.bootstrap.parseRoomInput(
      rawInput: _controller.text,
      fallbackProvider: _selectedProvider,
    );
    setState(() {
      _result = result;
      _inspection = null;
      _inspectionError = null;
      _checking = result.isSuccess;
    });
    if (!result.isSuccess || result.parsedRoom == null) {
      return;
    }
    try {
      final inspection = await widget.bootstrap.inspectParsedRoom(
        result.parsedRoom!,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _inspection = inspection;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inspectionError = error;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('房间解析')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SectionHeader(title: '房间解析工具'),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '输入直播间链接或房间号',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText:
                        '例如 huya:yy/35184442792200 或 https://www.douyu.com/topic/KPL?rid=3125893',
                    suffixIcon: IconButton(
                      tooltip: '解析房间输入',
                      onPressed: _checking ? null : _parse,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                    ),
                  ),
                  onSubmitted: (_) => _parse(),
                ),
                const SizedBox(height: 14),
                Text(
                  '手动指定平台',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final descriptor in _providers)
                      ChoiceChip(
                        label: Text(descriptor.displayName),
                        selected: _selectedProvider == descriptor.id,
                        onSelected: (_) {
                          setState(() {
                            _selectedProvider = descriptor.id;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _checking ? null : _parse,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_outlined),
                  label: Text(_checking ? '检查中…' : '解析并检查'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_result == null)
            const EmptyStateCard(
              title: '等待输入',
              message: '输入链接或房间号后开始检查。',
              icon: Icons.link_outlined,
            )
          else if (!_result!.isSuccess)
            EmptyStateCard(
              title: '解析失败',
              message: _result!.errorMessage ?? '未知错误',
              icon: Icons.error_outline,
            )
          else if (_checking)
            const AppSurfaceCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            )
          else if (_inspectionError != null)
            EmptyStateCard(
              title: '检查失败',
              message: '$_inspectionError',
              icon: Icons.error_outline,
            )
          else if (_inspection != null)
            _ParsedRoomCard(
              inspection: _inspection!,
              onCopy: () async {
                await Clipboard.setData(
                  ClipboardData(text: _inspection!.detail.sourceUrl ?? ''),
                );
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制直播间链接')),
                );
              },
              onOpen: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.room,
                  arguments: RoomRouteArguments(
                    providerId: _inspection!.parsedRoom.providerId,
                    roomId: _inspection!.detail.roomId,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ParsedRoomCard extends StatelessWidget {
  const _ParsedRoomCard({
    required this.inspection,
    required this.onOpen,
    required this.onCopy,
  });

  final ParsedRoomInspection inspection;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final detail = inspection.detail;
    final normalizedRoomId = inspection.parsedRoom.roomId;
    final resolvedRoomId = detail.roomId;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '解析成功',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('平台'),
            subtitle: Text(inspection.parsedRoom.providerName),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('解析结果'),
            subtitle: Text(normalizedRoomId),
          ),
          if (resolvedRoomId != normalizedRoomId)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('实际房间号'),
              subtitle: Text(resolvedRoomId),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('房间标题'),
            subtitle: Text(detail.title.isEmpty ? '未获取到标题' : detail.title),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('主播'),
            subtitle: Text(
                detail.streamerName.isEmpty ? '未获取到主播信息' : detail.streamerName),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('直播状态'),
            subtitle: Text(detail.isLive ? '直播中' : '未开播 / 回放 / 无可用线路'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('原始输入'),
            subtitle: SelectableText(inspection.parsedRoom.normalizedInput),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开房间'),
              ),
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制链接'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
