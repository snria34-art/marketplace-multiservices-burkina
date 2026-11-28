import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/widgets/account_session_action_button.dart';

class ProviderApplicationPage extends ConsumerStatefulWidget {
  const ProviderApplicationPage({super.key});

  @override
  ConsumerState<ProviderApplicationPage> createState() =>
      _ProviderApplicationPageState();
}

class _ProviderApplicationPageState
    extends ConsumerState<ProviderApplicationPage> {
  static const _types = <({String value, String label, IconData icon})>[
    (value: 'TAXI', label: 'Taxi', icon: Icons.local_taxi_outlined),
    (value: 'MOTO_TAXI', label: 'Moto-taxi', icon: Icons.two_wheeler),
    (value: 'VTC', label: 'VTC / Chauffeur privé', icon: Icons.directions_car_outlined),
    (value: 'VEHICLE_RENTAL', label: 'Location de véhicules', icon: Icons.car_rental),
    (value: 'TRANSPORT_COMPANY', label: 'Compagnie de transport / Bus', icon: Icons.directions_bus_outlined),
    (value: 'FREIGHT', label: 'Fret / Transport de marchandises', icon: Icons.local_shipping_outlined),
    (value: 'COURIER', label: 'Coursier / Livraison', icon: Icons.delivery_dining),
  ];

  final _name = TextEditingController();
  final _description = TextEditingController();
  String _type = 'TAXI';
  bool _submitting = false;
  String? _submittedId;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez un nom de prestataire valide.')),
      );
      return;
    }

    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null || _submitting) return;

    setState(() => _submitting = true);
    try {
      final result = await client!.rpc(
        'submit_service_provider_application',
        params: {
          'p_provider_type': _type,
          'p_display_name': name,
          'p_description': _description.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _submittedId = result.toString());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Demande non envoyée : $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _types.firstWhere((item) => item.value == _type);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devenir prestataire'),
        actions: const [AccountSessionActionButton()],
      ),
      body: _submittedId != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 52),
                    const SizedBox(height: 12),
                    Text(
                      'Demande envoyée',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Votre dossier est en attente de vérification. '
                      'Votre profil ne sera pas visible comme prestataire '
                      'avant validation par notre équipe.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Référence : $_submittedId',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Proposez vos services sur Marketplace Multiservices Burkina.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choisissez votre activité et envoyez une demande. '
                  'La validation des informations et des justificatifs '
                  'sera effectuée avant l’activation du profil.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type de prestataire',
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.value,
                          child: Row(
                            children: [
                              Icon(item.icon, size: 20),
                              const SizedBox(width: 10),
                              Flexible(child: Text(item.label)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _type = value);
                        },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Nom public / Nom de l’entreprise',
                    hintText: 'Ex. Taxi Wendpanga, Transport du Centre…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _description,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Présentation de votre activité',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(selected.icon),
                    title: Text(selected.label),
                    subtitle: const Text(
                      'Activation après vérification administrative.',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Envoyer ma demande'),
                ),
              ],
            ),
    );
  }
}
