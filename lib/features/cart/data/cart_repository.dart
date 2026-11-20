import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

class CartRepository {
  const CartRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  Future<String> addToCart({
    required String productId,
    int quantity = 1,
    String? variantId,
  }) async {
    final result = await client.rpc(
      'add_to_cart',
      params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_variant_id': variantId,
      },
    );

    return result.toString();
  }

  Future<Map<String, dynamic>?> activeCart() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final carts = await _read(() async => await client
        .from('carts')
        .select('id,status,updated_at')
        .eq('customer_id', user.id)
        .eq('status', 'ACTIVE')
        .limit(1));

    if ((carts as List).isEmpty) return null;

    final cart = Map<String, dynamic>.from(carts.first as Map);
    final cartId = cart['id'].toString();

    final items = await _read(() async => await client
        .from('cart_items')
        .select(
          'id,product_id,variant_id,quantity,unit_price,created_at,products(name,price),product_variants(name),restaurant_menu_item_id,restaurant_selections,restaurant_menu_items(name,restaurant_menu_item_option_groups(id,name,restaurant_menu_item_options(id,name,price_delta)))',
        )
        .eq('cart_id', cartId)
        .order('created_at'));

    final mappedItems = (items as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    for (final item in mappedItems) {
      final menuItemId = item['restaurant_menu_item_id']?.toString();
      final rawSelections = item['restaurant_selections'];
      if (menuItemId == null || menuItemId.isEmpty) {
        item['customization_invalid'] =
            rawSelections is Map && rawSelections.isNotEmpty;
        continue;
      }
      final selections = <String, List<String>>{};
      if (rawSelections is Map) {
        for (final entry in rawSelections.entries) {
          if (entry.value is List) {
            selections[entry.key.toString()] =
                (entry.value as List).map((id) => id.toString()).toList();
          }
        }
      }
      try {
        final quote = await _read(() => client.rpc(
          'quote_restaurant_menu_item',
          params: {
            'p_menu_item_id': menuItemId,
            'p_selections': selections,
          },
        ));
        if (quote is! Map) throw StateError('invalid_customization_quote');
        item['restaurant_options_total'] = quote['options_total'];
        item['restaurant_unit_total'] = quote['unit_total'];
        item['customization_invalid'] = false;
      } catch (_) {
        item['customization_invalid'] = true;
      }
    }

    cart['items'] = mappedItems;
    return cart;
  }

  Future<void> setQuantity({
    required String cartItemId,
    required int quantity,
  }) async {
    if (quantity < 0 || quantity > 1000) {
      throw ArgumentError('Quantité invalide.');
    }

    await client.rpc(
      'set_cart_item_quantity',
      params: {
        'p_cart_item_id': cartItemId,
        'p_quantity': quantity,
      },
    );
  }

  Future<void> remove(String cartItemId) async {
    // Use the ownership-checked RPC so cart timestamps and server-side
    // validation stay consistent with quantity changes.
    await setQuantity(cartItemId: cartItemId, quantity: 0);
  }
}
