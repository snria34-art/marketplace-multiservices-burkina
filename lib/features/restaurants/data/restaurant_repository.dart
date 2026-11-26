import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantRepository {
  const RestaurantRepository(this.client);

  final SupabaseClient client;

  static const _profileSelect = '''
    id,shop_id,cuisine_types,preparation_time_min,delivery_available,
    accepting_orders,pickup_available,minimum_order_amount,opening_hours,
    restaurant_menus(
      id,name,description,active,sort_order,
      restaurant_menu_items(
        id,product_id,name,description,price,active,sort_order
      )
    )
  ''';

  Future<List<Map<String, dynamic>>> restaurants() async {
    final rows = await client
        .from('restaurant_profiles')
        .select('''
          id,shop_id,cuisine_types,preparation_time_min,delivery_available,
          accepting_orders,pickup_available,minimum_order_amount,opening_hours,
          shops(name,address,status,verification_status),
          restaurant_menus(
            id,name,description,active,sort_order,
            restaurant_menu_items(
              id,product_id,name,description,price,active,sort_order
            )
          )
        ''')
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> managedRestaurants() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');

    final sellerRows = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);
    if ((sellerRows as List).isEmpty) return const [];

    final sellerId = (sellerRows.first as Map)['id'].toString();
    final shopRows = await client
        .from('shops')
        .select('id,name,status,verification_status,address')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    final shops = (shopRows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (shops.isEmpty) return const [];

    final shopIds = shops.map((shop) => shop['id'].toString()).toList();
    final profileRows = await client
        .from('restaurant_profiles')
        .select(_profileSelect)
        .inFilter('shop_id', shopIds);
    final profilesByShop = <String, Map<String, dynamic>>{
      for (final raw in profileRows as List)
        (raw as Map)['shop_id'].toString():
            Map<String, dynamic>.from(raw as Map),
    };

    return shops
        .map((shop) => <String, dynamic>{
              'shop': shop,
              'profile': profilesByShop[shop['id'].toString()],
            })
        .toList();
  }

  Future<void> createRestaurantProfile(String shopId) async {
    await client.from('restaurant_profiles').insert({
      'shop_id': shopId,
      'cuisine_types': <String>[],
      'preparation_time_min': 25,
      'delivery_available': true,
      'accepting_orders': true,
      'pickup_available': true,
      'minimum_order_amount': 0,
      'opening_hours': '',
    });
  }

  Future<void> updateRestaurantProfile({
    required String profileId,
    required List<String> cuisineTypes,
    required int preparationTimeMin,
    required bool deliveryAvailable,
    required bool acceptingOrders,
    required bool pickupAvailable,
    required num minimumOrderAmount,
    required String openingHours,
  }) async {
    await client.from('restaurant_profiles').update({
      'cuisine_types': cuisineTypes,
      'preparation_time_min': preparationTimeMin,
      'delivery_available': deliveryAvailable,
      'accepting_orders': acceptingOrders,
      'pickup_available': pickupAvailable,
      'minimum_order_amount': minimumOrderAmount,
      'opening_hours': openingHours,
    }).eq('id', profileId);
  }

  Future<void> createMenu({
    required String restaurantId,
    required String name,
    required String description,
  }) async {
    await client.from('restaurant_menus').insert({
      'restaurant_id': restaurantId,
      'name': name,
      'description': description,
      'active': true,
    });
  }

  Future<void> updateMenu({
    required String menuId,
    required String name,
    required String description,
    required bool active,
  }) async {
    await client.from('restaurant_menus').update({
      'name': name,
      'description': description,
      'active': active,
    }).eq('id', menuId);
  }

  Future<void> deleteMenu(String menuId) async {
    await client.from('restaurant_menus').delete().eq('id', menuId);
  }

  Future<List<Map<String, dynamic>>> availableProducts(String shopId) async {
    final rows = await client
        .from('products')
        .select('id,name,description,price,status')
        .eq('shop_id', shopId)
        .eq('status', 'ACTIVE')
        .order('name')
        .limit(300);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> addMenuItem({
    required String menuId,
    required Map<String, dynamic> product,
  }) async {
    // Cart checkout uses the catalog product price as its source of truth.
    // Keep the restaurant menu price aligned with that same server-owned price.
    final price = num.tryParse(product['price']?.toString() ?? '');
    if (price == null || price < 0) {
      throw const FormatException('Prix catalogue invalide.');
    }

    await client.from('restaurant_menu_items').insert({
      'menu_id': menuId,
      'product_id': product['id'],
      'name': product['name'],
      'description': product['description'],
      'price': price,
      'active': true,
    });
  }

  Future<void> setMenuItemActive({
    required String itemId,
    required bool active,
  }) async {
    await client
        .from('restaurant_menu_items')
        .update({'active': active})
        .eq('id', itemId);
  }

  Future<void> deleteMenuItem(String itemId) async {
    await client.from('restaurant_menu_items').delete().eq('id', itemId);
  }

  Future<List<Map<String, dynamic>>> restaurantOrders() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');

    final sellerRows = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);
    if ((sellerRows as List).isEmpty) return const [];

    final sellerId = (sellerRows.first as Map)['id'].toString();
    final shopRows = await client
        .from('shops')
        .select('id')
        .eq('seller_id', sellerId);
    final allShopIds = (shopRows as List)
        .map((row) => (row as Map)['id'].toString())
        .toList();
    if (allShopIds.isEmpty) return const [];

    final profileRows = await client
        .from('restaurant_profiles')
        .select('shop_id')
        .inFilter('shop_id', allShopIds);
    final restaurantShopIds = (profileRows as List)
        .map((row) => (row as Map)['shop_id'].toString())
        .toList();
    if (restaurantShopIds.isEmpty) return const [];

    final rows = await client
        .from('order_groups')
        .select('''
          id,order_id,shop_id,status,subtotal,created_at,
          shops(name),
          order_items(product_name,quantity,unit_price,total_price)
        ''')
        .inFilter('shop_id', restaurantShopIds)
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> transitionOrder({
    required String orderGroupId,
    required String nextStatus,
  }) async {
    await client.rpc(
      'restaurant_transition_order_group_status',
      params: {
        'p_order_group_id': orderGroupId,
        'p_next_status': nextStatus,
        'p_note': 'Mise à jour depuis l’espace restaurant',
      },
    );
  }
}
