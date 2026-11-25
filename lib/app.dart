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
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
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
