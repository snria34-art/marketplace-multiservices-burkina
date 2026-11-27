import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';

enum _OrderFilter {
  all,
  payment,
  preparing,
  shipping,
  receive,
  review,
  disputes,
  completed,
}

const _orderFilters = <_OrderFilter>[
  _OrderFilter.all,
  _OrderFilter.payment,
  _OrderFilter.preparing,
  _OrderFilter.shipping,
  _OrderFilter.receive,
  _OrderFilter.review,
  _OrderFilter.disputes,
  _OrderFilter.completed,
];

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late Future<_OrdersPayload> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OrdersPayload> _load() async {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return const _OrdersPayload.empty();

    final orders = await repo.orders(limit: 100);
    final orderIds = orders
        .map((order) => order['order_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final groups = await repo.orderGroupsForOrders(orderIds);

    final groupsByOrder = <String, List<Map<String, dynamic>>>{};
    for (final group in groups) {
      final orderId = group['order_id']?.toString() ?? '';
      if (orderId.isEmpty) continue;
      groupsByOrder.putIfAbsent(orderId, () => []).add(group);
    }

    return _OrdersPayload(
      orders: orders,
      groupsByOrder: groupsByOrder,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _confirmReceipt(String orderId) async {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return;

    try {
      await repo.confirmReceipt(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Réception confirmée. Vous pouvez maintenant évaluer vos articles.'),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de confirmer la réception : $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseProvider);

    if (client?.auth.currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Connectez-vous pour voir vos commandes.'),
        ),
      );
    }

    return DefaultTabController(
      length: _orderFilters.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes commandes'),
          actions: [
            IconButton(
              tooltip: 'Actualiser les commandes',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<_OrdersPayload>(
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
                      const SizedBox(height: 12),
                      const Text(
                        'Impossible de charger vos commandes.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final payload = snapshot.data ?? const _OrdersPayload.empty();

            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: _orderFilters.map((filter) {
                      final count = payload.orders
                          .where((order) => _matchesFilter(order, filter))
                          .length;
                      return Tab(
                        text: '${_filterLabel(filter)} ($count)',
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: _orderFilters.map((filter) {
                      final filteredOrders = payload.orders
                          .where((order) => _matchesFilter(order, filter))
                          .toList();

                      return _OrdersList(
                        orders: filteredOrders,
                        groupsByOrder: payload.groupsByOrder,
                        filter: filter,
                        onRefresh: _refresh,
                        onConfirmReceived: _confirmReceipt,
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _matchesFilter(
    Map<String, dynamic> order,
    _OrderFilter filter,
  ) {
    if (filter == _OrderFilter.all) return true;

    final status = order['status']?.toString().toUpperCase() ?? '';
    final completedAt = order['completed_at'];
    final deadline = DateTime.tryParse(
      order['review_deadline_at']?.toString() ?? '',
    );
    final now = DateTime.now();

    switch (filter) {
      case _OrderFilter.all:
        return true;
      case _OrderFilter.payment:
        return status == 'PENDING_PAYMENT';
      case _OrderFilter.preparing:
        return const {
          'PAID',
          'CONFIRMED',
          'PREPARING',
        }.contains(status);
      case _OrderFilter.shipping:
        return status == 'IN_TRANSIT';
      case _OrderFilter.receive:
        return const {
              'READY_FOR_PICKUP',
              'PARTIALLY_FULFILLED',
            }.contains(status) ||
            (status == 'DELIVERED' &&
                completedAt == null &&
                deadline != null &&
                deadline.isAfter(now));
      case _OrderFilter.review:
        return status == 'DELIVERED' &&
            completedAt != null &&
            deadline != null &&
            deadline.isAfter(now);
      case _OrderFilter.disputes:
        return status == 'DISPUTED';
      case _OrderFilter.completed:
        return status == 'CANCELLED' ||
            status == 'REFUNDED' ||
            (status == 'DELIVERED' &&
                (deadline == null || !deadline.isAfter(now)));
    }
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.groupsByOrder,
    required this.filter,
    required this.onRefresh,
    required this.onConfirmReceived,
  });

  final List<Map<String, dynamic>> orders;
  final Map<String, List<Map<String, dynamic>>> groupsByOrder;
  final _OrderFilter filter;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String orderId) onConfirmReceived;

  @override
  Widget build(BuildContext context) {
    final showRecommendations = filter == _OrderFilter.all;
    final showEmptyMessage = orders.isEmpty;
    final itemCount = orders.length +
        (showEmptyMessage ? 1 : 0) +
        (showRecommendations ? 1 : 0);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (showEmptyMessage && index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _emptyMessage(filter),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          final orderIndex = index - (showEmptyMessage ? 1 : 0);
          if (orderIndex >= 0 && orderIndex < orders.length) {
            final order = orders[orderIndex];
            final orderId = order['order_id']?.toString() ?? '';
            final groups = groupsByOrder[orderId] ??
                const <Map<String, dynamic>>[];

            return _OrderCard(
              order: order,
              groups: groups,
              filter: filter,
              onConfirmReceived: onConfirmReceived,
            );
          }

          return const _RecommendedProductsSection();
        },
      ),
    );
  }
}

class _RecommendedProductsSection extends ConsumerStatefulWidget {
  const _RecommendedProductsSection();

  @override
  ConsumerState<_RecommendedProductsSection> createState() =>
      _RecommendedProductsSectionState();
}

class _RecommendedProductsSectionState
    extends ConsumerState<_RecommendedProductsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final catalog = ref.read(catalogRepositoryProvider);
    if (catalog == null) return const [];
    return catalog.products(limit: 8);
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final productId = product['id']?.toString() ?? '';
    if (productId.isEmpty) return;

    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null) {
      if (mounted) context.push('/auth');
      return;
    }

    final cart = ref.read(cartRepositoryProvider);
    if (cart == null) return;

    try {
      await cart.addToCart(productId: productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit ajouté au panier.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d’ajouter ce produit : $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.hasError || products.isEmpty) {
          return const SizedBox.shrink();
        }

        final catalog = ref.read(catalogRepositoryProvider);
        if (catalog == null) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 28),
            Text(
              'À découvrir',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'D’autres articles disponibles sur Marketplace Burkina',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: products.map((product) {
                    final rawImages = product['product_images'];
                    final firstImage = rawImages is List &&
                            rawImages.isNotEmpty &&
                            rawImages.first is Map
                        ? Map<String, dynamic>.from(rawImages.first as Map)
                        : const <String, dynamic>{};
                    final storagePath =
                        firstImage['storage_path']?.toString();

                    return SizedBox(
                      width: cardWidth,
                      child: _RecommendedProductCard(
                        product: product,
                        imageUrl: storagePath == null
                            ? Future.value(null)
                            : catalog.productImageUrl(storagePath),
                        onAdd: () => _addToCart(product),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RecommendedProductCard extends StatelessWidget {
  const _RecommendedProductCard({
    required this.product,
    required this.imageUrl,
    required this.onAdd,
  });

  final Map<String, dynamic> product;
  final Future<String?> imageUrl;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final rawShop = product['shops'];
    final shop = rawShop is Map
        ? Map<String, dynamic>.from(rawShop)
        : const <String, dynamic>{};

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 116,
            child: FutureBuilder<String?>(
              future: imageUrl,
              builder: (context, snapshot) {
                final url = snapshot.data;
                if (url == null || url.isEmpty) {
                  return const Center(
                    child: Icon(Icons.image_outlined, size: 42),
                  );
                }
                return Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.image_not_supported_outlined, size: 42),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 3),
            child: Text(
              product['name']?.toString() ?? 'Article',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              '${product['price']?.toString() ?? '0'} XOF',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 2, 5, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shop['name']?.toString() ?? 'Boutique',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Ajouter au panier',
                  visualDensity: VisualDensity.compact,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.groups,
    required this.filter,
    required this.onConfirmReceived,
  });

  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> groups;
  final _OrderFilter filter;
  final Future<void> Function(String orderId) onConfirmReceived;

  @override
  Widget build(BuildContext context) {
    final orderId = order['order_id']?.toString() ?? '';
    final status = order['status']?.toString().toUpperCase() ?? '';
    final receiptConfirmed = order['completed_at'] != null;
    final reviewDeadline = DateTime.tryParse(
      order['review_deadline_at']?.toString() ?? '',
    );
    final reviewWindowOpen =
        reviewDeadline != null && reviewDeadline.isAfter(DateTime.now());
    final completed = status == 'CANCELLED' ||
        status == 'REFUNDED' ||
        (status == 'DELIVERED' && !reviewWindowOpen);
    final canConfirmReceipt = status == 'DELIVERED' &&
        !receiptConfirmed &&
        reviewWindowOpen;
    final cardStatus = status == 'DELIVERED' &&
            receiptConfirmed &&
            reviewWindowOpen
        ? 'Réception confirmée'
        : completed
            ? 'Terminée'
            : _statusLabel(status);
    final canTrack = !const {'PENDING_PAYMENT', 'CANCELLED', 'REFUNDED'}
        .contains(status);
    final amount = order['total']?.toString() ?? '0';
    final currency = order['currency']?.toString().trim() ?? 'XOF';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 22),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commande #${_shortId(orderId)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDate(order['created_at']?.toString()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      cardStatus,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (groups.isNotEmpty) ...[
              const Divider(height: 22),
              ...groups.map((group) => _OrderGroupSummary(group: group)),
            ],
            const Divider(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total payé / à payer',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '$amount $currency',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: orderId.isEmpty
                      ? null
                      : () => context.push('/orders/$orderId'),
                  icon: Icon(
                    filter == _OrderFilter.review
                        ? Icons.star_outline
                        : Icons.receipt_long_outlined,
                  ),
                  label: Text(
                    filter == _OrderFilter.review ? 'Évaluer' : 'Détails',
                  ),
                ),
                if (canConfirmReceipt)
                  FilledButton.icon(
                    onPressed: orderId.isEmpty
                        ? null
                        : () => onConfirmReceived(orderId),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmer la réception'),
                  ),
                if (canTrack)
                  FilledButton.tonalIcon(
                    onPressed: orderId.isEmpty
                        ? null
                        : () => context.push('/delivery/$orderId'),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Suivre la livraison'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderGroupSummary extends StatelessWidget {
  const _OrderGroupSummary({required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final shop = group['shops'];
    final shopName = shop is Map
        ? (shop['name']?.toString() ?? 'Boutique')
        : 'Boutique';
    final rawItems = group['order_items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().toList()
        : const <Map>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  shopName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                _statusLabel(group['status']?.toString().toUpperCase() ?? ''),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 25, bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item['product_name']?.toString() ?? 'Article',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('×${item['quantity']?.toString() ?? '1'}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OrdersPayload {
  const _OrdersPayload({
    required this.orders,
    required this.groupsByOrder,
  });

  const _OrdersPayload.empty()
      : orders = const [],
        groupsByOrder = const {};

  final List<Map<String, dynamic>> orders;
  final Map<String, List<Map<String, dynamic>>> groupsByOrder;
}

String _filterLabel(_OrderFilter filter) {
  switch (filter) {
    case _OrderFilter.all:
      return 'Toutes';
    case _OrderFilter.payment:
      return 'À payer';
    case _OrderFilter.preparing:
      return 'À préparer';
    case _OrderFilter.shipping:
      return 'En livraison';
    case _OrderFilter.receive:
      return 'À recevoir';
    case _OrderFilter.review:
      return 'À évaluer';
    case _OrderFilter.disputes:
      return 'Litiges';
    case _OrderFilter.completed:
      return 'Terminées';
  }
}

String _emptyMessage(_OrderFilter filter) {
  switch (filter) {
    case _OrderFilter.all:
      return 'Aucune commande pour le moment.';
    case _OrderFilter.payment:
      return 'Aucune commande en attente de paiement.';
    case _OrderFilter.preparing:
      return 'Aucune commande en préparation.';
    case _OrderFilter.shipping:
      return 'Aucune commande en cours de livraison.';
    case _OrderFilter.receive:
      return 'Aucune commande en attente de réception.';
    case _OrderFilter.review:
      return 'Aucune commande à évaluer pour le moment.';
    case _OrderFilter.disputes:
      return 'Aucune commande en litige.';
    case _OrderFilter.completed:
      return 'Aucune commande terminée.';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'PENDING_PAYMENT':
      return 'Paiement en attente';
    case 'PAID':
      return 'Paiement confirmé';
    case 'CONFIRMED':
      return 'Confirmée';
    case 'PREPARING':
      return 'En préparation';
    case 'READY_FOR_PICKUP':
      return 'Prête à être remise';
    case 'PARTIALLY_FULFILLED':
      return 'Traitement partiel';
    case 'IN_TRANSIT':
      return 'En livraison';
    case 'DELIVERED':
      return 'Livrée';
    case 'CANCELLED':
      return 'Annulée';
    case 'REFUNDED':
      return 'Remboursée';
    case 'DISPUTED':
      return 'En litige';
    default:
      return status.isEmpty ? 'Statut inconnu' : status.replaceAll('_', ' ');
  }
}

String _shortId(String id) {
  if (id.isEmpty) return '-';
  return id.length <= 8 ? id.toUpperCase() : id.substring(0, 8).toUpperCase();
}

String _formatDate(String? raw) {
  final parsed = DateTime.tryParse(raw ?? '');
  if (parsed == null) return 'Date non disponible';
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} à $hour:$minute';
}
