import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  static const List<String> _items = [
    '本软件为开源软件，您可以免费获取并使用。',
    '本软件完全基于个人意愿使用，您应对自己的使用行为和全部结果负责。',
    '本软件仅供学习交流、科研等非商业用途，严禁将本软件用于商业目的。',
    '本软件不保证与所有操作系统或硬件设备兼容。',
    '作者或贡献者不对因使用本软件导致的任何直接或间接损失承担责任。',
    '使用者应遵守所在地法律法规，不得利用本软件从事违法违规活动。',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('免责声明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SectionHeader(title: '免责声明'),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < _items.length; index += 1) ...[
                  Text(
                    '${index + 1}. ${_items[index]}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (index != _items.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('退出'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('已阅读并同意'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
