import 'package:flutter/foundation.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/home/application/load_provider_recommend_rooms_use_case.dart';
import 'package:nolive_app/src/features/search/application/search_feature_dependencies.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

class HomeFeatureDependencies {
  const HomeFeatureDependencies({
    required this.layoutPreferences,
    required this.providerCatalogRevision,
    required this.listAvailableProviders,
    required this.loadProviderRecommendRooms,
    required this.searchDependencies,
  });

  final ValueListenable<LayoutPreferences> layoutPreferences;
  final ValueListenable<int> providerCatalogRevision;
  final ListAvailableProvidersUseCase listAvailableProviders;
  final LoadProviderRecommendRoomsUseCase loadProviderRecommendRooms;
  final SearchFeatureDependencies searchDependencies;
}
