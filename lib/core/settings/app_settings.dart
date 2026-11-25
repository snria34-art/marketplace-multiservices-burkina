import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seedColorValue = 0xFF2E7D32,
    this.textScale = 1.0,
    this.highContrast = false,
    this.reduceAnimations = false,
  });

  final AppThemeMode themeMode;
  final int seedColorValue;
  final double textScale;
  final bool highContrast;
  final bool reduceAnimations;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? seedColorValue,
    double? textScale,
    bool? highContrast,
    bool? reduceAnimations,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      textScale: textScale ?? this.textScale,
      highContrast: highContrast ?? this.highContrast,
      reduceAnimations: reduceAnimations ?? this.reduceAnimations,
    );
  }
}

const appThemeColors = <int>[
  0xFF2E7D32,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFEF6C00,
  0xFF00838F,
  0xFF37474F,
];

const _themeModeKey = 'app_settings.theme_mode';
const _seedColorKey = 'app_settings.seed_color';
const _textScaleKey = 'app_settings.text_scale';
const _highContrastKey = 'app_settings.high_contrast';
const _reduceAnimationsKey = 'app_settings.reduce_animations';

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedMode = preferences.getString(_themeModeKey);
      final themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => AppThemeMode.system,
      );

      state = AppSettings(
        themeMode: themeMode,
        seedColorValue: preferences.getInt(_seedColorKey) ?? 0xFF2E7D32,
        textScale: (preferences.getDouble(_textScaleKey) ?? 1.0)
            .clamp(0.9, 1.4)
            .toDouble(),
        highContrast: preferences.getBool(_highContrastKey) ?? false,
        reduceAnimations: preferences.getBool(_reduceAnimationsKey) ?? false,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Chargement des préférences impossible : $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      // Keep safe defaults. A local preference failure must not stop the app.
    }
  }

  Future<void> setThemeMode(AppThemeMode value) =>
      _persist(state.copyWith(themeMode: value));

  Future<void> setSeedColor(int value) =>
      _persist(state.copyWith(seedColorValue: value));

  Future<void> setTextScale(double value) =>
      _persist(state.copyWith(textScale: value.clamp(0.9, 1.4).toDouble()));

  Future<void> setHighContrast(bool value) =>
      _persist(state.copyWith(highContrast: value));

  Future<void> setReduceAnimations(bool value) =>
      _persist(state.copyWith(reduceAnimations: value));

  Future<void> reset() => _persist(const AppSettings());

  Future<void> _persist(AppSettings next) async {
    // Apply immediately; persistence errors are reported to the settings UI.
    state = next;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, next.themeMode.name);
    await preferences.setInt(_seedColorKey, next.seedColorValue);
    await preferences.setDouble(_textScaleKey, next.textScale);
    await preferences.setBool(_highContrastKey, next.highContrast);
    await preferences.setBool(_reduceAnimationsKey, next.reduceAnimations);
  }
}
