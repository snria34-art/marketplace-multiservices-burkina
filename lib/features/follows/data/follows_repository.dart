import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

class FollowsRepository {
  const FollowsRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  Future<List<Map<String, dynamic>>> favoriteProducts() async {
    final raw = await _read(() => client.rpc(
      'my_favorite_products',
      params: {'p_limit': 100},
    ));

    return _maps(raw);
  }

  Future<List<Map<String, dynamic>>> followedShops() async {
    final raw = await _read(() => client.rpc(
      'my_followed_shops',
      params: {'p_limit': 100},
    ));

    return _maps(raw);
  }

  Future<void> toggleProductFavorite(String productId) async {
    await client.rpc(
      'toggle_product_favorite',
      params: {'p_product_id': productId},
    );
  }

  Future<void> toggleShopFollow(String shopId) async {
    await client.rpc(
      'toggle_shop_follow',
      params: {'p_shop_id': shopId},
    );
  }

  List<Map<String, dynamic>> _maps(dynamic rows) {
    if (rows is! List) return const [];

    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
