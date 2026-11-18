import 'package:supabase_flutter/supabase_flutter.dart';

/// Central runtime coordinator for the mobile marketplace.
///
/// This class deliberately does not perform payments, refunds or payouts.
/// Those operations must be authorized and executed by trusted server code.
enum MarketplaceCapability {
  browseCatalog,
  manageCart,
  placeOrder,
  trackDelivery,
  useMessaging,
  readWallet,
  requestPayout,
  administerPlatform,
}

enum CapabilityState { available, backendRequired, authenticationRequired }

class MarketplaceEngine {
  MarketplaceEngine(this._client);

  final SupabaseClient? _client;

  bool get backendConfigured => _client != null;

  bool get authenticated => _client?.auth.currentUser != null;

  CapabilityState stateFor(MarketplaceCapability capability) {
    return capabilityState(
      capability,
      backendConfigured: backendConfigured,
      authenticated: authenticated,
    );
  }

  /// Pure policy function so access rules can be tested without a live backend.
  static CapabilityState capabilityState(
    MarketplaceCapability capability, {
    required bool backendConfigured,
    required bool authenticated,
  }) {
    if (capability == MarketplaceCapability.browseCatalog) {
      return CapabilityState.available;
    }

    if (!backendConfigured) return CapabilityState.backendRequired;

    if (!authenticated) return CapabilityState.authenticationRequired;

    return CapabilityState.available;
  }

  /// Returns the authenticated client for repository operations.
  ///
  /// Repositories and Supabase RLS/RPC remain responsible for authorization.
  SupabaseClient requireAuthenticatedClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Le service serveur est indisponible.');
    }
    if (client.auth.currentUser == null) {
      throw StateError('Une connexion est nécessaire.');
    }
    return client;
  }
}
