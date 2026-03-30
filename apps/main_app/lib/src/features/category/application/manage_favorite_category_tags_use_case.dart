import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';

const _favoriteCategoryTagsStorageKey = 'browse_favorite_categories_v1';

@immutable
class FavoriteCategoryTag {
  const FavoriteCategoryTag({
    required this.providerId,
    required this.categoryId,
    required this.groupName,
    required this.label,
    this.imageUrl,
  });

  final ProviderId providerId;
  final String categoryId;
  final String groupName;
  final String label;
  final String? imageUrl;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FavoriteCategoryTag &&
        other.providerId == providerId &&
        other.categoryId == categoryId &&
        other.groupName == groupName &&
        other.label == label &&
        other.imageUrl == imageUrl;
  }

  @override
  int get hashCode => Object.hash(
        providerId,
        categoryId,
        groupName,
        label,
        imageUrl,
      );

  bool matches({
    required ProviderId providerId,
    required String categoryId,
  }) {
    return this.providerId == providerId && this.categoryId == categoryId;
  }

  Map<String, Object?> toJson() {
    return {
      'provider_id': providerId.value,
      'category_id': categoryId,
      'group_name': groupName,
      'label': label,
      'image_url': imageUrl,
    };
  }

  factory FavoriteCategoryTag.fromJson(Map<String, Object?> json) {
    return FavoriteCategoryTag(
      providerId: ProviderId(json['provider_id']?.toString() ?? ''),
      categoryId: json['category_id']?.toString().trim() ?? '',
      groupName: json['group_name']?.toString().trim() ?? '',
      label: json['label']?.toString().trim() ?? '',
      imageUrl: _normalizeOptionalString(json['image_url']),
    );
  }
}

class LoadFavoriteCategoryTagsUseCase {
  const LoadFavoriteCategoryTagsUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<List<FavoriteCategoryTag>> call() async {
    final rawPayload = await settingsRepository
        .readValue<String>(_favoriteCategoryTagsStorageKey);
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return const <FavoriteCategoryTag>[];
    }
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! List) {
        return const <FavoriteCategoryTag>[];
      }
      final items = <FavoriteCategoryTag>[];
      final seen = <String>{};
      for (final raw in decoded.whereType<Map>()) {
        final item = FavoriteCategoryTag.fromJson(
          raw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        if (item.providerId.value.isEmpty ||
            item.categoryId.isEmpty ||
            item.label.isEmpty) {
          continue;
        }
        final dedupeKey = '${item.providerId.value}:${item.categoryId}';
        if (!seen.add(dedupeKey)) {
          continue;
        }
        items.add(item);
      }
      return List<FavoriteCategoryTag>.unmodifiable(items);
    } on FormatException {
      return const <FavoriteCategoryTag>[];
    }
  }
}

class ToggleFavoriteCategoryTagUseCase {
  const ToggleFavoriteCategoryTagUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<List<FavoriteCategoryTag>> call(FavoriteCategoryTag tag) async {
    final current = List<FavoriteCategoryTag>.from(
      await LoadFavoriteCategoryTagsUseCase(settingsRepository).call(),
    );
    final existingIndex = current.indexWhere(
      (item) => item.matches(
        providerId: tag.providerId,
        categoryId: tag.categoryId,
      ),
    );
    if (existingIndex >= 0) {
      current.removeAt(existingIndex);
    } else {
      current.insert(0, tag);
    }
    final payload = jsonEncode([
      for (final item in current) item.toJson(),
    ]);
    await settingsRepository.writeValue(
        _favoriteCategoryTagsStorageKey, payload);
    return List<FavoriteCategoryTag>.unmodifiable(current);
  }
}

String? _normalizeOptionalString(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}
