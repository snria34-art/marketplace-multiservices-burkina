import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';
import '../../restaurants/data/restaurant_repository.dart';

final sellerRestaurantRepositoryProvider =
    Provider<RestaurantRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : RestaurantRepository(client);
});

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
              value: selectedId,
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

  Future<void> _configure(Map<String, dynamic> item,
      {Map<String, dynamic>? existing, bool portionPreset = false}) async {
    final name = TextEditingController(
      text: existing?['name']?.toString() ?? (portionPreset ? 'Taille / portion' : ''),
    );
    final options = TextEditingController(
      text: existing != null
          ? _maps(existing['restaurant_menu_item_options'])
              .map((o) => '${o['name'] ?? ''}|${o['price_delta'] ?? 0}').join('\\n')
          : portionPreset ? 'Petit|0\\nMoyen|500\\nGrand|1000' : '',
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
                  value: type,
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
                    value: max,
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
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(shop['name']?.toString() ?? 'Restaurant',
          style: Theme.of(context).textTheme.titleLarge)),
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
            onPressed: () => _configure(item, portionPreset: true),
          ),
          IconButton(
            tooltip: 'Ajouter une personnalisation',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _configure(item),
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
