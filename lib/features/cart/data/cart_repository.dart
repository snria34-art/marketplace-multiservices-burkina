import 'package:supabase_flutter/supabase_flutter.dart';

class CartRepository {
  const CartRepository(this.client);

  final SupabaseClient client;

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

    final carts = await client
        .from('carts')
        .select('id,status,updated_at')
        .eq('customer_id', user.id)
        .eq('status', 'ACTIVE')
        .limit(1);

    if ((carts as List).isEmpty) return null;

    final cart = Map<String, dynamic>.from(carts.first as Map);
    final cartId = cart['id'].toString();

    final items = await client
        .from('cart_items')
        .select(
          'id,product_id,variant_id,quantity,unit_price,selected_option_level_ids,created_at,products(name,price)',
        )
        .eq('cart_id', cartId)
        .order('created_at');

    final mappedItems = (items as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    for (final item in mappedItems) {
      final snapshot = await client.rpc(
        'get_my_cart_item_customizations',
        params: {'p_cart_item_id': item['id']},
      );
      item['customizations'] = snapshot is List
          ? snapshot.whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
          : const <Map<String, dynamic>>[];
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
