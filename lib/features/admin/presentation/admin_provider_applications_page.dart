import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/widgets/account_session_action_button.dart';

class AdminProviderApplicationsPage extends ConsumerStatefulWidget {
  const AdminProviderApplicationsPage({super.key});

  @override
  ConsumerState<AdminProviderApplicationsPage> createState() =>
      _AdminProviderApplicationsPageState();
}

class _AdminProviderApplicationsPageState
    extends ConsumerState<AdminProviderApplicationsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }
    final rows = await client.rpc('admin_list_pending_provider_applications');
    if (rows is! List) return const [];
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<String?> _rejectionNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Motif du refus'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Expliquez les éléments à corriger (5 caractères minimum).',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Confirmer le refus'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().length < 5) return null;
    return result.trim();
  }

  Future<void> _review(
    Map<String, dynamic> item,
    String decision,
  ) async {
    final id = item['provider_id']?.toString();
    if (id == null || _processing.contains(id)) return;

    String? note;
    if (decision == 'REJECT') {
      note = await _rejectionNote();
      if (note == null || !mounted) return;
    }

    setState(() => _processing.add(id));
    try {
      final client = ref.read(supabaseProvider);
      await client!.rpc(
        'admin_review_provider_application',
        params: {
          'p_provider_id': id,
          'p_decision': decision,
          'p_note': note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'APPROVE'
                ? 'Prestataire approuvé et activé.'
                : 'Demande refusée.',
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Décision non enregistrée : $error')),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'TAXI': return 'Taxi';
      case 'MOTO_TAXI': return 'Moto-taxi';
      case 'VTC': return 'VTC / Chauffeur privé';
      case 'VEHICLE_RENTAL': return 'Location de véhicules';
      case 'TRANSPORT_COMPANY': return 'Compagnie de transport / Bus';
      case 'FREIGHT': return 'Fret / Marchandises';
      case 'COURIER': return 'Coursier / Livraison';
      default: return type ?? 'Prestataire';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demandes prestataires'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const AccountSessionActionButton(),
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
                child: Text('Chargement impossible : ${snapshot.error}'),
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Aucune demande prestataire en attente.'),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final id = item['provider_id']?.toString() ?? '';
                final busy = _processing.contains(id);
                final created = DateTime.tryParse(
                  item['created_at']?.toString() ?? '',
                );
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['display_name']?.toString() ?? 'Sans nom',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(_typeLabel(item['provider_type']?.toString())),
                        if ((item['description']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(item['description'].toString()),
                        ],
                        if (created != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Demande du ${created.toLocal()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'Approbation désactivée : le dépôt privé et la vérification '
                          'des justificatifs KYC ne sont pas encore disponibles. '
                          'Une demande peut être refusée avec un motif.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: null,
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: const Text('Approuver'),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy ? null : () => _review(item, 'REJECT'),
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Refuser'),
                            ),
                          ],
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
