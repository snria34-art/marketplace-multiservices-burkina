import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return Future.value(const []);
    return repo.orders(limit: 50);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _statusLabel(String? raw, {bool completed = false}) {
    if (completed) return 'Commande terminée';
    switch (raw) {
      case 'PENDING_PAYMENT':
        return 'Paiement en attente';
      case 'PAID':
        return 'Paiement confirmé';
      case 'CONFIRMED':
        return 'Commande confirmée';
      case 'PREPARING':
        return 'En préparation';
      case 'READY_FOR_PICKUP':
        return 'Prête à être récupérée';
      case 'PARTIALLY_FULFILLED':
        return 'Partiellement traitée';
      case 'IN_TRANSIT':
        return 'En cours de livraison';
      case 'DELIVERED':
        return 'Livrée';
      case 'CANCELLED':
        return 'Annulée';
      case 'REFUNDED':
        return 'Remboursée';
      case 'DISPUTED':
        return 'En litige';
      default:
        return (raw ?? 'Statut inconnu').replaceAll('_', ' ');
    }
  }

  String _formatDate(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return 'Date indisponible';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} à $hour:$minute';
  }

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> orders,
    int tabIndex,
  ) {
    return orders.where((order) {
      final status = order['status']?.toString() ?? '';
      final completed = order['completed_at'] != null;

      switch (tabIndex) {
        case 1:
          return status == 'PENDING_PAYMENT';
        case 3:
          return const {'PAID', 'CONFIRMED', 'PREPARING'}.contains(status);
        case 4:
          return const {
            'READY_FOR_PICKUP',
            'PARTIALLY_FULFILLED',
            'IN_TRANSIT',
          }.contains(status);
        case 5:
          return status == 'DELIVERED' || completed;
        default:
          return true;
      }
    }).toList(growable: false);
  }

  Widget _ordersList(List<Map<String, dynamic>> orders) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: orders.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 110),
                Icon(Icons.receipt_long_outlined, size: 44),
                SizedBox(height: 12),
                Center(child: Text('Aucune commande dans cette catégorie.')),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'Les nouvelles commandes apparaîtront ici.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final order = orders[index];
                final status = order['status']?.toString();
                final completed = order['completed_at'] != null;
                final orderId = order['order_id']?.toString() ?? '';
                final shortId = orderId.length > 8
                    ? orderId.substring(0, 8).toUpperCase()
                    : orderId.toUpperCase();
                final amount = order['total']?.toString() ?? '0';
                final currency = order['currency']?.toString() ?? 'XOF';

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(Icons.receipt_long_outlined),
                    ),
                    title: Text(
                      shortId.isEmpty ? 'Commande' : 'Commande #$shortId',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        _statusLabel(status, completed: completed) +
                            '\n' +
                            _formatDate(order['created_at']),
                      ),
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$amount $currency',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: orderId.isNotEmpty
                        ? () => context.push('/orders/' + orderId)
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Widget _groupOrdersTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 28),
          const Icon(Icons.groups_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Achats groupés',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Les participations aux achats groupés sont suivies dans leur espace dédié. Vous pouvez y consulter les groupes ouverts et inviter des proches.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => context.push('/group-buy'),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Voir les achats groupés'),
          ),
        ],
      ),
    );
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
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes commandes'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Tout'),
              Tab(text: 'À payer'),
              Tab(text: 'Achats groupés'),
              Tab(text: 'À préparer'),
              Tab(text: 'À recevoir'),
              Tab(text: 'À évaluer'),
            ],
          ),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_outlined, size: 42),
                      const SizedBox(height: 8),
                      const Text(
                        'Impossible de charger les commandes. Réessayez.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
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

            final orders =
                snapshot.data ?? const <Map<String, dynamic>>[];

            return TabBarView(
              children: [
                _ordersList(_filter(orders, 0)),
                _ordersList(_filter(orders, 1)),
                _groupOrdersTab(),
                _ordersList(_filter(orders, 3)),
                _ordersList(_filter(orders, 4)),
                _ordersList(_filter(orders, 5)),
              ],
            );
          },
        ),
      ),
    );
  }
}
