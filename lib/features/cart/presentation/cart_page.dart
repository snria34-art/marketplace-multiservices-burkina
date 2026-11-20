import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() {
    final repo = ref.read(cartRepositoryProvider);
    if (repo == null) return Future.value(null);
    return repo.activeCart();
  }

  Future<void> _changeQuantity(
    Map<String, dynamic> item,
    int quantity,
  ) async {
    final repo = ref.read(cartRepositoryProvider);
    if (repo == null) return;

    try {
      if (quantity == 0) {
        await repo.remove(item['id'].toString());
      } else {
        await repo.setQuantity(
          cartItemId: item['id'].toString(),
          quantity: quantity,
        );
      }

      if (!mounted) return;
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeBackendErrorMessage(error, fallback: 'Mise à jour du panier impossible. Réessayez.'),
          ),
        ),
      );
    }
  }

  double _total(Map<String, dynamic> cart) {
    final items = cart['items'];
    if (items is! List) return 0;

    return items.fold<double>(0, (sum, raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final price = double.tryParse(
            (item['restaurant_unit_total'] ?? item['unit_price'])?.toString() ?? '',
          ) ?? 0;
      final quantity =
          int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      return sum + (price * quantity);
    });
  }


  List<String> _customizationLabels(Map<String, dynamic> item) {
    final rawMenu = item['restaurant_menu_items'];
    if (rawMenu is! Map) return const [];
    final menu = Map<String, dynamic>.from(rawMenu);
    final rawSelections = item['restaurant_selections'];
    if (rawSelections is! Map) return const [];
    final labels = <String>[];
    final rawGroups = menu['restaurant_menu_item_option_groups'];
    if (rawGroups is! List) return labels;

    for (final rawGroup in rawGroups) {
      if (rawGroup is! Map) continue;
      final group = Map<String, dynamic>.from(rawGroup);
      final groupId = group['id']?.toString() ?? '';
      final selected = rawSelections[groupId];
      if (selected is! List || selected.isEmpty) continue;
      final selectedIds = selected.map((id) => id.toString()).toSet();
      final rawOptions = group['restaurant_menu_item_options'];
      if (rawOptions is! List) continue;
      final names = <String>[];
      for (final rawOption in rawOptions) {
        if (rawOption is! Map) continue;
        final option = Map<String, dynamic>.from(rawOption);
        if (selectedIds.contains(option['id']?.toString())) {
          names.add(option['name']?.toString() ?? 'Option');
        }
      }
      if (names.isNotEmpty) {
        labels.add('${group['name']?.toString() ?? 'Choix'} : ${names.join(', ')}');
      }
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseProvider);
    final signedIn = client?.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon panier'),
        actions: [
          IconButton(
            tooltip: 'Mes commandes',
            onPressed: () => context.push('/orders'),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: !signedIn
          ? Center(
              child: FilledButton(
                onPressed: () => context.push('/auth'),
                child: const Text('Se connecter'),
              ),
            )
          : FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Impossible de charger le panier. Réessayez.',
                    ),
                  );
                }

                final cart = snapshot.data;
                final rawItems = cart?['items'];
                final items = rawItems is List ? rawItems : const [];

                if (items.isEmpty) {
                  return const Center(
                    child: Text('Votre panier est vide.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length + 2,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    if (index == items.length) {
                      return ListTile(
                        title: const Text('Sous-total'),
                        trailing: Text(
                          formatXof(_total(cart!)),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    if (index == items.length + 1) {
                      final hasInvalidCustomization = items.any((raw) =>
                          raw is Map && raw['customization_invalid'] == true);
                      return FilledButton.icon(
                        onPressed: hasInvalidCustomization
                            ? null
                            : () => context.push('/checkout/' + cart!['id'].toString()),
                        icon: const Icon(Icons.lock_outline),
                        label: Text(hasInvalidCustomization
                            ? 'Retirez les choix devenus indisponibles'
                            : 'Choisir la livraison et payer'),
                      );
                    }

                    final item =
                        Map<String, dynamic>.from(items[index] as Map);
                    final product = item['products'] is Map
                        ? Map<String, dynamic>.from(item['products'] as Map)
                        : const <String, dynamic>{};
                    final variant = item['product_variants'] is Map
                        ? Map<String, dynamic>.from(
                            item['product_variants'] as Map,
                          )
                        : const <String, dynamic>{};
                    final variantName = variant['name']?.toString().trim();
                    final quantity =
                        int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
                    final customizationLabels = _customizationLabels(item);
                    final customizationInvalid = item['customization_invalid'] == true;

                    return Card(
                      child: ListTile(
                        title: Text(
                          product['name']?.toString() ?? 'Produit',
                        ),
                        subtitle: Text(
                          [
                            if (variantName != null && variantName.isNotEmpty)
                              'Variante : ' + variantName,
                            if (customizationLabels.isNotEmpty)
                              'Choix : ' + customizationLabels.join(' • '),
                            if (customizationInvalid)
                              'Personnalisation modifiée par le restaurant : retirez cet article et ajoutez-le à nouveau.',
                            formatXof(num.tryParse((item['restaurant_unit_total'] ?? item['unit_price'] ?? '0').toString()) ?? 0) + ' / unité',
                          ].join('\n'),
                        ),
                        trailing: SizedBox(
                          width: 176,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Retirer du panier',
                                onPressed: () => _changeQuantity(item, 0),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _changeQuantity(item, quantity - 1),
                                icon: const Icon(Icons.remove),
                              ),
                              Text('$quantity'),
                              IconButton(
                                onPressed: () =>
                                    _changeQuantity(item, quantity + 1),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
