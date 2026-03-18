import 'package:flutter/foundation.dart';
import 'package:live_storage/live_storage.dart';

enum ShellTabId { home, browse, search, library, profile }

extension ShellTabIdX on ShellTabId {
  String get value => name;

  String get label => switch (this) {
        ShellTabId.home => '首页',
        ShellTabId.browse => '发现',
        ShellTabId.search => '搜索',
        ShellTabId.library => '关注',
        ShellTabId.profile => '我的',
      };

  static ShellTabId? fromValue(String raw) {
    for (final value in ShellTabId.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }
}

class LayoutPreferences {
  const LayoutPreferences({
    required this.shellTabOrder,
    required this.providerOrder,
  });

  static const List<ShellTabId> defaultShellTabOrder = [
    ShellTabId.library,
    ShellTabId.home,
    ShellTabId.browse,
    ShellTabId.profile,
  ];

  static const List<String> defaultProviderOrder = [
    'bilibili',
    'chaturbate',
    'douyu',
    'huya',
    'douyin',
  ];

  final List<ShellTabId> shellTabOrder;
  final List<String> providerOrder;

  factory LayoutPreferences.defaults() {
    return const LayoutPreferences(
      shellTabOrder: defaultShellTabOrder,
      providerOrder: defaultProviderOrder,
    );
  }

  LayoutPreferences copyWith({
    List<ShellTabId>? shellTabOrder,
    List<String>? providerOrder,
  }) {
    return LayoutPreferences(
      shellTabOrder: shellTabOrder ?? this.shellTabOrder,
      providerOrder: providerOrder ?? this.providerOrder,
    );
  }

  int providerSortIndex(String providerId) {
    final index = providerOrder.indexOf(providerId);
    return index == -1 ? providerOrder.length : index;
  }
}

class LoadLayoutPreferencesUseCase {
  const LoadLayoutPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<LayoutPreferences> call() async {
    final shellTabOrder = await settingsRepository.readValue<List>(
      'layout_shell_tab_order',
    );
    final providerOrder = await settingsRepository.readValue<List>(
      'layout_provider_order',
    );
    return LayoutPreferences(
      shellTabOrder: normalizeShellTabOrder(shellTabOrder),
      providerOrder: normalizeProviderOrder(providerOrder),
    );
  }

  static List<ShellTabId> normalizeShellTabOrder(Iterable<Object?>? rawValues) {
    final ordered = <ShellTabId>[];
    final seen = <ShellTabId>{};
    for (final raw in rawValues ?? const <Object?>[]) {
      final decoded = ShellTabIdX.fromValue(raw?.toString().trim() ?? '');
      if (decoded == null ||
          decoded == ShellTabId.search ||
          !seen.add(decoded)) {
        continue;
      }
      ordered.add(decoded);
    }
    for (final fallback in LayoutPreferences.defaultShellTabOrder) {
      if (seen.add(fallback)) {
        ordered.add(fallback);
      }
    }
    const legacyBrokenOrder = <ShellTabId>[
      ShellTabId.library,
      ShellTabId.browse,
      ShellTabId.home,
      ShellTabId.profile,
    ];
    final matchesLegacyOrder = ordered.length == legacyBrokenOrder.length &&
        ordered.asMap().entries.every(
              (entry) => legacyBrokenOrder[entry.key] == entry.value,
            );
    if (matchesLegacyOrder) {
      return List<ShellTabId>.unmodifiable(
        LayoutPreferences.defaultShellTabOrder,
      );
    }
    return List<ShellTabId>.unmodifiable(ordered);
  }

  static List<String> normalizeProviderOrder(Iterable<Object?>? rawValues) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final raw in rawValues ?? const <Object?>[]) {
      final decoded = raw?.toString().trim() ?? '';
      if (decoded.isEmpty || !seen.add(decoded)) {
        continue;
      }
      ordered.add(decoded);
    }
    for (final fallback in LayoutPreferences.defaultProviderOrder) {
      if (seen.add(fallback)) {
        ordered.add(fallback);
      }
    }
    return List<String>.unmodifiable(ordered);
  }
}

class UpdateLayoutPreferencesUseCase {
  const UpdateLayoutPreferencesUseCase({
    required this.settingsRepository,
    required this.preferencesNotifier,
  });

  final SettingsRepository settingsRepository;
  final ValueNotifier<LayoutPreferences> preferencesNotifier;

  Future<void> call(LayoutPreferences preferences) async {
    final normalized = LayoutPreferences(
      shellTabOrder: LoadLayoutPreferencesUseCase.normalizeShellTabOrder(
        preferences.shellTabOrder.map((item) => item.value),
      ),
      providerOrder: LoadLayoutPreferencesUseCase.normalizeProviderOrder(
        preferences.providerOrder,
      ),
    );
    await settingsRepository.writeValue(
      'layout_shell_tab_order',
      normalized.shellTabOrder
          .map((item) => item.value)
          .toList(growable: false),
    );
    await settingsRepository.writeValue(
      'layout_provider_order',
      normalized.providerOrder,
    );
    preferencesNotifier.value = normalized;
  }
}

Future<void> syncLayoutPreferencesNotifierFromSettings({
  required SettingsRepository settingsRepository,
  required ValueNotifier<LayoutPreferences> preferencesNotifier,
}) async {
  preferencesNotifier.value =
      await LoadLayoutPreferencesUseCase(settingsRepository).call();
}
