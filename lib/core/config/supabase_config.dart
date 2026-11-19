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

  /// Backend startup is isolated from UI startup: a missing or temporarily
  /// invalid backend must not crash the app shell. Server-backed actions stay
  /// unavailable until a valid client exists.
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
