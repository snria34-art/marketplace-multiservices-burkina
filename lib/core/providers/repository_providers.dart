import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../engine/marketplace_engine.dart';
import '../../features/cart/data/cart_repository.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/checkout/data/checkout_repository.dart';
import '../../features/messaging/data/messaging_repository.dart';
import '../../features/seller/data/seller_repository.dart';
import '../../features/seller/data/seller_products_repository.dart';
import '../../features/verticals/data/vertical_repository.dart';

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  if (!SupabaseConfig.isConfigured) return null;
  return Supabase.instance.client;
});

final marketplaceEngineProvider = Provider<MarketplaceEngine>((ref) {
  return MarketplaceEngine(ref.watch(supabaseProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : CatalogRepository(client);
});

final cartRepositoryProvider = Provider<CartRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : CartRepository(client);
});

final checkoutRepositoryProvider = Provider<CheckoutRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : CheckoutRepository(client);
});

final messagingRepositoryProvider = Provider<MessagingRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : MessagingRepository(client);
});

final sellerRepositoryProvider = Provider<SellerRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SellerRepository(client);
});

final sellerProductsRepositoryProvider =
    Provider<SellerProductsRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SellerProductsRepository(client);
});

final verticalRepositoryProvider = Provider<VerticalRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : VerticalRepository(client);
});
