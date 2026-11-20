import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

class RestaurantRepository {
  RestaurantRepository(this.client, {MarketplaceResilience? resilience})
      : _resilience = resilience ?? MarketplaceResilience();

  final SupabaseClient client;
  final MarketplaceResilience _resilience;

  Future<T> _read<T>(Future<T> Function() operation) => _resilience.read(operation);


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


  /// Saves a formula slot whose choices are real active products from this shop.
  Future<String> saveFormulaComponent({
    String? groupId,
    required String menuItemId,
    required String name,
    required String componentType,
    required List<Map<String, dynamic>> products,
  }) async {
    final result = await client.rpc(
      'save_restaurant_formula_component',
      params: {
        'p_group_id': groupId,
        'p_menu_item_id': menuItemId,
        'p_name': name.trim(),
        'p_component_type': componentType,
        'p_options': products,
      },
    );
    final id = result?.toString().trim() ?? '';
    if (id.isEmpty || id.toLowerCase() == 'null') {
      throw StateError('Enregistrement de formule invalide.');
    }
    return id;
  }

  Future<String> addMenuItemToCart({
    required String menuItemId,
    int quantity = 1,
    required Map<String, List<String>> selections,
  }) async {
    if (quantity < 1 || quantity > 1000) {
      throw ArgumentError('Quantité invalide.');
    }
    final result = await client.rpc(
      'add_restaurant_menu_item_to_cart',
      params: {
        'p_menu_item_id': menuItemId,
        'p_quantity': quantity,
        'p_selections': selections,
      },
    );
    final id = result?.toString().trim() ?? '';
    if (id.isEmpty || id.toLowerCase() == 'null') {
      throw StateError('Ajout au panier invalide.');
    }
    return id;
  }

  /// Gets an authoritative XOF unit price from the database for chosen options.
  Future<Map<String, dynamic>> quoteMenuItem({
    required String menuItemId,
    required Map<String, List<String>> selections,
  }) async {
    final response = await _read(() => client.rpc(
      'quote_restaurant_menu_item',
      params: {
        'p_menu_item_id': menuItemId,
        'p_selections': selections,
      },
    ));
    if (response is! Map) {
      throw StateError('Devis de personnalisation invalide.');
    }
    return Map<String, dynamic>.from(response);
  }



  Future<List<Map<String, dynamic>>> sellerProducts() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');
    final seller = await _read(() => client.from('sellers').select('id')
        .eq('user_id', user.id).maybeSingle());
    final sellerId = seller?['id']?.toString();
    if (sellerId == null || sellerId.isEmpty) return const [];
    final shops = await _read(() => client.from('shops').select('id').eq('seller_id', sellerId));
    final shopIds = (shops as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>().toList();
    if (shopIds.isEmpty) return const [];
    final rows = await _read(() async => await client.from('products')
        .select('id,name,price,shop_id')
        .inFilter('shop_id', shopIds)
        .eq('status', 'ACTIVE')
        .order('name')
        .limit(500));
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> linkMenuItemProduct({
    required String menuItemId,
    required String productId,
  }) async {
    final row = await client
        .from('restaurant_menu_items')
        .update({'product_id': productId})
        .eq('id', menuItemId)
        .select('id,product_id')
        .maybeSingle();
    if (row == null || row['product_id']?.toString() != productId) {
      throw StateError('Liaison produit non autorisée ou introuvable.');
    }
  }

  Future<List<Map<String, dynamic>>> sellerMenuItems() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');

    final seller = await _read(() async => await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle());
    final sellerId = seller?['id']?.toString();
    if (sellerId == null || sellerId.isEmpty) {
      throw StateError('Profil vendeur introuvable.');
    }

    final rows = await _read(() async => await client
        .from('restaurant_profiles')
        .select(
          'id,shop_id,restaurant_type,cuisine_types,shops!inner(name,seller_id),restaurant_menus!inner(id,name,restaurant_menu_items!inner(id,product_id,products(price),name,description,price,active,restaurant_menu_item_option_groups(id,name,component_type,selection_type,min_selections,max_selections,sort_order,restaurant_menu_item_options(id,name,price_delta,linked_product_id,sort_order))))',
        )
        .eq('shops.seller_id', sellerId)
        .order('created_at', ascending: false));

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveDiscoveryProfile({
    required String restaurantId,
    required String restaurantType,
    required List<String> cuisineTypes,
  }) async {
    await client.rpc(
      'save_restaurant_discovery_profile',
      params: {
        'p_restaurant_id': restaurantId,
        'p_restaurant_type': restaurantType,
        'p_cuisine_types': cuisineTypes,
      },
    );
  }

  Future<List<Map<String, dynamic>>> searchRestaurantCatalog({
    String query = '',
    String? restaurantType,
    String? cuisineType,
    int limit = 100,
  }) async {
    final response = await _read(() => client.rpc(
      'search_restaurant_catalog',
      params: {
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_restaurant_type': restaurantType,
        'p_cuisine_type': cuisineType,
        'p_limit': limit,
      },
    ));
    if (response is! List) {
      throw StateError('Réponse de recherche restaurant invalide.');
    }
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> restaurants() async {
    final rows = await _read(() async => await client
        .from('restaurant_profiles')
        .select(
          'id,shop_id,cuisine_types,preparation_time_min,delivery_available,shops(name,address,status),restaurant_menus(id,name,description,restaurant_menu_items(id,product_id,products(price),name,description,price,active,sort_order,restaurant_menu_item_option_groups(id,name,selection_type,min_selections,max_selections,sort_order,restaurant_menu_item_options(id,name,price_delta,sort_order))))',
        )
        .order('created_at', ascending: false)
        .limit(100));

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
