import 'package:flutter/material.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/settings_preference_readers.dart';

class DanmakuPreferences {
  const DanmakuPreferences({
    required this.enabledByDefault,
    required this.nativeBatchMaskEnabled,
    required this.fontSize,
    required this.fontWeight,
    required this.area,
    required this.speed,
    required this.opacity,
    required this.strokeWidth,
    required this.lineHeight,
    required this.topMargin,
    required this.bottomMargin,
    this.frequencyWindowSeconds = 8,
    this.maxFrequency = 2,
    this.textNormalizationEnabled = true,
  });

  static const DanmakuPreferences defaults = DanmakuPreferences(
    enabledByDefault: true,
    nativeBatchMaskEnabled: true,
    fontSize: 16,
    fontWeight: 3,
    area: 0.8,
    speed: 12,
    opacity: 1,
    strokeWidth: 2,
    lineHeight: 1.25,
    topMargin: 0,
    bottomMargin: 0,
    frequencyWindowSeconds: 8,
    maxFrequency: 2,
    textNormalizationEnabled: true,
  );

  final bool enabledByDefault;
  final bool nativeBatchMaskEnabled;
  final double fontSize;
  final int fontWeight;
  final double area;
  final double speed;
  final double opacity;
  final double strokeWidth;
  final double lineHeight;
  final double topMargin;
  final double bottomMargin;
  final int frequencyWindowSeconds;
  final int maxFrequency;
  final bool textNormalizationEnabled;

  DanmakuPreferences copyWith({
    bool? enabledByDefault,
    bool? nativeBatchMaskEnabled,
    double? fontSize,
    int? fontWeight,
    double? area,
    double? speed,
    double? opacity,
    double? strokeWidth,
    double? lineHeight,
    double? topMargin,
    double? bottomMargin,
    int? frequencyWindowSeconds,
    int? maxFrequency,
    bool? textNormalizationEnabled,
  }) {
    return DanmakuPreferences(
      enabledByDefault: enabledByDefault ?? this.enabledByDefault,
      nativeBatchMaskEnabled:
          nativeBatchMaskEnabled ?? this.nativeBatchMaskEnabled,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      area: area ?? this.area,
      speed: speed ?? this.speed,
      opacity: opacity ?? this.opacity,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      lineHeight: lineHeight ?? this.lineHeight,
      topMargin: topMargin ?? this.topMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      frequencyWindowSeconds:
          frequencyWindowSeconds ?? this.frequencyWindowSeconds,
      maxFrequency: maxFrequency ?? this.maxFrequency,
      textNormalizationEnabled:
          textNormalizationEnabled ?? this.textNormalizationEnabled,
    );
  }

