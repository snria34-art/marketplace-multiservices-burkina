import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';

class SellerOrdersPage extends ConsumerStatefulWidget {
  const SellerOrdersPage({super.key});

  @override
  ConsumerState<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends ConsumerState<SellerOrdersPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _updatingGroupId;

  String? _nextRestaurantStatus(String current) {
    switch (current) {
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

  String _restaurantActionLabel(String status) {
    switch (status) {
      case 'PAID':
        return 'Confirmer la commande';
      case 'CONFIRMED':
        return 'Commencer la préparation';
      case 'PREPARING':
        return 'Marquer la commande prête';
      case 'READY_FOR_PICKUP':
        return 'Confirmer le retrait par le client';
      default:
        return 'Statut mis à jour';
    }
  }

  Future<void> _advanceRestaurantOrder(Map<String, dynamic> group) async {
    final client = ref.read(marketplaceSellerClientProvider);
    final groupId = group['id']?.toString();
    final status = group['status']?.toString() ?? '';
    final fulfillment = group['fulfillment_method']?.toString() ?? 'DELIVERY';
    final confirmPickup =
        status == 'READY_FOR_PICKUP' && fulfillment == 'PICKUP';
    final nextStatus = _nextRestaurantStatus(status);
    if (client == null ||
        groupId == null ||
        (!confirmPickup && nextStatus == null) ||
        _updatingGroupId != null) {
      return;
    }

    setState(() => _updatingGroupId = groupId);
    try {
      if (confirmPickup) {
        await client.rpc(
          'confirm_restaurant_customer_pickup',
          params: {'p_order_group_id': groupId},
        );
      } else {
        await client.rpc(
          'transition_restaurant_order_group_status',
          params: {
            'p_order_group_id': groupId,
            'p_next_status': nextStatus,
            'p_note': null,
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirmPickup ? 'Retrait client confirmé.' : _restaurantActionLabel(status),
          ),
        ),
      );
      setState(() => _future = _load());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mise à jour de la commande impossible. Actualisez puis réessayez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingGroupId = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(marketplaceSellerClientProvider);
    final user = client?.auth.currentUser;

    if (client == null || user == null) return const [];

    final sellerRows = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);

    if ((sellerRows as List).isEmpty) return const [];

    final sellerId = (sellerRows.first as Map)['id'].toString();

    final shopRows = await client
        .from('shops')
        .select('id,name')
        .eq('seller_id', sellerId);

    final shopIds = (shopRows as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .toList();

    if (shopIds.isEmpty) return const [];

    final groups = await client
        .from('order_groups')
        .select(
          'id,order_id,shop_id,status,subtotal,created_at,fulfillment_method,fulfillment_instructions,pickup_location,shops(name),order_items(product_name,quantity,unit_price,total_price,restaurant_customizations)',
        )
        .inFilter('shop_id', shopIds)
        .order('created_at', ascending: false)
        .limit(200);

    final rawFulfillmentDetails =
        await client.rpc('get_seller_restaurant_order_fulfillment_details');
    final fulfillmentDetails = <String, Map<String, dynamic>>{};
    if (rawFulfillmentDetails is List) {
      for (final raw in rawFulfillmentDetails) {
        if (raw is Map) {
          final detail = Map<String, dynamic>.from(raw);
          final groupId = detail['order_group_id']?.toString();
          if (groupId != null && groupId.isNotEmpty) {
            fulfillmentDetails[groupId] = detail;
          }
        }
      }
    }

    return (groups as List).map((row) {
      final group = Map<String, dynamic>.from(row as Map);
      final detail = fulfillmentDetails[group['id']?.toString()];
      group['restaurant_fulfillment'] = detail;
      return group;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(marketplaceSellerClientProvider)?.auth.currentUser != null;

    if (!signedIn) {
      return const Scaffold(
        body: Center(
          child: Text('Connectez-vous à votre compte vendeur.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes vendeur'),
        actions: [
          IconButton(
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
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Impossible de charger les commandes. Vérifiez votre connexion puis réessayez.',
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

          final groups =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (groups.isEmpty) {
            return const Center(
              child: Text('Aucune commande pour vos boutiques.'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final group = groups[index];
                final shop = group['shops'] is Map
                    ? Map<String, dynamic>.from(group['shops'] as Map)
                    : const <String, dynamic>{};
                final restaurantFulfillment = group['restaurant_fulfillment'];
                final isRestaurant = restaurantFulfillment is Map;
                final status = group['status']?.toString() ?? '';
                final rawPickup = group['pickup_location'];
                final pickup = rawPickup is Map
                    ? Map<String, dynamic>.from(rawPickup)
                    : const <String, dynamic>{};
                final restaurantDetails = restaurantFulfillment is Map
                    ? Map<String, dynamic>.from(restaurantFulfillment)
                    : const <String, dynamic>{};
                final rawDeliveryAddress = restaurantDetails['delivery_address'];
                final deliveryAddress = rawDeliveryAddress is Map
                    ? Map<String, dynamic>.from(rawDeliveryAddress)
                    : const <String, dynamic>{};
                final fulfillment = group['fulfillment_method']?.toString() ?? 'DELIVERY';
                final nextStatus = isRestaurant ? _nextRestaurantStatus(status) : null;
                final canConfirmPickup = isRestaurant &&
                    fulfillment == 'PICKUP' &&
                    status == 'READY_FOR_PICKUP';
                final instructions = group['fulfillment_instructions']?.toString().trim() ?? '';
                final updating = _updatingGroupId == group['id']?.toString();
                final rawItems = group['order_items'];
                final items = rawItems is List ? rawItems : const [];

                return Card(
                  child: ExpansionTile(
                    title: Text(
                      shop['name']?.toString() ?? 'Boutique',
                    ),
                    subtitle: Text(
                      'Commande : ${group['order_id']?.toString() ?? '-'}\nÉtat : ${group['status']?.toString() ?? '-'} • Sous-total : ${formatXof(num.tryParse(group['subtotal']?.toString() ?? '0') ?? 0)}',
                    ),
                    children: [
                      if (isRestaurant)
                        ListTile(
                          leading: Icon(
                            fulfillment == 'PICKUP'
                                ? Icons.storefront_outlined
                                : Icons.delivery_dining_outlined,
                          ),
                          title: Text(
                            fulfillment == 'PICKUP'
                                ? 'Retrait au restaurant'
                                : 'Livraison au client',
                          ),
                          subtitle: Text(
                            fulfillment == 'PICKUP'
                                ? [
                                    if ((pickup['address']?.toString() ?? '').isNotEmpty)
                                      pickup['address'].toString(),
                                    if ((pickup['phone']?.toString() ?? '').isNotEmpty)
                                      'Téléphone : ${pickup['phone']}',
                                  ].join('\\n')
                                : [
                                    if ((deliveryAddress['recipient_name']?.toString() ?? '').isNotEmpty)
                                      deliveryAddress['recipient_name'].toString(),
                                    if ((deliveryAddress['phone']?.toString() ?? '').isNotEmpty)
                                      'Téléphone : ${deliveryAddress['phone']}',
                                    if ((deliveryAddress['address_line']?.toString() ?? '').isNotEmpty)
                                      deliveryAddress['address_line'].toString(),
                                    if ((deliveryAddress['city']?.toString() ?? '').isNotEmpty)
                                      deliveryAddress['city'].toString(),
                                  ].join('\\n'),
                          ),
                        ),
                      if (isRestaurant && instructions.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.notes_outlined),
                          title: const Text('Instructions du client'),
                          subtitle: Text(instructions),
                        ),
                      if (nextStatus != null || canConfirmPickup)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: updating || _updatingGroupId != null
                                  ? null
                                  : () => _advanceRestaurantOrder(group),
                              icon: updating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(_restaurantActionLabel(status)),
                            ),
                          ),
                        ),
                      for (final rawItem in items)
                        Builder(
                          builder: (context) {
                            final item =
                                Map<String, dynamic>.from(rawItem as Map);

                            final rawCustomizations = item['restaurant_customizations'];
                            final customizations = rawCustomizations is List
                                ? rawCustomizations.whereType<Map>().map((choice) =>
                                    Map<String, dynamic>.from(choice)).toList()
                                : const <Map<String, dynamic>>[];
                            final choicesLabel = customizations.map((choice) =>
                                '${choice['option_name']} (+${formatXof(num.tryParse(choice['price_delta']?.toString() ?? '0') ?? 0)})').join(', ');

                            return ListTile(
                              title: Text(
                                item['product_name']?.toString() ??
                                    'Produit',
                              ),
                              subtitle: Text(
                                'Qté : ${item['quantity']?.toString() ?? '0'} • ${formatXof(num.tryParse(item['unit_price']?.toString() ?? '0') ?? 0)}${choicesLabel.isEmpty ? '' : '\nChoix : $choicesLabel'}',
                              ),
                              trailing: Text(
                                formatXof(num.tryParse(item['total_price']?.toString() ?? '0') ?? 0),
                              ),
                            );
                          },
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
