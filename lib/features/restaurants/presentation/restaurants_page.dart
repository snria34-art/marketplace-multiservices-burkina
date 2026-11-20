import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/restaurant_repository.dart';

final restaurantRepositoryProvider = Provider<RestaurantRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : RestaurantRepository(client);
});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants'),
        actions: [
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Impossible de charger les restaurants.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          final restaurants =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (restaurants.isEmpty) {
            return const Center(child: Text('Aucun restaurant disponible.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: restaurants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final restaurant = restaurants[index];
              final shop = restaurant['shops'] is Map
                  ? Map<String, dynamic>.from(restaurant['shops'] as Map)
                  : const <String, dynamic>{};
              final cuisines = restaurant['cuisine_types'];

              final rawMenus = restaurant['restaurant_menus'];
              final menus = rawMenus is List
                  ? rawMenus
                      .whereType<Map>()
                      .map((row) => Map<String, dynamic>.from(row))
                      .toList()
                  : const <Map<String, dynamic>>[];

              return Card(
                child: ExpansionTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.restaurant_outlined),
                  ),
                  title: Text(
                    shop['name']?.toString() ?? 'Restaurant',
                  ),
                  subtitle: Text(
                    cuisines is List && cuisines.isNotEmpty
                        ? cuisines.join(', ')
                        : 'Cuisine non renseignée',
                  ),
                  children: [
                    for (final menu in menus) _MenuSection(menu: menu),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.menu});

  final Map<String, dynamic> menu;

  @override
  Widget build(BuildContext context) {
    final rawItems = menu['restaurant_menu_items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];

    return ExpansionTile(
      title: Text(menu['name']?.toString() ?? 'Menu'),
      subtitle: Text(menu['description']?.toString() ?? ''),
      children: [
        for (final item in items)
          _MenuItemTile(item: item),
      ],
    );
  }
}


class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final rawGroups = item['restaurant_menu_item_option_groups'];
    final groups = rawGroups is List
        ? rawGroups
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? 'Plat',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ((item['description']?.toString() ?? '').isNotEmpty)
                      Text(item['description'].toString()),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\${item['price']?.toString() ?? '0'} XOF',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          for (final group in groups) _OptionGroupPreview(group: group),
        ],
      ),
    );
  }
}

class _OptionGroupPreview extends StatelessWidget {
  const _OptionGroupPreview({required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final rawOptions = group['restaurant_menu_item_options'];
    final options = rawOptions is List
        ? rawOptions
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];
    final min = int.tryParse(group['min_selections']?.toString() ?? '') ?? 0;
    final max = int.tryParse(group['max_selections']?.toString() ?? '') ?? 1;
    final multiple = group['selection_type']?.toString() == 'MULTIPLE';

    if (options.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\${group['name']?.toString() ?? 'Personnalisation'} · '
            '\${multiple ? 'plusieurs choix' : 'un choix'}'
            '\${min > 0 ? ' · obligatoire' : ' · facultatif'}'
            '\${multiple ? ' · max. $max' : ''}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 3),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 15),
                  const SizedBox(width: 6),
                  Expanded(child: Text(option['name']?.toString() ?? 'Option')),
                  Text(
                    (num.tryParse(option['price_delta']?.toString() ?? '') ?? 0) == 0
                        ? 'Inclus'
                        : '+\${option['price_delta']} XOF',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
