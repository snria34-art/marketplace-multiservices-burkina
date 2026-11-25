import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class AdminReturnsPage extends ConsumerStatefulWidget {
  const AdminReturnsPage({super.key});

  @override
  ConsumerState<AdminReturnsPage> createState() => _AdminReturnsPageState();
}

class _AdminReturnsPageState extends ConsumerState<AdminReturnsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(marketplaceAdminClientProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }
    final result = await client.rpc('admin_list_returns');
    if (result is! List) return const [];
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _transition(
    Map<String, dynamic> row,
    String target,
  ) async {
    final returnId = row['return_id']?.toString();
    if (returnId == null || returnId.isEmpty || _working) return;

    String? resolution;
    String? refundId;
    String? note;

    if (target == 'APPROVED' ||
        (target == 'CLOSED' && row['return_status'] == 'RECEIVED')) {
      final controller = TextEditingController();
      final chosen = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(target == 'APPROVED' ? 'Approuver le retour' : 'Clôturer le retour'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: target == 'APPROVED' ? 'REFUND' : 'REPLACEMENT',
                decoration: const InputDecoration(labelText: 'Résolution'),
                items: const [
                  DropdownMenuItem(value: 'REFUND', child: Text('Remboursement')),
                  DropdownMenuItem(value: 'REPLACEMENT', child: Text('Remplacement')),
                  DropdownMenuItem(value: 'CREDIT', child: Text('Avoir')),
                ],
                onChanged: (value) => resolution = value,
              ),
              if (target == 'CLOSED') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Confirmation de livraison / exécution',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, resolution ?? (target == 'APPROVED' ? 'REFUND' : 'REPLACEMENT')),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      note = controller.text.trim();
      controller.dispose();
      if (!mounted || chosen == null) return;
      resolution = chosen;
      if (target == 'CLOSED' && (note.isEmpty)) {
        _message('Une confirmation est requise pour clôturer le retour.');
        return;
      }
    } else if (target == 'REJECTED') {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Refuser la demande'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Motif du refus'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Refuser')),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || value == null) return;
      note = value;
    } else if (target == 'REFUNDED') {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lier le remboursement terminé'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'UUID du remboursement COMPLETED'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Vérifier et valider')),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || value == null || value.isEmpty) return;
      refundId = value;
    }

    setState(() => _working = true);
    try {
      final client = ref.read(marketplaceAdminClientProvider);
      if (client == null) throw StateError('Connexion Supabase indisponible.');
      await client.rpc(
        'admin_transition_return',
        params: {
          'p_return_id': returnId,
          'p_new_status': target,
          'p_resolution': resolution,
          'p_refund_id': refundId,
          'p_note': note,
        },
      );
      if (!mounted) return;
      _message('Dossier de retour mis à jour : $target');
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      _message(safeBackendErrorMessage(
        error,
        fallback: 'Transition refusée. Vérifiez le statut, les droits et le remboursement lié.',
      ));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  List<PopupMenuEntry<String>> _actions(Map<String, dynamic> row) {
    final status = row['return_status']?.toString();
    if (status == 'REQUESTED') {
      return const [
        PopupMenuItem(value: 'APPROVED', child: Text('Approuver')),
        PopupMenuItem(value: 'REJECTED', child: Text('Refuser')),
      ];
    }
    if (status == 'APPROVED') {
      return const [PopupMenuItem(value: 'PICKUP', child: Text('Confirmer la collecte'))];
    }
    if (status == 'PICKUP') {
      return const [PopupMenuItem(value: 'RECEIVED', child: Text('Confirmer la réception'))];
    }
    if (status == 'RECEIVED') {
      return const [
        PopupMenuItem(value: 'REFUNDED', child: Text('Lier remboursement terminé')),
        PopupMenuItem(value: 'CLOSED', child: Text('Clôturer remplacement / avoir')),
      ];
    }
    if (status == 'REFUNDED') {
      return const [PopupMenuItem(value: 'CLOSED', child: Text('Clôturer le dossier'))];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossiers de retour'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _working ? null : _refresh,
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
            return const Center(child: Text('Impossible de charger les dossiers de retour.'));
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return const Center(child: Text('Aucun dossier de retour.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final status = row['return_status']?.toString() ?? '—';
              final actions = _actions(row);
              return Card(
                child: ListTile(
                  isThreeLine: true,
                  title: Text('Retour $status • Commande ${row['order_id']}'),
                  subtitle: Text(
                    'Client : ${row['customer_id']}\n'
                    'Article : ${row['order_item_id'] ?? 'Commande entière'}\n'
                    '${row['reason'] ?? ''}'
                    '${row['resolution'] == null ? '' : '\nRésolution : ${row['resolution']}'}'
                    '${row['refund_id'] == null ? '' : '\nRemboursement : ${row['refund_id']}'}',
                  ),
                  trailing: actions.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          enabled: !_working,
                          onSelected: (value) => _transition(row, value),
                          itemBuilder: (_) => actions,
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
