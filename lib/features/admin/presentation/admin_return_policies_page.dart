import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class AdminReturnPoliciesPage extends ConsumerStatefulWidget {
  const AdminReturnPoliciesPage({super.key});

  @override
  ConsumerState<AdminReturnPoliciesPage> createState() => _AdminReturnPoliciesPageState();
}

class _AdminReturnPoliciesPageState extends ConsumerState<AdminReturnPoliciesPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _saving = {};

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
    final raw = await client.rpc('admin_get_return_policy_settings');
    if (raw is! List) return const [];
    return raw.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _save(Map<String, dynamic> row, int hours) async {
    final id = row['category_id'].toString();
    if (_saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      final client = ref.read(marketplaceAdminClientProvider);
      if (client == null) throw StateError('Service indisponible.');
      await client.rpc('admin_set_return_window', params: {
        'p_category_id': id,
        'p_hours': hours,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Délai enregistré : $hours heures.')),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeBackendErrorMessage(error, fallback: 'Modification de la politique de retour refusée. Vérifiez les droits et réessayez.'))),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Délais de retour')),
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
                child: Text('Accès impossible : ${snapshot.error}'),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Les retours commerciaux ordinaires peuvent être réglés à 24 h, 48 h ou 72 h après livraison. Les réclamations légales et les litiges restent traités séparément.',
                  ),
                ),
              ),
              for (final row in rows)
                Card(
                  child: ListTile(
                    title: Text(row['name']?.toString() ?? 'Catégorie'),
                    subtitle: Text(row['is_default'] == true
                        ? 'Délai appliqué si aucune règle particulière n’existe.'
                        : 'Délai spécifique à cette catégorie.'),
                    trailing: SizedBox(
                      width: 118,
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: [24, 48, 72].contains(row['return_window_hours'])
                            ? row['return_window_hours'] as int
                            : 72,
                        items: const [
                          DropdownMenuItem(value: 24, child: Text('24 heures')),
                          DropdownMenuItem(value: 48, child: Text('48 heures')),
                          DropdownMenuItem(value: 72, child: Text('72 heures')),
                        ],
                        onChanged: _saving.contains(row['category_id'].toString())
                            ? null
                            : (value) {
                                if (value != null) _save(row, value);
                              },
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Les règles sont enregistrées côté serveur. Un client ne peut pas modifier lui-même ces délais.',
              ),
            ],
          );
        },
      ),
    );
  }
}