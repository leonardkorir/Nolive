import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class DanmakuShieldPage extends StatefulWidget {
  const DanmakuShieldPage({required this.dependencies, super.key});

  final DanmakuShieldDependencies dependencies;

  @override
  State<DanmakuShieldPage> createState() => _DanmakuShieldPageState();
}

class _DanmakuShieldPageState extends State<DanmakuShieldPage> {
  late Future<List<String>> _future;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _future = widget.dependencies.loadBlockedKeywords();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.dependencies.loadBlockedKeywords();
    });
    await _future;
  }

  Future<void> _addKeyword() async {
    await widget.dependencies.addBlockedKeyword(_controller.text);
    _controller.clear();
    await _refresh();
  }

  Future<void> _removeKeyword(String keyword) async {
    await widget.dependencies.removeBlockedKeyword(keyword);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关键词屏蔽')),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) {
          final keywords = snapshot.data ?? const <String>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              const SectionHeader(
                title: '弹幕屏蔽规则',
                subtitle: '房间页的播放器内弹幕和聊天回放都会使用这里的规则。支持普通关键词，也支持 `re:` 开头的正则。',
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: '输入关键词，或用 re: 开头写正则',
                        suffixIcon: IconButton(
                          tooltip: '添加屏蔽规则',
                          onPressed: _addKeyword,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '示例：`广告` 会屏蔽包含“广告”的消息；`re:^抽奖.*\$` 会屏蔽以“抽奖”开头的整条弹幕。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已启用 ${keywords.length} 条规则',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (keywords.isEmpty)
                      const Text('还没有屏蔽规则。')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final keyword in keywords)
                            InputChip(
                              label: Text(keyword),
                              onDeleted: () => _removeKeyword(keyword),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
