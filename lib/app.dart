import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/settings/app_settings.dart';

class MarketplaceApp extends ConsumerWidget {
  const MarketplaceApp({super.key});

  ThemeData _buildTheme(AppSettings settings, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(settings.seedColorValue),
      brightness: brightness,
      contrastLevel: settings.highContrast ? 1.0 : 0.0,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F8FA)
          : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(appSettingsProvider);

    final themeMode = switch (settings.themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

    return MaterialApp.router(
      title: 'Marketplace Multiservices Burkina',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(settings, Brightness.light),
      darkTheme: _buildTheme(settings, Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Preserve the device's text accessibility factor and apply the
        // additional scale selected inside the application.
        final deviceScale = media.textScaler.scale(14) / 14;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(deviceScale * settings.textScale),
            disableAnimations: settings.reduceAnimations,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}
