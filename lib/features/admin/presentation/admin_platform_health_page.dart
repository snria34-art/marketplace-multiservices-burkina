import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';

class AdminPlatformHealthPage extends ConsumerStatefulWidget {
  const AdminPlatformHealthPage({super.key});

  @override
  ConsumerState<AdminPlatformHealthPage> createState() =>
      _AdminPlatformHealthPageState();
}

class _AdminPlatformHealthPageState
    extends ConsumerState<AdminPlatformHealthPage> {
  late Future<Map<String, dynamic>> _future;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }
    final health = await client.rpc('get_platform_health');
    final repairs = await client.rpc(
      'get_platform_repair_audit',
      params: {'p_limit': 20},
    );
    return {
      'checks': health is List ? health : const [],
      'repairs': repairs is List ? repairs : const [],
    };
  }

  Future<void> _runMonitor() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    setState(() => _running = true);
    try {
      await client.functions.invoke('platform-health-monitor');
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vérification des services terminée.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vérification impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runRepairs() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final count = await client.rpc('admin_run_safe_platform_repairs');
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Réparations réversibles appliquées : $count')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Réparation refusée : $error')),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'UP':
        return Colors.green;
      case 'DOWN':
        return Colors.red;
      case 'DEGRADED':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surveillance et réparations'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Accès impossible : ${snapshot.error}\n\n'
                  'Un compte administrateur actif est nécessaire.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data ?? const {};
          final checks = data['checks'] as List? ?? const [];
          final repairs = data['repairs'] as List? ?? const [];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _runMonitor,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.monitor_heart_outlined),
                label: const Text('Vérifier les services maintenant'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _runRepairs,
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text('Exécuter les réparations sûres'),
              ),
              const SizedBox(height: 16),
              Text('État des services', style: Theme.of(context).textTheme.titleLarge),
              if (checks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucun contrôle externe enregistré pour le moment.'),
                ),
              ...checks.map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                final status = row['status']?.toString() ?? 'NOT_TESTED';
                final details = row['details'] is Map
                    ? Map<String, dynamic>.from(row['details'] as Map)
                    : const <String, dynamic>{};
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.circle, color: _statusColor(status), size: 14),
                    title: Text(row['component']?.toString() ?? 'Service'),
                    subtitle: Text(
                      '$status • ${row['response_ms'] ?? '-'} ms\n'
                      '${details['reason'] ?? details['http_status'] ?? ''}',
                    ),
                    trailing: Text(
                      row['checked_at']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Text('Journal des réparations', style: Theme.of(context).textTheme.titleLarge),
              if (repairs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune réparation enregistrée.'),
                ),
              ...repairs.map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(row['repair_code']?.toString() ?? 'Réparation'),
                  subtitle: Text(row['status']?.toString() ?? ''),
                  trailing: Text(row['created_at']?.toString() ?? ''),
                );
              }),
              const SizedBox(height: 12),
              const Text(
                'Les réparations automatiques ne touchent pas aux commandes, paiements, soldes ou comptes. Chaque opération autorisée est sauvegardée et journalisée.',
              ),
            ],
          );
        },
      ),
    );
  }
}
