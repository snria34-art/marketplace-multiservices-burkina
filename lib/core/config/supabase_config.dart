import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get key {
    if (publishableKey.isNotEmpty) return publishableKey;
    return legacyAnonKey;
  }

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;

  /// Initializes the backend independently from UI startup. Callers should
  /// await this in a background task so a slow backend cannot delay the shell.
  static Future<SupabaseClient?> initialize() async {
    if (!isConfigured) return null;

    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        debug: false,
      );
      return Supabase.instance.client;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Supabase indisponible au démarrage: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }
}
