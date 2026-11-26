import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../application/restaurant_providers.dart';
import '../data/restaurant_repository.dart';

class RestaurantsPage extends ConsumerStatefulWidget {
  const RestaurantsPage({super.key});

  @override
  ConsumerState<RestaurantsPage> createState() => _RestaurantsPageState();
}

class _RestaurantsPageState extends ConsumerState<RestaurantsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return ref.read(restaurantRepositoryProvider)?.restaurants() ??
        Future.value(const []);
  }

  Future<void> _addToCart(String productId) async {
    final client = ref.read(supabaseProvider);
    final cart = ref.read(cartRepositoryProvider);

    if (client?.auth.currentUser == null || cart == null) {
      if (mounted) context.push('/auth');
      return;
    }

    try {
      await cart.addToCart(productId: productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plat ajouté au panier.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ajout impossible. Vérifiez que le plat est toujours disponible.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants'),
        actions: [
          IconButton(
            tooltip: 'Mon panier',
            onPressed: () => context.push('/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Espace restaurateur',
            onPressed: () => context.push('/seller/restaurant'),
            icon: const Icon(Icons.restaurant_menu_outlined),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 40),
                    const SizedBox(height: 10),
                    const Text(
                      'Impossible de charger les restaurants.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final restaurants =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (restaurants.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun restaurant validé n’est disponible pour le moment.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: restaurants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final restaurant = restaurants[index];
                final shop = restaurant['shops'] is Map
                    ? Map<String, dynamic>.from(restaurant['shops'] as Map)
                    : const <String, dynamic>{};
                final cuisines = restaurant['cuisine_types'];
                final acceptingOrders = restaurant['accepting_orders'] != false;
                final menus = (restaurant['restaurant_menus'] is List
                        ? restaurant['restaurant_menus'] as List
                        : const [])
                    .whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .where((menu) => menu['active'] != false)
                    .toList();

                final details = <String>[
                  if (cuisines is List && cuisines.isNotEmpty)
                    cuisines.join(', '),
                  if (restaurant['preparation_time_min'] != null)
                    'Préparation : ${restaurant['preparation_time_min']} min',
                  restaurant['delivery_available'] == true
                      ? 'Livraison disponible'
                      : 'Livraison non proposée',
                  if (restaurant['pickup_available'] == true)
                    'Retrait sur place possible',
                  if ((restaurant['opening_hours']?.toString() ?? '').trim().isNotEmpty)
                    'Horaires : ${restaurant['opening_hours']}',
                ];

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.restaurant_outlined),
                        ),
                        title: Text(
                          shop['name']?.toString() ?? 'Restaurant',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          details.isEmpty
                              ? 'Cuisine non renseignée'
                              : details.join(' • '),
                        ),
                        trailing: Icon(
                          acceptingOrders
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline,
                          color: acceptingOrders
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (!acceptingOrders)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text('Ce restaurant ne prend pas de commandes actuellement.'),
                        ),
                      if (menus.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucun menu publié pour le moment.'),
                        )
                      else
                        for (final menu in menus)
                          _MenuSection(
                            menu: menu,
                            acceptingOrders: acceptingOrders,
                            onAddToCart: _addToCart,
                          ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({
    required this.menu,
    required this.acceptingOrders,
    required this.onAddToCart,
  });

  final Map<String, dynamic> menu;
  final bool acceptingOrders;
  final ValueChanged<String> onAddToCart;

  @override
  Widget build(BuildContext context) {
    final rawItems = menu['restaurant_menu_items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((item) => item['active'] != false)
            .toList()
        : const <Map<String, dynamic>>[];

    return ExpansionTile(
      title: Text(menu['name']?.toString() ?? 'Menu'),
      subtitle: Text(menu['description']?.toString() ?? ''),
      children: [
        if (items.isEmpty)
          const ListTile(title: Text('Aucun plat dans ce menu.')),
        for (final item in items)
          ListTile(
            title: Text(item['name']?.toString() ?? 'Plat'),
            subtitle: Text(
              [
                if ((item['description']?.toString() ?? '').isNotEmpty)
                  item['description'].toString(),
                '${item['price']?.toString() ?? '0'} XOF',
              ].join(' • '),
            ),
            trailing: item['product_id'] == null
                ? const Text('Non commandable')
                : IconButton.filledTonal(
                    tooltip: 'Ajouter au panier',
                    onPressed: acceptingOrders
                        ? () => onAddToCart(item['product_id'].toString())
                        : null,
                    icon: const Icon(Icons.add_shopping_cart_outlined),
                  ),
          ),
      ],
    );
  }
}
