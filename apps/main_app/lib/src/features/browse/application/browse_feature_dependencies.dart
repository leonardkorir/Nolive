import 'package:flutter/foundation.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/category/application/manage_favorite_category_tags_use_case.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/search/application/search_feature_dependencies.dart';

import 'load_provider_highlights_use_case.dart';
import '../../settings/application/manage_layout_preferences_use_case.dart';

class BrowseFeatureDependencies {
  const BrowseFeatureDependencies({
    required this.layoutPreferences,
    required this.providerCatalogRevision,
    required this.listAvailableProviders,
    required this.loadProviderHighlights,
    required this.loadProviderCategories,
    required this.loadFavoriteCategoryTags,
    required this.searchDependencies,
  });

  final ValueListenable<LayoutPreferences> layoutPreferences;
  final ValueListenable<int> providerCatalogRevision;
  final ListAvailableProvidersUseCase listAvailableProviders;
  final LoadProviderHighlightsUseCase loadProviderHighlights;
  final LoadProviderCategoriesUseCase loadProviderCategories;
  final LoadFavoriteCategoryTagsUseCase loadFavoriteCategoryTags;
  final SearchFeatureDependencies searchDependencies;
}
