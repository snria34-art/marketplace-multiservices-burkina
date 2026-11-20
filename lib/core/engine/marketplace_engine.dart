import 'package:supabase_flutter/supabase_flutter.dart';

import 'marketplace_resilience.dart';

/// Capabilities exposed by the marketplace runtime.
///
/// This is a client-side availability gate only. Supabase RLS and guarded RPCs
/// remain the authority for every read and mutation.
enum MarketplaceCapability {
  browseCatalog,
  discoverRestaurants,
  discoverGroupBuys,
  discoverMechanics,
  discoverServices,
  discoverTransport,
  discoverVerticals,
  discoverPromotions,
  discoverModules,
  authenticate,
  configureRestaurantCatalog,
  manageCart,
  placeOrder,
  trackDelivery,
  courierOperations,
  manageFollows,
  useMessaging,
  readNotifications,
  reserveTransport,
  requestMechanicService,
  requestProfessionalService,
  manageVerticalWorkflows,
  manageSellerCatalog,
  readSellerFinance,
  readWallet,
  requestPayout,
  administerPlatform,
}

enum CapabilityState { available, backendRequired, authenticationRequired }

class MarketplaceEngine {
  MarketplaceEngine(
    this._client, {
    MarketplaceResilience? resilience,
  }) : resilience = resilience ?? MarketplaceResilience();

  final SupabaseClient? _client;
  final MarketplaceResilience resilience;

  bool get backendConfigured => _client != null;

  /// Exposed for realtime subscriptions and repository adapters.
  SupabaseClient? get backendClient => _client;

  bool get authenticated => _client?.auth.currentUser != null;

  CapabilityState stateFor(MarketplaceCapability capability) {
    return capabilityState(
      capability,
      backendConfigured: backendConfigured,
      authenticated: authenticated,
    );
  }

  /// Returns null when the backend or signed-in session required by a
  /// capability is unavailable. It never grants backend permissions.
  SupabaseClient? clientFor(MarketplaceCapability capability) {
    return stateFor(capability) == CapabilityState.available ? _client : null;
  }

  /// Repositories may use this for a clear local precondition error; server
  /// authorization is still enforced independently by RLS/RPC.
  SupabaseClient requireClientFor(MarketplaceCapability capability) {
    switch (stateFor(capability)) {
      case CapabilityState.available:
        return _client!;
      case CapabilityState.backendRequired:
        throw StateError('Le service serveur est indisponible.');
      case CapabilityState.authenticationRequired:
        throw StateError('Une connexion est nécessaire.');
    }
  }

  /// Central bounded retry policy for idempotent reads only.
  ///
  /// Mutations, checkout, payment, refund and payout calls must not use this
  /// method: their outcome may be unknown and may not be safe to repeat.
  Future<T> read<T>(Future<T> Function() operation) => resilience.read(operation);

  /// Mutations are deliberately single-shot. Use an explicit server idempotency
  /// key inside the RPC when retrying a mutation is a product requirement.
  Future<T> mutate<T>(Future<T> Function() operation) => operation();

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

    const publicCapabilities = {
      MarketplaceCapability.discoverRestaurants,
      MarketplaceCapability.discoverGroupBuys,
      MarketplaceCapability.discoverMechanics,
      MarketplaceCapability.discoverServices,
      MarketplaceCapability.discoverTransport,
      MarketplaceCapability.discoverVerticals,
      MarketplaceCapability.discoverPromotions,
      MarketplaceCapability.discoverModules,
      MarketplaceCapability.authenticate,
    };
    if (publicCapabilities.contains(capability)) {
      return CapabilityState.available;
    }

    if (!authenticated) return CapabilityState.authenticationRequired;

    return CapabilityState.available;
  }

  SupabaseClient requireAuthenticatedClient() {
    return requireClientFor(MarketplaceCapability.manageCart);
  }
}
