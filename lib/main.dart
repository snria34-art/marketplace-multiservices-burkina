import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_recovery_state.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/providers/repository_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = await SupabaseConfig.initialize();

  AuthRecoveryState.attach(client);

  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(client),
      ],
      child: const MarketplaceApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (client != null) {
      PushNotificationService.instance.initialize(client);
    }
  });
}
