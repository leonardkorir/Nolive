import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';

class LoadProviderHighlightsUseCase {
  const LoadProviderHighlightsUseCase({
    required this.registry,
    required this.listAvailableProviders,
  });

  final ProviderRegistry registry;
  final ListAvailableProvidersUseCase listAvailableProviders;

  static const Map<String, List<String>> _queries = {
    'bilibili': ['架构', '聊天'],
    'chaturbate': ['kitt', 'lucy'],
    'douyu': ['架构', '王者荣耀'],
    'huya': ['架构', '王者荣耀'],
    'douyin': ['架构', '王者荣耀'],
  };

  Future<List<ProviderHighlightSection>> call() async {
    final descriptors = listAvailableProviders();
    final futures = descriptors.map(_loadForDescriptor);
    final sections = await Future.wait(futures);
    return sections
        .whereType<ProviderHighlightSection>()
        .toList(growable: false);
  }

  Future<ProviderHighlightSection?> _loadForDescriptor(
    ProviderDescriptor descriptor,
  ) async {
    try {
      final provider = registry.create(descriptor.id);
      final search = provider.requireContract<SupportsRoomSearch>(
        ProviderCapability.searchRooms,
      );
      final queries = _queries[descriptor.id.value] ?? const ['架构'];
      for (final query in [...queries, '']) {
        final response = await search.searchRooms(query);
        if (response.items.isNotEmpty) {
          return ProviderHighlightSection(
            descriptor: descriptor,
            query: query,
            rooms: response.items.take(4).toList(growable: false),
          );
        }
      }
    } catch (_) {}
    return null;
  }
}

class ProviderHighlightSection {
  const ProviderHighlightSection({
    required this.descriptor,
    required this.query,
    required this.rooms,
  });

  final ProviderDescriptor descriptor;
  final String query;
  final List<LiveRoom> rooms;
}
