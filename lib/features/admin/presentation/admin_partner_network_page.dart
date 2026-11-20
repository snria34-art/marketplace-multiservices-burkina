import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';

class AdminPartnerNetworkPage extends ConsumerStatefulWidget {
  const AdminPartnerNetworkPage({super.key});

  @override
  ConsumerState<AdminPartnerNetworkPage> createState() =>
      _AdminPartnerNetworkPageState();
}

class _AdminPartnerNetworkPageState
    extends ConsumerState<AdminPartnerNetworkPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final client = ref.read(marketplaceAdminClientProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }

    final response = await client.functions.invoke('admin-partner-network');
    if (response.data is! Map) {
      throw StateError('Réponse des statistiques partenaires invalide.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Map<String, dynamic> _section(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réseau de partenaires'),
        actions: [
          IconButton(
            tooltip: 'Actualiser les statistiques',
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.query_stats_outlined, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'Statistiques partenaires indisponibles.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Impossible de charger le réseau partenaire. Vérifiez vos droits administrateur et réessayez.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Le tableau de bord nécessite le déploiement contrôlé '
                      'de la fonction Edge admin-partner-network. Aucune '
                      'valeur fictive n’est affichée.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();

          final sellers = _section(data, 'sellers');
          final shops = _section(data, 'shops');
          final providers = _section(data, 'providers');
          final couriers = _section(data, 'couriers');
          final partners = _section(data, 'partners');
          final generatedAt = DateTime.tryParse(
            data['generated_at']?.toString() ?? '',
          );
          final truncated = data['data_truncated'] == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Comptes vérifiés et activité enregistrée',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                generatedAt == null
                    ? 'Date de calcul non fournie'
                    : 'Calculé le '
                        '${generatedAt.toLocal().toString().substring(0, 16)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (truncated) ...[
                const SizedBox(height: 10),
                const ListTile(
                  leading: Icon(Icons.warning_amber_outlined),
                  title: Text('Résultat partiellement tronqué'),
                  subtitle: Text(
                    'Certaines tables dépassent la limite de lecture. '
                    'Les chiffres affichés peuvent être incomplets.',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Partenaires distincts actifs',
                value: partners['unique_active_accounts'],
                description:
                    'Comptes vendeurs, prestataires et coursiers réunis '
                    'sans compter deux fois un même utilisateur.',
              ),
              const SizedBox(height: 16),
              Text(
                'Vendeurs et boutiques',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _MetricCard(
                title: 'Vendeurs inscrits',
                value: sellers['registered'],
              ),
              _MetricCard(
                title: 'Vendeurs vérifiés avec compte actif',
                value: sellers['verified_active'],
              ),
              _MetricCard(
                title: 'Vendeurs avec boutique active et vérifiée',
                value: sellers['with_active_verified_shop'],
              ),
              _MetricCard(
                title: 'Vendeurs ayant déjà livré une commande',
                value: sellers['with_delivered_order'],
                description: 'Activité enregistrée sur l’historique conservé.',
              ),
              _MetricCard(
                title: 'Boutiques actives et vérifiées',
                value: shops['active_verified'],
                description: '${shops['registered'] ?? 0} boutiques recensées.',
              ),
              const SizedBox(height: 16),
              Text(
                'Prestataires de services',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _MetricCard(
                title: 'Prestataires inscrits',
                value: providers['registered'],
              ),
              _MetricCard(
                title: 'Prestataires actifs et vérifiés',
                value: providers['active_verified'],
              ),
              _MetricCard(
                title: 'Prestataires avec demande terminée',
                value: providers['with_completed_request'],
                description: 'Au moins une demande marquée COMPLETED.',
              ),
              const SizedBox(height: 16),
              Text(
                'Coursiers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _MetricCard(
                title: 'Comptes avec rôle coursier',
                value: couriers['registered'],
              ),
              _MetricCard(
                title: 'Comptes coursiers actifs',
                value: couriers['active_accounts'],
                description:
                    'Compte actif ne signifie pas disponibilité en ligne.',
              ),
              _MetricCard(
                title: 'Coursiers actuellement en mission',
                value: couriers['currently_on_mission'],
                description:
                    'Au moins une affectation ASSIGNED, ACCEPTED, '
                    'PICKED_UP ou IN_TRANSIT.',
              ),
              _MetricCard(
                title: 'Coursiers ayant déjà terminé une livraison',
                value: couriers['with_completed_delivery'],
              ),
              const SizedBox(height: 16),
              const Text(
                'Définitions : un partenaire « actif » est un compte '
                'actif répondant aux critères de vérification et de service '
                'publié. « A déjà réalisé une opération » signifie qu’une '
                'commande, une demande de service ou une livraison terminée '
                'existe dans l’historique disponible. Ces indicateurs ne '
                'mesurent pas une présence en ligne instantanée.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.description,
  });

  final String title;
  final Object? value;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: description == null ? null : Text(description!),
        trailing: Text(
          value?.toString() ?? '—',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
