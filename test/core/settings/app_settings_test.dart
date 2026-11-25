import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketplace_multiservices_burkina/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('les préférences sont enregistrées et rechargées', () async {
    final firstContainer = ProviderContainer();
    addTearDown(firstContainer.dispose);

    await firstContainer.read(appSettingsProvider.notifier).load();

    final firstController = firstContainer.read(appSettingsProvider.notifier);

    await firstController.setThemeMode(AppThemeMode.dark);
    await firstController.setSeedColor(0xFF1565C0);
    await firstController.setTextScale(1.2);
    await firstController.setHighContrast(true);
    await firstController.setReduceAnimations(true);

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);

    await secondContainer.read(appSettingsProvider.notifier).load();
    final restored = secondContainer.read(appSettingsProvider);

    expect(restored.themeMode, AppThemeMode.dark);
    expect(restored.seedColorValue, 0xFF1565C0);
    expect(restored.textScale, 1.2);
    expect(restored.highContrast, isTrue);
    expect(restored.reduceAnimations, isTrue);
  });

  test('la réinitialisation restaure les valeurs par défaut', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(appSettingsProvider.notifier);
    await controller.setThemeMode(AppThemeMode.dark);
    await controller.setTextScale(1.3);
    await controller.reset();

    expect(container.read(appSettingsProvider).themeMode, AppThemeMode.system);
    expect(container.read(appSettingsProvider).textScale, 1.0);
  });
}
