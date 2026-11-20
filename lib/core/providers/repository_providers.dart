import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engine/marketplace_engine.dart';
import '../engine/marketplace_resilience.dart';
import '../../features/cart/data/cart_repository.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/checkout/data/checkout_repository.dart';
import '../../features/courier/data/courier_repository.dart';
import '../../features/delivery/data/delivery_repository.dart';
import '../../features/follows/data/follows_repository.dart';
import '../../features/group_buy/data/group_buy_repository.dart';
import '../../features/mechanics/data/mechanic_repository.dart';
import '../../features/messaging/data/messaging_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/restaurants/data/restaurant_repository.dart';
import '../../features/seller/data/seller_repository.dart';
import '../../features/seller/data/seller_products_repository.dart';
import '../../features/services/data/service_repository.dart';
import '../../features/transport/data/transport_repository.dart';
import '../../features/verticals/data/vertical_repository.dart';

/// Holds the backend client independently from the Flutter shell lifecycle.
/// The app can render immediately and receive the client when initialization
/// finishes, without requiring a restart.
final supabaseClientProvider =
    NotifierProvider<SupabaseClientNotifier, SupabaseClient?>(
  SupabaseClientNotifier.new,
);

/// Stable read provider retained for existing tests and provider overrides.
final supabaseProvider = Provider<SupabaseClient?>(
  (ref) => ref.watch(supabaseClientProvider),
);

class SupabaseClientNotifier extends Notifier<SupabaseClient?> {
  @override
  SupabaseClient? build() => null;

  void setClient(SupabaseClient? client) {
    state = client;
  }
}

/// Rebuilds capability-aware providers whenever Supabase authentication
/// changes, so a sign-in/sign-out does not leave stale access decisions.
final marketplaceAuthChangesProvider = StreamProvider<dynamic>((ref) {
  final client = ref.watch(supabaseProvider);
  return client?.auth.onAuthStateChange ?? const Stream<dynamic>.empty();
});

final marketplaceResilienceProvider = Provider<MarketplaceResilience>((ref) {
  return MarketplaceResilience();
});

/// Single runtime gateway. All feature repository providers below obtain their
/// client from this engine, not directly from the Supabase bootstrap provider.
final marketplaceEngineProvider = Provider<MarketplaceEngine>((ref) {
  final client = ref.watch(supabaseProvider);
  ref.watch(marketplaceAuthChangesProvider);
  return MarketplaceEngine(
    client,
    resilience: ref.watch(marketplaceResilienceProvider),
  );
});

/// Capability-scoped clients for screens that still need direct realtime,
/// storage, or feature-specific calls. These are convenience gates only;
/// database RLS and guarded RPCs remain authoritative.
final marketplacePublicClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.discoverPromotions);
});

final marketplaceAuthenticationClientProvider =
    Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.authenticate);
});

final marketplaceCustomerClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.manageCart);
});

final marketplaceSellerClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.manageSellerCatalog);
});

final marketplaceAdminClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.administerPlatform);
});

final marketplaceCourierClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.courierOperations);
});

final marketplaceNotificationClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(marketplaceEngineProvider)
      .clientFor(MarketplaceCapability.readNotifications);
});

final catalogRepositoryProvider = Provider<CatalogRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.browseCatalog);
  return client == null
      ? null
      : CatalogRepository(client, resilience: engine.resilience);
});

final restaurantRepositoryProvider = Provider<RestaurantRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverRestaurants);
  return client == null
      ? null
      : RestaurantRepository(client, resilience: engine.resilience);
});

final sellerRestaurantRepositoryProvider =
    Provider<RestaurantRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client =
      engine.clientFor(MarketplaceCapability.configureRestaurantCatalog);
  return client == null
      ? null
      : RestaurantRepository(client, resilience: engine.resilience);
});

final cartRepositoryProvider = Provider<CartRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.manageCart);
  return client == null ? null : CartRepository(client, resilience: engine.resilience);
});

final checkoutRepositoryProvider = Provider<CheckoutRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.placeOrder);
  return client == null ? null : CheckoutRepository(client, resilience: engine.resilience);
});

final courierRepositoryProvider = Provider<CourierRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.courierOperations);
  return client == null ? null : CourierRepository(client, resilience: engine.resilience);
});

final deliveryRepositoryProvider = Provider<DeliveryRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.trackDelivery);
  return client == null ? null : DeliveryRepository(client, resilience: engine.resilience);
});

final followsRepositoryProvider = Provider<FollowsRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.manageFollows);
  return client == null ? null : FollowsRepository(client, resilience: engine.resilience);
});

final groupBuyRepositoryProvider = Provider<GroupBuyRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverGroupBuys);
  return client == null ? null : GroupBuyRepository(client, resilience: engine.resilience);
});

final mechanicRepositoryProvider = Provider<MechanicRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverMechanics);
  return client == null ? null : MechanicRepository(client, resilience: engine.resilience);
});

final messagingRepositoryProvider = Provider<MessagingRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.useMessaging);
  return client == null ? null : MessagingRepository(client, resilience: engine.resilience);
});

final notificationRepositoryProvider =
    Provider<NotificationRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.readNotifications);
  return client == null ? null : NotificationRepository(client, resilience: engine.resilience);
});

final sellerRepositoryProvider = Provider<SellerRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.readSellerFinance);
  return client == null ? null : SellerRepository(client, resilience: engine.resilience);
});

final sellerProductsRepositoryProvider =
    Provider<SellerProductsRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.manageSellerCatalog);
  return client == null ? null : SellerProductsRepository(client, resilience: engine.resilience);
});

final serviceRepositoryProvider = Provider<ServiceRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverServices);
  return client == null ? null : ServiceRepository(client, resilience: engine.resilience);
});

final transportRepositoryProvider = Provider<TransportRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverTransport);
  return client == null ? null : TransportRepository(client, resilience: engine.resilience);
});

final verticalRepositoryProvider = Provider<VerticalRepository?>((ref) {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverVerticals);
  return client == null ? null : VerticalRepository(client, resilience: engine.resilience);
});
