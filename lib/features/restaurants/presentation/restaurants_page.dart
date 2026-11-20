import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';
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
  static const _restaurantTypes = <(String, String)>[
    ('FAST_FOOD', 'Fast-food'),
    ('TRADITIONAL', 'Traditionnelle'),
    ('GRILL', 'Grillades'),
    ('PIZZERIA', 'Pizzeria'),
    ('BAKERY', 'Boulangerie'),
    ('CAFE', 'Café'),
    ('SEAFOOD', 'Poissons & fruits de mer'),
    ('VEGETARIAN', 'Végétarien'),
    ('INTERNATIONAL', 'Cuisine internationale'),
  ];

  static const _cuisines = <(String, String)>[
    ('BURKINABE', 'Burkinabè'),
    ('IVORIAN', 'Ivoirienne'),
    ('TOGOLESE', 'Togolaise'),
    ('GHANAIAN', 'Ghanéenne'),
    ('NIGERIAN', 'Nigériane'),
    ('SENEGALESE', 'Sénégalaise'),
    ('MALIENNE', 'Malienne'),
    ('BENINESE', 'Béninoise'),
    ('CAMEROONIAN', 'Camerounaise'),
    ('LEBANESE', 'Libanaise'),
    ('ITALIAN', 'Italienne'),
    ('FRENCH', 'Française'),
    ('CHINESE', 'Chinoise'),
    ('INDIAN', 'Indienne'),
    ('MOROCCAN', 'Marocaine'),
  ];

  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  String? _restaurantType;
  String? _cuisineType;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return ref.read(restaurantRepositoryProvider)?.searchRestaurantCatalog(
          query: _searchController.text,
          restaurantType: _restaurantType,
          cuisineType: _cuisineType,
          limit: 150,
        ) ?? Future.value(const []);
  }

  void _search() => setState(() => _future = _load());

  Widget _filterChips(
    List<(String, String)> values,
    String? selected,
    ValueChanged<String?> onSelected,
  ) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('Tout'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(value.$2),
                selected: selected == value.$1,
                onSelected: (_) => onSelected(selected == value.$1 ? null : value.$1),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants & plats'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _search,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Rechercher un plat, une cuisine, un restaurant…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Rechercher',
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Type de restaurant',
                style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: _filterChips(_restaurantTypes, _restaurantType, (value) {
              setState(() {
                _restaurantType = value;
                _future = _load();
              });
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Cuisine du pays',
                style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: _filterChips(_cuisines, _cuisineType, (value) {
              setState(() {
                _cuisineType = value;
                _future = _load();
              });
            }),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                        const Text('La recherche des restaurants est indisponible.'),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _search,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  );
                }
                final results = snapshot.data ?? const <Map<String, dynamic>>[];
                if (results.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucun plat trouvé. Essayez un autre nom ou une autre cuisine.',
                        textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    final cuisines = result['cuisine_types'];
                    final cuisineLabels = cuisines is List
                        ? cuisines.map((value) => value.toString()).join(' · ')
                        : '';
                    final item = <String, dynamic>{
                      'id': result['menu_item_id'],
                      'name': result['dish_name'],
                      'description': result['dish_description'],
                      'price': result['price'],
                      'product_id': result['product_id'],
                      'restaurant_menu_item_option_groups': result['option_groups'] ?? const [],
                    };
                    return Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              child: Icon(Icons.restaurant_outlined),
                            ),
                            title: Text(result['restaurant_name']?.toString() ?? 'Restaurant'),
                            subtitle: Text([
                              _restaurantTypeLabel(result['restaurant_type']?.toString()),
                              cuisineLabels,
                              if (result['address']?.toString().isNotEmpty == true)
                                result['address'].toString(),
                            ].where((value) => value.isNotEmpty).join(' · ')),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(result['menu_name']?.toString() ?? 'Menu',
                                    style: Theme.of(context).textTheme.labelMedium),
                                ),
                                Text(formatXof(num.tryParse(result['price']?.toString() ?? '') ?? 0),
                                  style: Theme.of(context).textTheme.labelLarge),
                              ],
                            ),
                          ),
                          _MenuItemTile(item: item),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _restaurantTypeLabel(String? value) {
    for (final type in _restaurantTypes) {
      if (type.$1 == value) return type.$2;
    }
    return 'Restaurant';
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


class _MenuItemTile extends ConsumerStatefulWidget {
  const _MenuItemTile({required this.item});
  final Map<String, dynamic> item;

  @override
  ConsumerState<_MenuItemTile> createState() => _MenuItemTileState();
}

class _MenuItemTileState extends ConsumerState<_MenuItemTile> {
  bool _adding = false;

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Map<String, List<String>>?> _selectOptions(
      List<Map<String, dynamic>> groups) async {
    final selected = <String, Set<String>>{
      for (final group in groups) group['id'].toString(): <String>{},
    };

    return showDialog<Map<String, List<String>>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Personnaliser ${widget.item['name'] ?? 'ce plat'}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in groups) ...[
                    Text(group['name']?.toString() ?? 'Choix',
                      style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      (int.tryParse(group['min_selections']?.toString() ?? '0') ?? 0) > 0
                          ? 'Obligatoire' : 'Facultatif',
                      style: Theme.of(context).textTheme.labelSmall),
                    for (final option in _maps(group['restaurant_menu_item_options']))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected[group['id'].toString()]!.contains(option['id'].toString()),
                        title: Text(option['name']?.toString() ?? 'Option'),
                        subtitle: Text(
                          (num.tryParse(option['price_delta']?.toString() ?? '') ?? 0) == 0
                              ? 'Inclus' : '+${formatXof(num.tryParse(option['price_delta']?.toString() ?? '') ?? 0)}'),
                        onChanged: (checked) {
                          setDialogState(() {
                            final values = selected[group['id'].toString()]!;
                            final id = option['id'].toString();
                            final multiple = group['selection_type']?.toString() == 'MULTIPLE';
                            final max = int.tryParse(group['max_selections']?.toString() ?? '1') ?? 1;
                            if (checked == true) {
                              if (!multiple) values.clear();
                              if (values.length < max) values.add(id);
                            } else {
                              values.remove(id);
                            }
                          });
                        },
                      ),
                    const Divider(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                for (final group in groups) {
                  final min = int.tryParse(group['min_selections']?.toString() ?? '0') ?? 0;
                  if ((selected[group['id'].toString()]?.length ?? 0) < min) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Choisissez au moins $min option(s) pour ${group['name']}.')),
                    );
                    return;
                  }
                }
                Navigator.pop(dialogContext, {
                  for (final entry in selected.entries)
                    if (entry.value.isNotEmpty) entry.key: entry.value.toList(),
                });
              },
              child: const Text('Voir le prix'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart() async {
    if (_adding) return;
    final item = widget.item;
    final groups = _maps(item['restaurant_menu_item_option_groups']);
    final selections = await _selectOptions(groups);
    if (!mounted || selections == null) return;

    final repository = ref.read(restaurantRepositoryProvider);
    if (repository == null) {
      _show('Service indisponible. Réessayez.');
      return;
    }

    setState(() => _adding = true);
    try {
      final quote = await repository.quoteMenuItem(
        menuItemId: item['id'].toString(),
        selections: selections,
      );
      if (!mounted) return;
      final total = num.tryParse(quote['unit_total']?.toString() ?? '');
      final base = num.tryParse(quote['base_price']?.toString() ?? '');
      final extras = num.tryParse(quote['options_total']?.toString() ?? '');
      if (total == null || base == null || extras == null) {
        throw StateError('Devis de personnalisation invalide.');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmer le plat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['name']?.toString() ?? 'Plat'),
              const SizedBox(height: 12),
              Text('Prix de base : ${formatXof(base)}'),
              Text('Suppléments : ${formatXof(extras)}'),
              const Divider(),
              Text('Total unitaire : ${formatXof(total)}',
                style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Le prix est vérifié par le serveur avant l’ajout au panier.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Retour')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter au panier')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      await repository.addMenuItemToCart(
        menuItemId: item['id'].toString(),
        quantity: 1,
        selections: selections,
      );
      if (!mounted) return;
      _show('Plat ajouté au panier.');
    } catch (error) {
      _show(error.toString().contains('cart_item_customization_conflict')
          ? 'Ce plat est déjà dans le panier avec d’autres choix. Retirez cette ligne avant de choisir une autre personnalisation.'
          : 'Ajout impossible. Le restaurant a peut-être modifié ses choix ou ses tarifs. Actualisez le menu.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final groups = _maps(item['restaurant_menu_item_option_groups']);
    final linked = item['product_id']?.toString().isNotEmpty == true;
    final product = item['products'] is Map ? Map<String, dynamic>.from(item['products'] as Map) : const <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']?.toString() ?? 'Plat',
                    style: Theme.of(context).textTheme.titleMedium),
                  if ((item['description']?.toString() ?? '').isNotEmpty)
                    Text(item['description'].toString()),
                ],
              )),
              const SizedBox(width: 12),
              Text('${formatXof(num.tryParse((product['price'] ?? item['price'] ?? '0').toString()) ?? 0)}',
                style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          if (groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${groups.length} groupe(s) de personnalisation disponibles',
                style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: linked && !_adding ? _addToCart : null,
              icon: _adding
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_shopping_cart),
              label: Text(linked ? 'Personnaliser et ajouter' : 'Indisponible'),
            ),
          ),
        ],
      ),
    );
  }
}
