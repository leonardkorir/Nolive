import 'package:flutter/foundation.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';

import 'search_provider_rooms_use_case.dart';
import '../../settings/application/manage_layout_preferences_use_case.dart';

class SearchFeatureDependencies {
  const SearchFeatureDependencies({
    required this.layoutPreferences,
    required this.providerCatalogRevision,
    required this.listAvailableProviders,
    required this.searchProviderRooms,
  });

  final ValueListenable<LayoutPreferences> layoutPreferences;
  final ValueListenable<int> providerCatalogRevision;
  final ListAvailableProvidersUseCase listAvailableProviders;
  final SearchProviderRoomsUseCase searchProviderRooms;
}
