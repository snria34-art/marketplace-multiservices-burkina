import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/restaurant_providers.dart';
import '../data/restaurant_repository.dart';

class SellerRestaurantPage extends ConsumerStatefulWidget {
  const SellerRestaurantPage({super.key});

  @override
  ConsumerState<SellerRestaurantPage> createState() =>
      _SellerRestaurantPageState();
}

class _SellerRestaurantPageState extends ConsumerState<SellerRestaurantPage> {
  late Future<List<Map<String, dynamic>>> _restaurantsFuture;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  RestaurantRepository? get _repository =>
      ref.read(restaurantRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _restaurantsFuture = _loadRestaurants();
    _ordersFuture = _loadOrders();
  }

  Future<List<Map<String, dynamic>>> _loadRestaurants() {
    return _repository?.managedRestaurants() ?? Future.value(const []);
  }

  Future<List<Map<String, dynamic>>> _loadOrders() {
    return _repository?.restaurantOrders() ?? Future.value(const []);
  }

  void _refresh() {
    setState(() {
      _restaurantsFuture = _loadRestaurants();
      _ordersFuture = _loadOrders();
    });
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _createProfile(Map<String, dynamic> shop) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.createRestaurantProfile(shop['id'].toString());
      if (!mounted) return;
      _refresh();
      _message('Profil restaurant créé. Complétez ses paramètres et son menu.');
    } catch (_) {
      _message('Création impossible. Vérifiez que cette boutique vous appartient.');
    }
  }

  Future<void> _editSettings(Map<String, dynamic> profile) async {
    final repository = _repository;
    if (repository == null) return;

    final cuisines = TextEditingController(
      text: (profile['cuisine_types'] is List
              ? (profile['cuisine_types'] as List).join(', ')
              : '')
          .toString(),
    );
    final preparation = TextEditingController(
      text: profile['preparation_time_min']?.toString() ?? '25',
    );
    final minimum = TextEditingController(
      text: profile['minimum_order_amount']?.toString() ?? '0',
    );
    final hours = TextEditingController(
      text: profile['opening_hours']?.toString() ?? '',
    );

    var delivery = profile['delivery_available'] == true;
    var accepting = profile['accepting_orders'] != false;

    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Paramètres du restaurant'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: cuisines,
                    decoration: const InputDecoration(
                      labelText: 'Types de cuisine',
                      hintText: 'Burkinabè, africaine, grillades…',
                      helperText: 'Séparez les cuisines par des virgules.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: preparation,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Temps moyen de préparation',
                      suffixText: 'minutes',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: minimum,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Commande minimum',
                      suffixText: 'XOF',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: hours,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Horaires d’ouverture',
                      hintText: 'Lun-Sam : 08:00-22:00 ; Dim : 10:00-20:00',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Accepter les commandes'),
                    value: accepting,
                    onChanged: (value) =>
                        setDialogState(() => accepting = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Livraison disponible'),
                    value: delivery,
                    onChanged: (value) =>
                        setDialogState(() => delivery = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'cuisines': cuisines.text,
                'preparation': preparation.text,
                'minimum': minimum.text,
                'hours': hours.text,
                'delivery': delivery,
                'accepting': accepting,
              }),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    cuisines.dispose();
    preparation.dispose();
    minimum.dispose();
    hours.dispose();

    if (!mounted || values == null) return;

    final preparationTime =
        int.tryParse(values['preparation']?.toString().trim() ?? '');
    final minimumAmount =
        num.tryParse(values['minimum']?.toString().trim() ?? '');
    if (preparationTime == null ||
        preparationTime < 0 ||
        preparationTime > 1440 ||
        minimumAmount == null ||
        minimumAmount < 0) {
      _message('Vérifiez le temps de préparation et le montant minimum.');
      return;
    }

    final cuisineTypes = values['cuisines']
        .toString()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    try {
      await repository.updateRestaurantProfile(
        profileId: profile['id'].toString(),
        cuisineTypes: cuisineTypes,
        preparationTimeMin: preparationTime,
        deliveryAvailable: values['delivery'] == true,
        acceptingOrders: values['accepting'] == true,
        pickupAvailable: profile['pickup_available'] == true,
        minimumOrderAmount: minimumAmount,
        openingHours: values['hours'].toString().trim(),
      );
      if (!mounted) return;
      _refresh();
      _message('Paramètres du restaurant enregistrés.');
    } catch (_) {
      _message('Enregistrement refusé. Vérifiez votre connexion et réessayez.');
    }
  }

  Future<void> _createMenu(String restaurantId) async {
    final repository = _repository;
    if (repository == null) return;
    final name = TextEditingController();
    final description = TextEditingController();

    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouveau menu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom du menu'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'name': name.text.trim(),
              'description': description.text.trim(),
            }),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    name.dispose();
    description.dispose();
    if (!mounted || values == null) return;
    if ((values['name'] ?? '').isEmpty) {
      _message('Le nom du menu est obligatoire.');
      return;
    }

    try {
      await repository.createMenu(
        restaurantId: restaurantId,
        name: values['name']!,
        description: values['description'] ?? '',
      );
      if (!mounted) return;
      _refresh();
      _message('Menu créé.');
    } catch (_) {
      _message('Création du menu impossible. Réessayez.');
    }
  }

  Future<void> _addMenuItem({
    required String shopId,
    required String menuId,
  }) async {
    final repository = _repository;
    if (repository == null) return;

    try {
      final products = await repository.availableProducts(shopId);
      if (!mounted) return;
      if (products.isEmpty) {
        _message(
          'Aucun produit actif. Créez et faites valider vos plats dans « Produits » avant de les ajouter au menu.',
        );
        return;
      }

      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _AddRestaurantMenuItemDialog(products: products),
      );
      if (!mounted || values == null) return;

      final product = products.firstWhere(
        (item) => item['id'].toString() == values['product_id'].toString(),
      );
      await repository.addMenuItem(
        menuId: menuId,
        product: product,
      );
      if (!mounted) return;
      _refresh();
      _message('Plat ajouté au menu.');
    } catch (_) {
      _message('Ajout du plat impossible. Vérifiez les produits de la boutique.');
    }
  }

  Future<void> _deleteMenu(String menuId) async {
    final repository = _repository;
    if (repository == null) return;
    final confirmed = await _confirm(
      'Supprimer ce menu et ses plats ?',
    );
    if (!confirmed) return;
    try {
      await repository.deleteMenu(menuId);
      if (!mounted) return;
      _refresh();
      _message('Menu supprimé.');
    } catch (_) {
      _message('Suppression du menu impossible.');
    }
  }

  Future<void> _deleteMenuItem(String itemId) async {
    final repository = _repository;
    if (repository == null) return;
    final confirmed = await _confirm('Supprimer ce plat du menu ?');
    if (!confirmed) return;
    try {
      await repository.deleteMenuItem(itemId);
      if (!mounted) return;
      _refresh();
      _message('Plat retiré du menu.');
    } catch (_) {
      _message('Suppression du plat impossible.');
    }
  }

  Future<bool> _confirm(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _setMenuActive(
    Map<String, dynamic> menu,
    bool active,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.updateMenu(
        menuId: menu['id'].toString(),
        name: menu['name']?.toString() ?? 'Menu',
        description: menu['description']?.toString() ?? '',
        active: active,
      );
      if (!mounted) return;
      _refresh();
      _message(active ? 'Menu publié.' : 'Menu masqué aux clients.');
    } catch (_) {
      _message('État du menu non modifié.');
    }
  }

  Future<void> _setMenuItemActive(
    String itemId,
    bool active,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.setMenuItemActive(itemId: itemId, active: active);
      if (!mounted) return;
      _refresh();
    } catch (_) {
      _message('Disponibilité du plat non modifiée.');
    }
  }

  Future<void> _transitionOrder(
    String orderGroupId,
    String nextStatus,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.transitionOrder(
        orderGroupId: orderGroupId,
        nextStatus: nextStatus,
      );
      if (!mounted) return;
      setState(() => _ordersFuture = _loadOrders());
      _message('État de la commande mis à jour.');
    } catch (_) {
      _message(
        'Mise à jour refusée. Vérifiez que la migration restaurant a été appliquée et que cette commande appartient à votre restaurant.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace restaurateur'),
        actions: [
          IconButton(
            tooltip: 'Gérer les produits et photos',
            onPressed: () => context.push('/seller/products'),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await Future.wait([_restaurantsFuture, _ordersFuture]);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'Vos restaurants',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _restaurantsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _RetryCard(
                    message: 'Impossible de charger vos boutiques.',
                    onRetry: _refresh,
                  );
                }

                final entries =
                    snapshot.data ?? const <Map<String, dynamic>>[];
                if (entries.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Aucune boutique n’est associée à ce compte. Un profil vendeur et une boutique sont nécessaires pour ouvrir un restaurant.',
                      ),
                    ),
                  );
                }

                return Column(
                  children: entries.map((entry) {
                    final shop = Map<String, dynamic>.from(
                      entry['shop'] as Map,
                    );
                    final rawProfile = entry['profile'];
                    if (rawProfile is! Map) {
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(shop['name']?.toString() ?? 'Boutique'),
                          subtitle: Text(
                            'Cette boutique n’a pas encore de profil restaurant.',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () => _createProfile(shop),
                            child: const Text('Configurer'),
                          ),
                        ),
                      );
                    }

                    final profile =
                        Map<String, dynamic>.from(rawProfile);
                    final menus = (profile['restaurant_menus'] is List
                            ? profile['restaurant_menus'] as List
                            : const [])
                        .whereType<Map>()
                        .map((row) => Map<String, dynamic>.from(row))
                        .toList();
                    final status =
                        shop['verification_status']?.toString() ?? 'PENDING';
                    final shopStatus = shop['status']?.toString() ?? 'DRAFT';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  child: Icon(Icons.restaurant_outlined),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shop['name']?.toString() ?? 'Restaurant',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text('Boutique : $shopStatus • Vérification : $status'),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Paramètres du restaurant',
                                  onPressed: () => _editSettings(profile),
                                  icon: const Icon(Icons.settings_outlined),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cuisine : ${(profile['cuisine_types'] is List ? (profile['cuisine_types'] as List).join(', ') : '').toString().isEmpty ? 'À renseigner' : (profile['cuisine_types'] as List).join(', ')}',
                            ),
                            Text(
                              'Préparation : ${profile['preparation_time_min'] ?? 25} min • Livraison : ${profile['delivery_available'] == true ? 'Oui' : 'Non'}',
                            ),
                            Text(
                              profile['accepting_orders'] == false
                                  ? 'Commandes suspendues'
                                  : 'Commandes acceptées',
                              style: TextStyle(
                                color: profile['accepting_orders'] == false
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Menus (${menus.length})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _createMenu(
                                    profile['id'].toString(),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Ajouter un menu'),
                                ),
                              ],
                            ),
                            if (menus.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Ajoutez un menu pour commencer.'),
                              ),
                            for (final menu in menus)
                              _RestaurantMenuCard(
                                menu: menu,
                                onMenuActiveChanged: (active) =>
                                    _setMenuActive(menu, active),
                                onAddItem: () => _addMenuItem(
                                  shopId: shop['id'].toString(),
                                  menuId: menu['id'].toString(),
                                ),
                                onDelete: () =>
                                    _deleteMenu(menu['id'].toString()),
                                onDeleteItem: _deleteMenuItem,
                                onItemActiveChanged: _setMenuItemActive,
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    context.push('/seller/products'),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Produits et photos'),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/seller/shop'),
                                icon: const Icon(Icons.storefront_outlined),
                                label: const Text('Informations et photos de la boutique'),
                              ),
                            ),
                            if (shopStatus != 'ACTIVE' || status != 'VERIFIED')
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Le restaurant sera visible aux clients après activation et vérification de la boutique par l’administration.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Commandes restaurant',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser les commandes',
                  onPressed: () =>
                      setState(() => _ordersFuture = _loadOrders()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Confirmez les commandes payées, lancez la préparation puis signalez lorsqu’elles sont prêtes.',
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _RetryCard(
                    message: 'Impossible de charger les commandes.',
                    onRetry: () =>
                        setState(() => _ordersFuture = _loadOrders()),
                  );
                }

                final orders =
                    snapshot.data ?? const <Map<String, dynamic>>[];
                if (orders.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Aucune commande restaurant pour le moment.'),
                    ),
                  );
                }

                return Column(
                  children: orders
                      .map(
                        (order) => _RestaurantOrderCard(
                          order: order,
                          onTransition: _transitionOrder,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantMenuCard extends StatelessWidget {
  const _RestaurantMenuCard({
    required this.menu,
    required this.onMenuActiveChanged,
    required this.onAddItem,
    required this.onDelete,
    required this.onDeleteItem,
    required this.onItemActiveChanged,
  });

  final Map<String, dynamic> menu;
  final ValueChanged<bool> onMenuActiveChanged;
  final VoidCallback onAddItem;
  final VoidCallback onDelete;
  final Future<void> Function(String) onDeleteItem;
  final Future<void> Function(String, bool) onItemActiveChanged;

  @override
  Widget build(BuildContext context) {
    final rawItems = menu['restaurant_menu_items'];
    final items = rawItems is List ? rawItems.whereType<Map>().toList() : const [];

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            title: Text(menu['name']?.toString() ?? 'Menu'),
            subtitle: Text(menu['description']?.toString() ?? ''),
            trailing: Wrap(
              spacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Switch(
                  value: menu['active'] == true,
                  onChanged: onMenuActiveChanged,
                ),
                IconButton(
                  tooltip: 'Ajouter un plat',
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                IconButton(
                  tooltip: 'Supprimer le menu',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Aucun plat dans ce menu.'),
            )
          else
            for (final rawItem in items)
              Builder(
                builder: (context) {
                  final item = Map<String, dynamic>.from(rawItem);
                  final itemId = item['id'].toString();
                  return SwitchListTile(
                    value: item['active'] == true,
                    onChanged: (value) =>
                        onItemActiveChanged(itemId, value),
                    title: Text(item['name']?.toString() ?? 'Plat'),
                    subtitle: Text(
                      '${item['price']?.toString() ?? '0'} XOF'
                      '${item['product_id'] == null ? ' • Produit non lié' : ''}',
                    ),
                    secondary: IconButton(
                      tooltip: 'Retirer du menu',
                      onPressed: () => onDeleteItem(itemId),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _RestaurantOrderCard extends StatelessWidget {
  const _RestaurantOrderCard({
    required this.order,
    required this.onTransition,
  });

  final Map<String, dynamic> order;
  final Future<void> Function(String, String) onTransition;

  String? get _nextStatus {
    switch (order['status']?.toString()) {
      case 'PAID':
        return 'CONFIRMED';
      case 'CONFIRMED':
        return 'PREPARING';
      case 'PREPARING':
        return 'READY_FOR_PICKUP';
      default:
        return null;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'PAID':
        return 'Payée — à confirmer';
      case 'CONFIRMED':
        return 'Confirmée';
      case 'PREPARING':
        return 'En préparation';
      case 'READY_FOR_PICKUP':
        return 'Prête';
      case 'IN_TRANSIT':
        return 'En livraison';
      case 'DELIVERED':
        return 'Livrée';
      case 'CANCELLED':
        return 'Annulée';
      default:
        return status ?? 'État inconnu';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = order['shops'] is Map
        ? Map<String, dynamic>.from(order['shops'] as Map)
        : const <String, dynamic>{};
    final rawItems = order['order_items'];
    final items = rawItems is List ? rawItems : const [];
    final orderGroupId = order['id'].toString();
    final nextStatus = _nextStatus;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(shop['name']?.toString() ?? 'Restaurant'),
        subtitle: Text(
          'Commande ${order['order_id']?.toString() ?? '-'}'
          ' • ${_statusLabel(order['status']?.toString())}'
          ' • ${order['subtotal']?.toString() ?? '0'} XOF',
        ),
        children: [
          for (final rawItem in items)
            Builder(
              builder: (context) {
                final item = Map<String, dynamic>.from(rawItem as Map);
                return ListTile(
                  dense: true,
                  title: Text(item['product_name']?.toString() ?? 'Plat'),
                  subtitle: Text(
                    'Qté : ${item['quantity']?.toString() ?? '0'}'
                    ' • ${item['unit_price']?.toString() ?? '0'} XOF',
                  ),
                  trailing: Text(
                    '${item['total_price']?.toString() ?? '0'} XOF',
                  ),
                );
              },
            ),
          if (nextStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => onTransition(orderGroupId, nextStatus),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    nextStatus == 'CONFIRMED'
                        ? 'Confirmer la commande'
                        : nextStatus == 'PREPARING'
                            ? 'Commencer la préparation'
                            : 'Signaler la commande prête',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddRestaurantMenuItemDialog extends StatefulWidget {
  const _AddRestaurantMenuItemDialog({required this.products});

  final List<Map<String, dynamic>> products;

  @override
  State<_AddRestaurantMenuItemDialog> createState() =>
      _AddRestaurantMenuItemDialogState();
}

class _AddRestaurantMenuItemDialogState
    extends State<_AddRestaurantMenuItemDialog> {
  late String _productId;

  @override
  void initState() {
    super.initState();
    _productId = widget.products.first['id'].toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un plat'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Produit actif'),
            items: [
              for (final product in widget.products)
                DropdownMenuItem(
                  value: product['id'].toString(),
                  child: Text(
                    product['name']?.toString() ?? 'Produit',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final product = widget.products.firstWhere(
                (item) => item['id'].toString() == value,
              );
              setState(() => _productId = value);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Le prix du plat est repris du catalogue pour garantir le même montant dans le panier et à la commande.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'product_id': _productId,
          }),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(message),
        trailing: IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}
