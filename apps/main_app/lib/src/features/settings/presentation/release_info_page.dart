import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/settings/application/release_info_manifest.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class ReleaseInfoPage extends StatelessWidget {
  const ReleaseInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('应用信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/branding/nolive_brand_mark.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ReleaseInfoManifest.fallbackAppName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Android 首发闭环已建立，当前以发布基线、能力边界和验收口径为准。',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _ReleaseInfoFactRow(
                    label: '版本',
                    value: ReleaseInfoManifest.fallbackVersion,
                  ),
                  const _ReleaseInfoFactRow(
                    label: 'Bundle ID',
                    value: ReleaseInfoManifest.fallbackBundleId,
                  ),
                  const _ReleaseInfoFactRow(
                    label: '首发平台',
                    value: ReleaseInfoManifest.primaryPlatform,
                  ),
                  const _ReleaseInfoFactRow(
                    label: 'Flutter 基线',
                    value: ReleaseInfoManifest.flutterBaseline,
                  ),
                  const _ReleaseInfoFactRow(
                    label: 'Android minSdk',
                    value: ReleaseInfoManifest.androidMinSdk,
                  ),
                  const _ReleaseInfoFactRow(
                    label: '默认播放器',
                    value: ReleaseInfoManifest.playerDefault,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '目标产物',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ReleaseInfoManifest.targetPlatforms.join(' / '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _ReleaseInfoSection(
            title: '发布范围',
            items: ReleaseInfoManifest.releaseScope,
          ),
          const SizedBox(height: 16),
          const _ReleaseInfoSection(
            title: '当前亮点',
            items: ReleaseInfoManifest.highlights,
          ),
          const SizedBox(height: 16),
          const _ReleaseInfoSection(
            title: '发布检查',
            items: ReleaseInfoManifest.releaseChecks,
          ),
          const SizedBox(height: 16),
          const _ReleaseInfoSection(
            title: '延后平台',
            items: ReleaseInfoManifest.deferredPlatforms,
          ),
        ],
      ),
    );
  }
}

class _ReleaseInfoSection extends StatelessWidget {
  const _ReleaseInfoSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReleaseInfoFactRow extends StatelessWidget {
  const _ReleaseInfoFactRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
