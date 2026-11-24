import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';

class SellerRestaurantOptionsPage extends ConsumerStatefulWidget {
  const SellerRestaurantOptionsPage({super.key});

  @override
  ConsumerState<SellerRestaurantOptionsPage> createState() =>
      _SellerRestaurantOptionsPageState();
}

class _SellerRestaurantOptionsPageState
    extends ConsumerState<SellerRestaurantOptionsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return ref.read(sellerRestaurantRepositoryProvider)?.sellerMenuItems() ??
        Future.value(const []);
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }



  static const _restaurantTypes = <(String, String)>[
    ('FAST_FOOD', 'Fast-food'),
    ('TRADITIONAL', 'Cuisine traditionnelle'),
    ('GRILL', 'Grillades'),
    ('PIZZERIA', 'Pizzeria'),
    ('BAKERY', 'Boulangerie'),
    ('CAFE', 'Café'),
    ('SEAFOOD', 'Poissons & fruits de mer'),
    ('VEGETARIAN', 'Végétarien'),
    ('INTERNATIONAL', 'Cuisine internationale'),
    ('OTHER', 'Autre'),
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
    ('OTHER', 'Autre cuisine'),
  ];

  Future<void> _configureDiscovery(Map<String, dynamic> restaurant) async {
    final repository = ref.read(sellerRestaurantRepositoryProvider);
    if (repository == null) return;
    var type = _restaurantTypes.any((entry) => entry.$1 == restaurant['restaurant_type'])
        ? restaurant['restaurant_type'].toString()
        : 'OTHER';
    final rawCuisines = restaurant['cuisine_types'];
    final selected = <String>{
      if (rawCuisines is List) ...rawCuisines.map((value) => value.toString()),
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Catégories du restaurant'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Genre de restaurant'),
                    items: _restaurantTypes.map((entry) => DropdownMenuItem(
                      value: entry.$1, child: Text(entry.$2),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Origine des cuisines proposées',
                    style: Theme.of(context).textTheme.titleSmall),
                  for (final cuisine in _cuisines)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(cuisine.$1),
                      title: Text(cuisine.$2),
                      onChanged: (checked) => setDialogState(() {
                        if (checked == true) {
                          if (selected.length < 10) selected.add(cuisine.$1);
                        } else {
                          selected.remove(cuisine.$1);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result != true) return;
    try {
      await repository.saveDiscoveryProfile(
        restaurantId: restaurant['id'].toString(),
        restaurantType: type,
        cuisineTypes: selected.toList(),
      );
      if (!mounted) return;
      setState(() => _future = _load());
      _show('Catégories enregistrées. Elles sont maintenant utilisables dans la recherche client.');
    } catch (_) {
      _show('Impossible d’enregistrer les catégories du restaurant.');
    }
  }

  Future<void> _linkProduct(Map<String, dynamic> item) async {
    final repository = ref.read(sellerRestaurantRepositoryProvider);
    if (repository == null) return;
    try {
      final products = await repository.sellerProducts();
      if (!mounted) return;
      if (products.isEmpty) {
        _show('Créez d’abord un produit actif dans votre boutique.');
        return;
      }
      String? selectedId;
      final productId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Lier ce plat à un produit'),
            content: DropdownButtonFormField<String>(
              initialValue: selectedId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Produit de votre boutique'),
              items: products.map((product) => DropdownMenuItem(
                value: product['id'].toString(),
                child: Text('${product['name']} · ${formatXof(num.tryParse(product['price']?.toString() ?? '') ?? 0)}',
                  overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) => setDialogState(() => selectedId = value),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler')),
              FilledButton(
                onPressed: selectedId == null
                    ? null : () => Navigator.pop(dialogContext, selectedId),
                child: const Text('Lier'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || productId == null) return;
      await repository.linkMenuItemProduct(
        menuItemId: item['id'].toString(),
        productId: productId,
      );
      if (!mounted) return;
      setState(() => _future = _load());
      _show('Plat lié au produit. Il peut maintenant être ajouté au panier.');
    } catch (_) {
      _show('Impossible de lier ce plat. Vérifiez que le produit appartient à la même boutique.');
    }
  }

  Future<void> _configureFormula(
    Map<String, dynamic> item, {
    required String componentType,
    Map<String, dynamic>? existing,
  }) async {
    final repository = ref.read(sellerRestaurantRepositoryProvider);
    if (repository == null) return;
    try {
      final products = await repository.sellerProducts();
      if (!mounted) return;
      if (products.isEmpty) {
        _show('Créez d’abord des produits actifs dans votre boutique.');
        return;
      }
      final selected = <String>{
        for (final option in _maps(existing?['restaurant_menu_item_options']))
          if (option['linked_product_id'] != null) option['linked_product_id'].toString(),
      };
      final defaultName = componentType == 'MAIN'
          ? 'Plat de la formule'
          : componentType == 'DRINK'
              ? 'Boisson de la formule'
              : componentType == 'DESSERT'
                  ? 'Dessert de la formule'
                  : 'Accompagnement de la formule';
      final initialName = existing?['name']?.toString() ?? defaultName;
      final chosen = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Composer : $initialName'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Choisissez les produits réels qui seront proposés dans cette partie de la formule. Un seul choix sera demandé au client.'),
                  const SizedBox(height: 8),
                  for (final product in products)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(product['id'].toString()),
                      title: Text(product['name']?.toString() ?? 'Produit'),
                      subtitle: Text(formatXof(num.tryParse(product['price']?.toString() ?? '0') ?? 0)),
                      onChanged: (value) => setDialogState(() {
                        final id = product['id'].toString();
                        if (value == true) { selected.add(id); } else { selected.remove(id); }
                      }),
                    ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, selected.toList()),
                child: const Text('Enregistrer les choix'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || chosen == null) return;
      final byId = {for (final product in products) product['id'].toString(): product};
      final payload = chosen.map((id) {
        final product = byId[id]!;
        return <String, dynamic>{
          'product_id': id,
          'name': product['name']?.toString() ?? 'Produit',
          'price_delta': 0,
        };
      }).toList();
      await repository.saveFormulaComponent(
        groupId: existing?['id']?.toString(),
        menuItemId: item['id'].toString(),
        name: initialName,
        componentType: componentType,
        products: payload,
      );
      if (!mounted) return;
      setState(() => _future = _load());
      _show('Partie de formule enregistrée avec des produits de votre boutique.');
    } catch (_) {
      _show('Impossible d’enregistrer cette partie de formule. Vérifiez les produits actifs et les droits vendeur.');
    }
  }

  Future<void> _configure(Map<String, dynamic> item,
      {Map<String, dynamic>? existing, bool portionPreset = false}) async {
    final name = TextEditingController(
      text: existing?['name']?.toString() ?? (portionPreset ? 'Taille / portion' : ''),
    );
    final options = TextEditingController(
      text: existing != null
          ? _maps(existing['restaurant_menu_item_options'])
              .map((o) => '${o['name'] ?? ''}|${o['price_delta'] ?? 0}').join('\n')
          : portionPreset ? 'Petit|0\nMoyen|500\nGrand|1000' : '',
    );
    var type = existing?['selection_type']?.toString() ?? 'SINGLE';
    var isRequired = portionPreset || (int.tryParse(existing?['min_selections']?.toString() ?? '0') ?? 0) > 0;
    var max = int.tryParse(existing?['max_selections']?.toString() ?? '1') ?? 1;

    final draft = await showDialog<_OptionDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Ajouter une personnalisation' : 'Modifier la personnalisation'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Nom du groupe', hintText: 'Ex. : Accompagnement')),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type de sélection'),
                  items: const [
                    DropdownMenuItem(value: 'SINGLE', child: Text('Un seul choix')),
                    DropdownMenuItem(value: 'MULTIPLE', child: Text('Plusieurs choix')),
                  ],
                  onChanged: (v) { if (v != null) setDialogState(() { type = v; if (v == 'SINGLE') max = 1; }); },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Choix obligatoire'),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                ),
                if (type == 'MULTIPLE')
                  DropdownButtonFormField<int>(
                    initialValue: max,
                    decoration: const InputDecoration(labelText: 'Nombre maximum de choix'),
                    items: List.generate(20, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                    onChanged: (v) { if (v != null) setDialogState(() => max = v); },
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: options, minLines: 4, maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Options et suppléments',
                    hintText: 'Riz|0\nFrites|500\nAlloco|750\nPoulet supplémentaire|1000',
                    helperText: 'Une ligne par choix : nom|supplément en XOF. 0 = inclus.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, _OptionDraft(
                name: name.text.trim(), type: type, isRequired: isRequired,
                max: max, options: options.text,
              )),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    options.dispose();
    if (!mounted || draft == null) return;

    final parsed = <Map<String, dynamic>>[];
    for (final line in draft.options.split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final split = value.lastIndexOf('|');
      if (split <= 0 || split == value.length - 1) {
        _show('Format invalide. Utilisez nom|prix pour chaque option.');
        return;
      }
      final optionName = value.substring(0, split).trim();
      final price = num.tryParse(value.substring(split + 1).trim());
      if (optionName.isEmpty || price == null || price < 0) {
        _show('Nom ou supplément invalide. Le prix doit être positif ou nul.');
        return;
      }
      parsed.add({'name': optionName, 'price_delta': price});
    }
    if (draft.name.isEmpty || parsed.isEmpty || parsed.length > 30) {
      _show('Ajoutez un nom et entre 1 et 30 options.');
      return;
    }

    try {
      await ref.read(sellerRestaurantRepositoryProvider)!.saveItemOptionGroup(
        groupId: existing?['id']?.toString(),
        menuItemId: item['id'].toString(),
        name: draft.name,
        selectionType: draft.type,
        minSelections: draft.isRequired ? 1 : 0,
        maxSelections: draft.max,
        options: parsed,
      );
      if (!mounted) return;
      setState(() => _future = _load());
      _show('Personnalisation enregistrée. Les tarifs restent contrôlés par le serveur.');
    } catch (_) {
      _show('Enregistrement impossible. Vérifiez vos droits vendeur et les options.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personnalisation des plats'),
        actions: [IconButton(onPressed: () => setState(() => _future = _load()),
          icon: const Icon(Icons.refresh), tooltip: 'Actualiser')]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: FilledButton.icon(
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh), label: const Text('Réessayer')));
          }
          final restaurants = snapshot.data ?? const <Map<String, dynamic>>[];
          if (restaurants.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun menu de restaurant associé à vos boutiques. Créez d’abord votre profil restaurant et vos plats.',
                textAlign: TextAlign.center)));
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            const Card(child: Padding(padding: EdgeInsets.all(12),
              child: Text('Définissez les choix proposés au client et le supplément en XOF. Le client ne peut pas modifier ces tarifs.'))),
            for (final restaurant in restaurants) ..._restaurantWidgets(restaurant),
          ]);
        },
      ),
    );
  }

  List<Widget> _restaurantWidgets(Map<String, dynamic> restaurant) {
    final shop = restaurant['shops'] is Map
        ? Map<String, dynamic>.from(restaurant['shops'] as Map) : const <String, dynamic>{};
    final menus = _maps(restaurant['restaurant_menus']);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(shop['name']?.toString() ?? 'Restaurant',
                style: Theme.of(context).textTheme.titleLarge),
            ),
            OutlinedButton.icon(
              onPressed: () => _configureDiscovery(restaurant),
              icon: const Icon(Icons.category_outlined),
              label: const Text('Catégories'),
            ),
          ],
        ),
      ),
      for (final menu in menus)
        Card(child: ExpansionTile(
          title: Text(menu['name']?.toString() ?? 'Menu'),
          children: [
            for (final item in _maps(menu['restaurant_menu_items'])) _itemTile(item),
          ],
        )),
    ];
  }

  Widget _itemTile(Map<String, dynamic> item) {
    final groups = _maps(item['restaurant_menu_item_option_groups']);
    final portionGroups = groups.where((group) =>
        group['name']?.toString().trim().toLowerCase() == 'taille / portion').toList();
    final product = item['products'] is Map ? Map<String, dynamic>.from(item['products'] as Map) : const <String, dynamic>{};
    return ListTile(
      title: Text(item['name']?.toString() ?? 'Plat'),
      subtitle: Text('${formatXof(num.tryParse((product['price'] ?? item['price'] ?? '0').toString()) ?? 0)} · ${groups.length} groupe(s)'),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (item['product_id'] == null)
            IconButton(
              tooltip: 'Lier à un produit',
              icon: const Icon(Icons.link),
              onPressed: () => _linkProduct(item),
            ),
          IconButton(
            tooltip: 'Configurer les portions petit, moyen et grand',
            icon: const Icon(Icons.straighten),
            onPressed: () => _configure(
              item,
              portionPreset: true,
              existing: portionGroups.isEmpty ? null : portionGroups.first,
            ),
          ),
          IconButton(
            tooltip: 'Ajouter une personnalisation',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _configure(item),
          ),
          PopupMenuButton<String>(
            tooltip: 'Composer une formule avec des produits',
            icon: const Icon(Icons.restaurant_menu),
            onSelected: (type) {
              final matches = groups.where((group) => group['component_type'] == type).toList();
              _configureFormula(item, componentType: type,
                existing: matches.isEmpty ? null : matches.first);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'MAIN', child: Text('Plat de la formule')),
              PopupMenuItem(value: 'DRINK', child: Text('Boisson de la formule')),
              PopupMenuItem(value: 'DESSERT', child: Text('Dessert de la formule')),
              PopupMenuItem(value: 'SIDE', child: Text('Accompagnement de la formule')),
            ],
          ),
        ],
      ),
      onTap: groups.isEmpty ? null : () => showModalBottomSheet<void>(
        context: context,
        builder: (context) => ListView(padding: const EdgeInsets.all(16), children: [
          Text(item['name']?.toString() ?? 'Plat',
            style: Theme.of(context).textTheme.titleLarge),
          for (final group in groups)
            ListTile(
              title: Text(group['name']?.toString() ?? 'Choix'),
              subtitle: Text(_maps(group['restaurant_menu_item_options'])
                .map((o) => '${o['name']} (+${formatXof(num.tryParse(o['price_delta']?.toString() ?? '') ?? 0)})').join('\n')),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined), tooltip: 'Modifier',
                onPressed: () { Navigator.pop(context); _configure(item, existing: group); },
              ),
            ),
        ]),
      ),
    );
  }
}

class _OptionDraft {
  const _OptionDraft({required this.name, required this.type, required this.isRequired,
    required this.max, required this.options});
  final String name;
  final String type;
  final bool isRequired;
  final int max;
  final String options;
}
