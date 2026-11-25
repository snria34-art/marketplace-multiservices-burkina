import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_recovery_state.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/providers/repository_providers.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Render the application shell immediately. Backend initialization must
  // never hold the first frame hostage when connectivity is slow or absent.
  final container = ProviderContainer();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MarketplaceApp(),
    ),
  );

  unawaited(container.read(appSettingsProvider.notifier).load());
  unawaited(_initializeBackend(container));
}

Future<void> _initializeBackend(ProviderContainer container) async {
  try {
    final client = await SupabaseConfig.initialize();
    if (client == null) return;

    AuthRecoveryState.attach(client);
    container.read(supabaseClientProvider.notifier).setClient(client);

    // Push setup is non-critical and must not block backend availability.
    try {
      final engine = container.read(marketplaceEngineProvider);
      await PushNotificationService.instance.initialize(engine);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Initialisation push indisponible: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  } catch (error, stackTrace) {
    // Keep the public app shell available; protected/server-backed actions
    // remain unavailable because the provider has no authenticated client.
    if (kDebugMode) {
      debugPrint('Initialisation backend indisponible: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
