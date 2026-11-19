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

  /// Accepts only HTTPS project URLs, never a project reference or dashboard URL.
  static bool isValidProjectUrl(String value) {
    final candidate = value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }

    const suffix = '.supabase.co';
    final host = uri.host.toLowerCase();
    if (!host.endsWith(suffix)) return false;

    final projectRef = host.substring(0, host.length - suffix.length);
    return RegExp(r'^[a-z0-9-]{8,40}$').hasMatch(projectRef);
  }

  /// Supports modern publishable keys and legacy anon JWT keys only.
  /// Secret/service-role keys and project references are intentionally rejected.
  static bool isValidPublicKey(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidate.contains(RegExp(r'\s'))) {
      return false;
    }

    const publishablePrefix = 'sb_publishable_';
    if (candidate.startsWith(publishablePrefix)) {
      final suffix = candidate.substring(publishablePrefix.length);
      return suffix.length >= 12 &&
          RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(suffix);
    }

    final jwtParts = candidate.split('.');
    return candidate.startsWith('eyJ') &&
        jwtParts.length == 3 &&
        jwtParts.every((part) => part.isNotEmpty);
  }

  static String? get configurationIssue {
    if (url.trim().isEmpty) return 'SUPABASE_URL is missing.';
    if (!isValidProjectUrl(url)) {
      return 'SUPABASE_URL must be an HTTPS Supabase project URL.';
    }
    if (key.trim().isEmpty) {
      return 'SUPABASE_PUBLISHABLE_KEY is missing.';
    }
    if (!isValidPublicKey(key)) {
      return 'SUPABASE_PUBLISHABLE_KEY must be a publishable key or legacy anon JWT.';
    }
    return null;
  }

  static bool get isConfigured => configurationIssue == null;

  /// Initializes the backend independently from UI startup. Callers should
  /// await this in a background task so a slow backend cannot delay the shell.
  static Future<SupabaseClient?> initialize() async {
    final issue = configurationIssue;
    if (issue != null) {
      if (kDebugMode) {
        debugPrint('Configuration Supabase invalide: $issue');
      }
      return null;
    }

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
