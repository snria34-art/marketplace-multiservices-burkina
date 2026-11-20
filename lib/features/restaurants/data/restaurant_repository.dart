import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantRepository {
  const RestaurantRepository(this.client);

  final SupabaseClient client;


  /// Saves a seller-owned option group. Prices are surcharge amounts in XOF.
  /// Existing group options are replaced atomically by the database RPC.
  Future<String> saveItemOptionGroup({
    String? groupId,
    required String menuItemId,
    required String name,
    required String selectionType,
    required int minSelections,
    required int maxSelections,
    required List<Map<String, dynamic>> options,
  }) async {
    final result = await client.rpc(
      'save_restaurant_item_option_group',
      params: {
        'p_group_id': groupId,
        'p_menu_item_id': menuItemId,
        'p_name': name.trim(),
        'p_selection_type': selectionType,
        'p_min_selections': minSelections,
        'p_max_selections': maxSelections,
        'p_options': options,
      },
    );
    final id = result?.toString().trim() ?? '';
    if (id.isEmpty || id.toLowerCase() == 'null') {
      throw StateError('Réponse de personnalisation invalide.');
    }
    return id;
  }

  /// Gets an authoritative XOF unit price from the database for chosen options.
  Future<Map<String, dynamic>> quoteMenuItem({
    required String menuItemId,
    required Map<String, List<String>> selections,
  }) async {
    final response = await client.rpc(
      'quote_restaurant_menu_item',
      params: {
        'p_menu_item_id': menuItemId,
        'p_selections': selections,
      },
    );
    if (response is! Map) {
      throw StateError('Devis de personnalisation invalide.');
    }
    return Map<String, dynamic>.from(response);
  }


  Future<List<Map<String, dynamic>>> sellerMenuItems() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');

    final seller = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    final sellerId = seller?['id']?.toString();
    if (sellerId == null || sellerId.isEmpty) {
      throw StateError('Profil vendeur introuvable.');
    }

    final rows = await client
        .from('restaurant_profiles')
        .select(
          'id,shop_id,shops!inner(name,seller_id),restaurant_menus!inner(id,name,restaurant_menu_items!inner(id,name,description,price,active,restaurant_menu_item_option_groups(id,name,selection_type,min_selections,max_selections,sort_order,restaurant_menu_item_options(id,name,price_delta,sort_order))))',
        )
        .eq('shops.seller_id', sellerId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> restaurants() async {
    final rows = await client
        .from('restaurant_profiles')
        .select(
          'id,shop_id,cuisine_types,preparation_time_min,delivery_available,shops(name,address,status),restaurant_menus(id,name,description,restaurant_menu_items(id,name,description,price,active,sort_order))',
        )
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
