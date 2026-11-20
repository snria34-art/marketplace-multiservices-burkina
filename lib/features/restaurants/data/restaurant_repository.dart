import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantRepository {
  const RestaurantRepository(this.client);

  final SupabaseClient client;


  Future<List<Map<String, dynamic>>> productOptionGroups(
    String productId,
  ) async {
    final rows = await client
        .from('product_option_groups')
        .select(
          'id,name,selection_mode,min_select,max_select,required,sort_order,product_options(id,label,option_kind,sort_order,product_option_levels(id,label,price_delta,quantity_value,is_default,sort_order))',
        )
        .eq('product_id', productId)
        .eq('active', true)
        .order('sort_order');

    return _maps(rows);
  }

  Future<String> addConfiguredRestaurantItemToCart({
    required String productId,
    required int quantity,
    required List<String> selectedLevelIds,
  }) async {
    if (quantity < 1 || quantity > 1000) {
      throw ArgumentError('Quantité invalide.');
    }
    if (selectedLevelIds.length > 100 ||
        selectedLevelIds.toSet().length != selectedLevelIds.length) {
      throw ArgumentError('Options du plat invalides.');
    }

    final result = await client.rpc(
      'add_configured_restaurant_item_to_cart',
      params: {
        'p_product_id': productId,
        'p_variant_id': null,
        'p_quantity': quantity,
        'p_selected_level_ids': selectedLevelIds,
      },
    );
    return result.toString();
  }

  List<Map<String, dynamic>> _maps(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
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
