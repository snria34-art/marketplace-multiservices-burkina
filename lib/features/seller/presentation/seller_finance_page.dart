import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/seller_repository.dart';

final sellerFinanceRepositoryProvider = Provider<SellerRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SellerRepository(client);
});

class SellerFinancePage extends ConsumerStatefulWidget {
  const SellerFinancePage({super.key});

  @override
  ConsumerState<SellerFinancePage> createState() => _SellerFinancePageState();
}

class _SellerFinancePageState extends ConsumerState<SellerFinancePage> {
  late Future<_FinanceSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _requestPayout() async {
    final repo = ref.read(sellerFinanceRepositoryProvider);
    if (repo == null) return;

    final amountController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var provider = 'ORANGE_MONEY';
        var submitting = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Demander un retrait'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Montant en XOF',
                    helperText: 'Saisissez un montant entier disponible.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: provider,
                  decoration: const InputDecoration(
                    labelText: 'Moyen de paiement',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'ORANGE_MONEY',
                      child: Text('Orange Money'),
                    ),
                    DropdownMenuItem(
                      value: 'WAVE',
                      child: Text('Wave'),
                    ),
                    DropdownMenuItem(
                      value: 'MOOV_MONEY',
                      child: Text('Moov Money'),
                    ),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setDialogState(() => provider = value);
                          }
                        },
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final amount = num.tryParse(
                          amountController.text.trim(),
                        );
                        if (amount == null ||
                            amount <= 0 ||
                            amount != amount.truncate()) {
                          setDialogState(() {
                            error = 'Entrez un montant XOF entier valide.';
                          });
                          return;
                        }

                        setDialogState(() {
                          submitting = true;
                          error = null;
                        });
                        try {
                          final sellerId = await repo.sellerId();
                          if (sellerId == null) {
                            throw StateError('Compte vendeur introuvable.');
                          }
                          await repo.requestPayout(
                            sellerId: sellerId,
                            amount: amount,
                            provider: provider,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          if (!mounted) return;
                          setState(() => _future = _load());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Demande de retrait enregistrée.',
                              ),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() {
                            submitting = false;
                            error = _payoutErrorMessage(e);
                          });
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmer'),
              ),
            ],
          ),
        );
      },
    );
    amountController.dispose();
  }

  String _payoutErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('seller_payout_blocked_by_refund_reconciliation')) {
      return 'Retrait bloqué : un remboursement de commande doit encore être rapproché.';
    }
    if (message.contains('insufficient_seller_balance')) {
      return 'Solde disponible insuffisant pour ce montant.';
    }
    if (message.contains('seller_not_eligible')) {
      return 'Le compte vendeur doit être vérifié pour demander un retrait.';
    }
    if (message.contains('amount_invalid')) {
      return 'Le montant demandé est invalide.';
    }
    return 'Demande impossible pour le moment. Vérifiez votre solde et réessayez.';
  }

  Future<_FinanceSnapshot> _load() async {
    final repo = ref.read(sellerFinanceRepositoryProvider);
    if (repo == null) {
      throw StateError('Authentification requise.');
    }
    final sellerId = await repo.sellerId();
    if (sellerId == null) {
      throw StateError('Compte vendeur introuvable.');
    }

    final results = await Future.wait<dynamic>([
      repo.balance(sellerId),
      repo.payouts(sellerId),
      repo.client
          .from('seller_ledger')
          .select('entry_type,amount,currency,reference_id,created_at')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false)
          .limit(100),
    ]);
    final ledger = results[2] as List;

    return _FinanceSnapshot(
      balance: results[0] as num,
      payouts: results[1] as List<Map<String, dynamic>>,
      ledger: ledger
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance vendeur'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_FinanceSnapshot>(
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
                      'Impossible de charger les informations financières. Réessayez.',
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

          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Solde'),
                  trailing: Text(
                    data.balance.toString() + ' XOF',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: data.balance > 0 ? _requestPayout : null,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Demander un retrait'),
              ),
              const SizedBox(height: 12),
              Text(
                'Demandes de paiement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (data.payouts.isEmpty)
                const Text('Aucune demande de paiement.')
              else
                ...data.payouts.map(
                  (row) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(
                        (row['amount']?.toString() ?? '0') +
                            ' ' +
                            (row['currency']?.toString() ?? 'XOF'),
                      ),
                      subtitle: Text(
                        (row['provider']?.toString() ?? '-') +
                            ' • ' +
                            (row['status']?.toString() ?? '-'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Journal financier',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...data.ledger.map(
                (row) => ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(row['entry_type']?.toString() ?? '-'),
                  subtitle: Text(row['created_at']?.toString() ?? '-'),
                  trailing: Text(
                    (row['amount']?.toString() ?? '0') +
                        ' ' +
                        (row['currency']?.toString() ?? 'XOF'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FinanceSnapshot {
  const _FinanceSnapshot({
    required this.balance,
    required this.payouts,
    required this.ledger,
  });

  final num balance;
  final List<Map<String, dynamic>> payouts;
  final List<Map<String, dynamic>> ledger;
}
