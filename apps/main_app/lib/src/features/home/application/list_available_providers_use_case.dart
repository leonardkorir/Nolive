import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

class ListAvailableProvidersUseCase {
  const ListAvailableProvidersUseCase(
    this.registry,
    this.layoutPreferences, {
    this.stringSetting,
  });

  final ProviderRegistry registry;
  final ValueListenable<LayoutPreferences> layoutPreferences;
  final String Function(String key)? stringSetting;

  List<ProviderDescriptor> call() {
    final descriptors = registry.descriptors
        .where((descriptor) => !_shouldHideDescriptor(descriptor))
        .toList(growable: false);
    final preferences = layoutPreferences.value;
    descriptors.sort((left, right) {
      final leftIndex = preferences.providerSortIndex(left.id.value);
      final rightIndex = preferences.providerSortIndex(right.id.value);
      if (leftIndex != rightIndex) {
        return leftIndex.compareTo(rightIndex);
      }
      return left.displayName.compareTo(right.displayName);
    });
    return descriptors;
  }

  bool _shouldHideDescriptor(ProviderDescriptor descriptor) {
    final preferences = layoutPreferences.value;
    if (!preferences.isProviderEnabled(descriptor.id.value)) {
      return true;
    }
    if (descriptor.id != ProviderId.chaturbate) {
      return false;
    }
    if (stringSetting == null) {
      return false;
    }
    final cookie = stringSetting!.call('account_chaturbate_cookie').trim();
    return cookie.isEmpty;
  }
}
