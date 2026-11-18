import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../engine/marketplace_engine.dart';
import '../../features/cart/data/cart_repository.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/checkout/data/checkout_repository.dart';

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