  FontWeight resolveFontWeight() {
    return switch (fontWeight.clamp(0, 8)) {
      0 => FontWeight.w100,
      1 => FontWeight.w200,
      2 => FontWeight.w300,
      3 => FontWeight.w400,
      4 => FontWeight.w500,
      5 => FontWeight.w600,
      6 => FontWeight.w700,
      7 => FontWeight.w800,
      _ => FontWeight.w900,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DanmakuPreferences &&
            runtimeType == other.runtimeType &&
            enabledByDefault == other.enabledByDefault &&
            nativeBatchMaskEnabled == other.nativeBatchMaskEnabled &&
            fontSize == other.fontSize &&
            fontWeight == other.fontWeight &&
            area == other.area &&
            speed == other.speed &&
            opacity == other.opacity &&
            strokeWidth == other.strokeWidth &&
            lineHeight == other.lineHeight &&
            topMargin == other.topMargin &&
            bottomMargin == other.bottomMargin &&
            frequencyWindowSeconds == other.frequencyWindowSeconds &&
            maxFrequency == other.maxFrequency &&
            textNormalizationEnabled == other.textNormalizationEnabled;
  }

  @override
  int get hashCode => Object.hash(
    enabledByDefault,
    nativeBatchMaskEnabled,
    fontSize,
    fontWeight,
    area,
    speed,
    opacity,
    strokeWidth,
    lineHeight,
    topMargin,
    bottomMargin,
    frequencyWindowSeconds,
    maxFrequency,
    textNormalizationEnabled,
  );
}

class LoadDanmakuPreferencesUseCase {
  const LoadDanmakuPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<DanmakuPreferences> call() async {
    final defaults = DanmakuPreferences.defaults;
    final s = settingsRepository;
    return DanmakuPreferences(
      enabledByDefault: await s.readBool(
        'danmaku_enabled_by_default',
        fallback: defaults.enabledByDefault,
      ),
      nativeBatchMaskEnabled: await s.readBool(
        'danmaku_native_batch_mask_enabled',
        fallback: defaults.nativeBatchMaskEnabled,
      ),
      fontSize: await s.readClampedDouble(
        'danmaku_font_size',
        min: 8,
        max: 48,
        fallback: defaults.fontSize,
      ),
      fontWeight: await s.readClampedInt(
        'danmaku_font_weight',
        min: 0,
        max: 8,
        fallback: defaults.fontWeight,
      ),
      area: await s.readClampedDouble(
        'danmaku_area',
        min: 0.1,
        max: 1.0,
        fallback: defaults.area,
      ),
      speed: await s.readClampedDouble(
        'danmaku_speed',
        min: 4,
        max: 60,
        fallback: defaults.speed,
      ),
      opacity: await s.readClampedDouble(
        'danmaku_opacity',
        min: 0.1,
        max: 1.0,
        fallback: defaults.opacity,
      ),
      strokeWidth: await s.readClampedDouble(
        'danmaku_stroke_width',
        min: 0,
        max: 4,
        fallback: defaults.strokeWidth,
      ),
      lineHeight: await s.readClampedDouble(
        'danmaku_line_height',
        min: 0.8,
        max: 2.0,
        fallback: defaults.lineHeight,
      ),
      topMargin: await s.readClampedDouble(
        'danmaku_top_margin',
        min: 0,
        max: 48,
        fallback: defaults.topMargin,
      ),
      bottomMargin: await s.readClampedDouble(
        'danmaku_bottom_margin',
        min: 0,
        max: 48,
        fallback: defaults.bottomMargin,
      ),
      frequencyWindowSeconds: await s.readClampedInt(
        'danmaku_frequency_window_seconds',
        min: 2,
        max: 60,
        fallback: defaults.frequencyWindowSeconds,
      ),
      maxFrequency: await s.readClampedInt(
        'danmaku_max_frequency',
        min: 1,
        max: 20,
        fallback: defaults.maxFrequency,
      ),
      textNormalizationEnabled: await s.readBool(
        'danmaku_text_normalization',
        fallback: defaults.textNormalizationEnabled,
      ),
    );
  }
}

class UpdateDanmakuPreferencesUseCase {
  const UpdateDanmakuPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(DanmakuPreferences preferences) async {
    await settingsRepository.writeValue(
      'danmaku_enabled_by_default',
      preferences.enabledByDefault,
    );
    await settingsRepository.writeValue(
      'danmaku_native_batch_mask_enabled',
      preferences.nativeBatchMaskEnabled,
    );
    await settingsRepository.writeValue(
      'danmaku_font_size',
      preferences.fontSize.clamp(8, 48),
    );
    await settingsRepository.writeValue(
      'danmaku_font_weight',
      preferences.fontWeight.clamp(0, 8),
    );
    await settingsRepository.writeValue(
      'danmaku_area',
      preferences.area.clamp(0.1, 1.0),
    );
    await settingsRepository.writeValue(
      'danmaku_speed',
      preferences.speed.clamp(4, 60),
    );
    await settingsRepository.writeValue(
      'danmaku_opacity',
      preferences.opacity.clamp(0.1, 1.0),
    );
    await settingsRepository.writeValue(
      'danmaku_stroke_width',
      preferences.strokeWidth.clamp(0, 4),
    );
    await settingsRepository.writeValue(
      'danmaku_line_height',
      preferences.lineHeight.clamp(0.8, 2.0),
    );
    await settingsRepository.writeValue(
      'danmaku_top_margin',
      preferences.topMargin.clamp(0, 48),
    );
    await settingsRepository.writeValue(
      'danmaku_bottom_margin',
      preferences.bottomMargin.clamp(0, 48),
    );
    await settingsRepository.writeValue(
      'danmaku_frequency_window_seconds',
      preferences.frequencyWindowSeconds.clamp(2, 60),
    );
    await settingsRepository.writeValue(
      'danmaku_max_frequency',
      preferences.maxFrequency.clamp(1, 20),
    );
    await settingsRepository.writeValue(
      'danmaku_text_normalization',
      preferences.textNormalizationEnabled,
    );
  }
}
