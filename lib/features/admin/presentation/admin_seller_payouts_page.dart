import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class AdminSellerPayoutsPage extends ConsumerStatefulWidget {
  const AdminSellerPayoutsPage({super.key});

  @override
  ConsumerState<AdminSellerPayoutsPage> createState() =>
      _AdminSellerPayoutsPageState();
}

class _AdminSellerPayoutsPageState
    extends ConsumerState<AdminSellerPayoutsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification requise.');
    }

    final rows = await client
        .from('seller_payouts')
        .select(
          'id,seller_id,amount,currency,provider,status,requested_at,paid_at,provider_reference',
        )
        .order('requested_at', ascending: false)
        .limit(100);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _changeStatus(
    Map<String, dynamic> payout, {
    required bool paid,
  }) async {
    final referenceController = TextEditingController();
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          paid ? 'Confirmer le paiement effectué' : 'Déclarer le retrait échoué',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${payout['amount']} ${payout['currency']} • ${payout['provider']}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: paid ? referenceController : reasonController,
              maxLength: paid ? 200 : 500,
              decoration: InputDecoration(
                labelText: paid
                    ? 'Référence réelle du prestataire'
                    : 'Motif de l’échec',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = (paid
                      ? referenceController.text
                      : reasonController.text)
                  .trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      paid
                          ? 'La référence du prestataire est obligatoire.'
                          : 'Le motif de l’échec est obligatoire.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    final reference = referenceController.text.trim();
    final reason = reasonController.text.trim();
    referenceController.dispose();
    reasonController.dispose();
    if (confirmed != true) return;

    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      if (paid) {
        await client.rpc(
          'admin_mark_seller_payout_paid',
          params: {
            'p_payout_id': payout['id'],
            'p_provider_reference': reference,
          },
        );
      } else {
        await client.rpc(
          'admin_mark_seller_payout_failed',
          params: {
            'p_payout_id': payout['id'],
            'p_reason': reason,
          },
        );
      }

      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paid
                ? 'Paiement du retrait enregistré.'
                : 'Échec enregistré et montant restitué au solde vendeur.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(safeBackendErrorMessage(error, fallback: 'Action sur le retrait vendeur refusée. Vérifiez son statut et les droits.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retraits vendeurs'),
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de charger les retraits vendeurs.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
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

          final payouts =
              snapshot.data ?? const <Map<String, dynamic>>[];
          if (payouts.isEmpty) {
            return const Center(child: Text('Aucune demande de retrait.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: payouts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final payout = payouts[index];
              final status = payout['status']?.toString() ?? 'UNKNOWN';
              final pending = status == 'PENDING';
              final sellerId = payout['seller_id']?.toString() ?? '-';
              final sellerLabel = sellerId.length > 12
                  ? '${sellerId.substring(0, 12)}…'
                  : sellerId;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${payout['amount']} ${payout['currency']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text('Vendeur : $sellerLabel'),
                      Text('Moyen : ${payout['provider']}'),
                      Text('Statut : $status'),
                      if (payout['requested_at'] != null)
                        Text('Demandé : ${payout['requested_at']}'),
                      if (payout['provider_reference'] != null)
                        Text('Référence : ${payout['provider_reference']}'),
                      if (pending) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  _changeStatus(payout, paid: true),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Paiement effectué'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _changeStatus(payout, paid: false),
                              icon: const Icon(Icons.error_outline),
                              label: const Text('Échec du retrait'),
                            ),
                          ],
                        ),
                      ],
                    ],
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
