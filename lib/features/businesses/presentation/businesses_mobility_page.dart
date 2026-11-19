import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../verticals/data/vertical_repository.dart';

final businessMobilityListingsProvider =
    FutureProvider.autoDispose<Map<VerticalModule, List<Map<String, dynamic>>>>(
  (ref) async {
    final repository = ref.watch(verticalRepositoryProvider);
    if (repository == null) return const {};

    final results = await Future.wait([
      repository.list(VerticalModule.digital),
      repository.list(VerticalModule.rentals),
    ]);

    return {
      VerticalModule.digital: results[0],
      VerticalModule.rentals: results[1],
    };
  },
);

class BusinessesMobilityPage extends ConsumerWidget {
  const BusinessesMobilityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessMobilityListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entreprises & mobilité'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(businessMobilityListingsProvider.future),
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              const Text(
                'Impossible de charger les annonces pour le moment.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => ref.invalidate(businessMobilityListingsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
          data: (groups) {
            final digital = groups[VerticalModule.digital] ?? const [];
            final rentals = groups[VerticalModule.rentals] ?? const [];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  'Trouvez des entreprises et des solutions de mobilité près de vous.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  icon: Icons.devices_other_outlined,
                  title: 'Entreprises digitales',
                  count: digital.length,
                ),
                if (digital.isEmpty)
                  const _EmptySection(
                    message: 'Aucun service digital vérifié disponible actuellement.',
                  )
                else
                  ...digital.map((item) => _DigitalServiceCard(item: item)),
                const SizedBox(height: 20),
                _SectionHeader(
                  icon: Icons.directions_car_outlined,
                  title: 'Location de véhicules et motos',
                  count: rentals.length,
                ),
                if (rentals.isEmpty)
                  const _EmptySection(
                    message: 'Aucun véhicule de location vérifié disponible actuellement.',
                  )
                else
                  ...rentals.map((item) => _RentalCard(item: item)),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Les annonces de vente de véhicules et motos (origine locale ou importée) nécessitent encore leur propre fiche et leur workflow de publication. Elles ne sont pas présentées comme disponibles tant que cette partie n’est pas connectée.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Chip(label: Text('$count')),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}

class _DigitalServiceCard extends StatelessWidget {
  const _DigitalServiceCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final provider = item['service_providers'];
    final providerName = provider is Map
        ? provider['display_name']?.toString()
        : null;
    final price = item['price'];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.computer_outlined),
        ),
        title: Text(item['name']?.toString() ?? 'Service digital'),
        subtitle: Text([
          if (item['category'] != null) item['category'].toString(),
          if (providerName != null && providerName.isNotEmpty) providerName,
          if (item['description'] != null) item['description'].toString(),
        ].join(' • ')),
        trailing: price == null
            ? null
            : Text(
                '${price.toString()} F',
                style: Theme.of(context).textTheme.labelLarge,
              ),
        isThreeLine: item['description'] != null,
      ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final provider = item['service_providers'];
    final providerName = provider is Map
        ? provider['display_name']?.toString()
        : null;
    final vehicle = [
      item['brand']?.toString(),
      item['model']?.toString(),
    ].where((value) => value != null && value.isNotEmpty).join(' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.two_wheeler_outlined),
        ),
        title: Text(
          vehicle.isEmpty
              ? item['vehicle_type']?.toString() ?? 'Véhicule'
              : vehicle,
        ),
        subtitle: Text([
          item['vehicle_type']?.toString() ?? 'Véhicule / moto',
          if (providerName != null && providerName.isNotEmpty) providerName,
          if (item['deposit_amount'] != null)
            'Caution : ${item['deposit_amount']} F',
        ].join(' • ')),
        trailing: Text(
          '${item['daily_price'] ?? '—'} F/j',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
