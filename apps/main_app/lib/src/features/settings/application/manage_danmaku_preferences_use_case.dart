import 'package:flutter/material.dart';
import 'package:live_storage/live_storage.dart';

class DanmakuPreferences {
  const DanmakuPreferences({
    required this.enabledByDefault,
    required this.fontSize,
    required this.fontWeight,
    required this.area,
    required this.speed,
    required this.opacity,
    required this.strokeWidth,
    required this.lineHeight,
    required this.topMargin,
    required this.bottomMargin,
  });

  static const DanmakuPreferences defaults = DanmakuPreferences(
    enabledByDefault: true,
    fontSize: 16,
    fontWeight: 3,
    area: 0.8,
    speed: 18,
    opacity: 1,
    strokeWidth: 2,
    lineHeight: 1.25,
    topMargin: 0,
    bottomMargin: 0,
  );

  final bool enabledByDefault;
  final double fontSize;
  final int fontWeight;
  final double area;
  final double speed;
  final double opacity;
  final double strokeWidth;
  final double lineHeight;
  final double topMargin;
  final double bottomMargin;

  DanmakuPreferences copyWith({
    bool? enabledByDefault,
    double? fontSize,
    int? fontWeight,
    double? area,
    double? speed,
    double? opacity,
    double? strokeWidth,
    double? lineHeight,
    double? topMargin,
    double? bottomMargin,
  }) {
    return DanmakuPreferences(
      enabledByDefault: enabledByDefault ?? this.enabledByDefault,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      area: area ?? this.area,
      speed: speed ?? this.speed,
      opacity: opacity ?? this.opacity,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      lineHeight: lineHeight ?? this.lineHeight,
      topMargin: topMargin ?? this.topMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
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
            fontSize == other.fontSize &&
            fontWeight == other.fontWeight &&
            area == other.area &&
            speed == other.speed &&
            opacity == other.opacity &&
            strokeWidth == other.strokeWidth &&
            lineHeight == other.lineHeight &&
            topMargin == other.topMargin &&
            bottomMargin == other.bottomMargin;
  }

  @override
  int get hashCode => Object.hash(
        enabledByDefault,
        fontSize,
        fontWeight,
        area,
        speed,
        opacity,
        strokeWidth,
        lineHeight,
        topMargin,
        bottomMargin,
      );
}

class LoadDanmakuPreferencesUseCase {
  const LoadDanmakuPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<DanmakuPreferences> call() async {
    final defaults = DanmakuPreferences.defaults;
    return DanmakuPreferences(
      enabledByDefault: await settingsRepository
              .readValue<bool>('danmaku_enabled_by_default') ??
          defaults.enabledByDefault,
      fontSize: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_font_size'),
        min: 8,
        max: 48,
        fallback: defaults.fontSize,
      ),
      fontWeight: _clampInt(
        await settingsRepository.readValue<int>('danmaku_font_weight'),
        min: 0,
        max: 8,
        fallback: defaults.fontWeight,
      ),
      area: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_area'),
        min: 0.1,
        max: 1.0,
        fallback: defaults.area,
      ),
      speed: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_speed'),
        min: 4,
        max: 60,
        fallback: defaults.speed,
      ),
      opacity: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_opacity'),
        min: 0.1,
        max: 1.0,
        fallback: defaults.opacity,
      ),
      strokeWidth: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_stroke_width'),
        min: 0,
        max: 4,
        fallback: defaults.strokeWidth,
      ),
      lineHeight: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_line_height'),
        min: 0.8,
        max: 2.0,
        fallback: defaults.lineHeight,
      ),
      topMargin: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_top_margin'),
        min: 0,
        max: 48,
        fallback: defaults.topMargin,
      ),
      bottomMargin: _clampDouble(
        await settingsRepository.readValue<double>('danmaku_bottom_margin'),
        min: 0,
        max: 48,
        fallback: defaults.bottomMargin,
      ),
    );
  }

  double _clampDouble(
    double? value, {
    required double min,
    required double max,
    required double fallback,
  }) {
    return (value ?? fallback).clamp(min, max).toDouble();
  }

  int _clampInt(
    int? value, {
    required int min,
    required int max,
    required int fallback,
  }) {
    return (value ?? fallback).clamp(min, max);
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
  }
}
