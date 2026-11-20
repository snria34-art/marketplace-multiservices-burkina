import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/group_buy_repository.dart';
import 'group_buy_countdown.dart';

final groupBuyRepositoryProvider = Provider<GroupBuyRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : GroupBuyRepository(client);
});

class GroupBuyPage extends ConsumerStatefulWidget {
  const GroupBuyPage({super.key});

  @override
  ConsumerState<GroupBuyPage> createState() => _GroupBuyPageState();
}

class _GroupBuyPageState extends ConsumerState<GroupBuyPage> {
  late Future<List<Map<String, dynamic>>> future;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    return ref.read(groupBuyRepositoryProvider)?.active() ?? const [];
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  Future<void> _join(Map<String, dynamic> group) async {
    final repository = ref.read(groupBuyRepositoryProvider);
    final client = ref.read(supabaseProvider);

    if (repository == null || client?.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour rejoindre un achat groupé.'),
        ),
      );
      return;
    }
    if (_joining) return;

    setState(() => _joining = true);
    try {
      await repository.join(groupBuyId: group['id'].toString());
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Participation enregistrée.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('group_buy_capacity_exceeded')
          ? 'Les dernières places ont déjà été prises.'
          : error.toString().contains('group_buy_unavailable')
              ? 'Ce regroupage est terminé ou n’est plus disponible.'
              : 'Impossible de rejoindre le regroupage. Vérifiez votre connexion et réessayez.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  DateTime? _date(dynamic value) {
    final raw = value?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achats groupés'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Actualiser les regroupages',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
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
                    const Icon(Icons.wifi_off_outlined, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'Impossible de charger les achats groupés.',
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

          final groups = snapshot.data ?? const <Map<String, dynamic>>[];
          if (groups.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  Icon(Icons.groups_outlined, size: 52),
                  SizedBox(height: 12),
                  Center(child: Text('Aucun achat groupé actif.')),
                  SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Les nouveaux regroupages apparaîtront ici.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final group = groups[index];
                final product = group['products'] is Map
                    ? Map<String, dynamic>.from(group['products'] as Map)
                    : const <String, dynamic>{};
                final target = int.tryParse(
                      group['target_quantity']?.toString() ?? '',
                    ) ??
                    0;
                final current = int.tryParse(
                      group['current_quantity']?.toString() ?? '',
                    ) ??
                    0;
                final progress = target <= 0
                    ? 0.0
                    : (current / target).clamp(0.0, 1.0);
                final startsAt = _date(group['starts_at']);
                final endsAt = _date(group['ends_at']);
                final full = target > 0 && current >= target;
                final productName =
                    product['name']?.toString() ??
                    group['title']?.toString() ??
                    'Achat groupé';

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
                            CircleAvatar(
                              radius: 23,
                              child: Icon(
                                full ? Icons.check_circle_outline : Icons.groups_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    productName,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  if ((product['description']?.toString() ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        product['description'].toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if ((group['title']?.toString() ?? '').isNotEmpty &&
                                      group['title'].toString() != productName)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        group['title'].toString(),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (startsAt != null && endsAt != null)
                          GroupBuyCountdown(
                            startsAt: startsAt,
                            endsAt: endsAt,
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$current / $target participants',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            Text(
                              '${group['group_price']?.toString() ?? '0'} XOF',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: progress,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _joining || full
                                ? null
                                : () => _join(group),
                            icon: _joining
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.group_add_outlined),
                            label: Text(
                              full ? 'Objectif atteint' : 'Rejoindre le regroupage',
                            ),
                          ),
                        ),
                      ],
                    ),
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
