import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/providers/repository_providers.dart';
import '../data/mechanic_repository.dart';
import 'mechanic_service_profile_dialog.dart';

final mechanicRepositoryProvider = Provider<MechanicRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : MechanicRepository(client);
});

class MechanicsPage extends ConsumerStatefulWidget {
  const MechanicsPage({super.key});

  @override
  ConsumerState<MechanicsPage> createState() => _MechanicsPageState();
}

class _MechanicsPageState extends ConsumerState<MechanicsPage> {
  late Future<List<Map<String, dynamic>>> _mechanicsFuture;
  late Future<List<Map<String, dynamic>>> _quotesFuture;
  late Future<bool> _isMechanicFuture;

  @override
  void initState() {
    super.initState();
    _mechanicsFuture = _loadMechanics();
    _quotesFuture = _loadQuotes();
    _isMechanicFuture = _loadOwnMechanic();
  }

  Future<List<Map<String, dynamic>>> _loadMechanics() {
    return ref.read(mechanicRepositoryProvider)?.mechanics() ??
        Future.value(const []);
  }

  Future<bool> _loadOwnMechanic() async {
    final client = ref.read(supabaseProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) return false;
    final rows = await client
        .from('mechanics')
        .select('id,display_name,active,verification_status')
        .eq('user_id', user.id)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> _manageAvailability() async {
    final canManage = await _loadOwnMechanic();
    if (!mounted) return;
    if (!canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun profil mécanicien lié à ce compte.')),
      );
      return;
    }

    final status = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Ma disponibilité'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'AVAILABLE'),
            child: const Text('Disponible maintenant'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'IN_10_MIN'),
            child: const Text('Disponible dans 10 min'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'IN_20_MIN'),
            child: const Text('Disponible dans 20 min'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'IN_30_MIN'),
            child: const Text('Disponible dans 30 min'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'UNAVAILABLE'),
            child: const Text('Indisponible'),
          ),
        ],
      ),
    );

    if (!mounted || status == null) return;

    try {
      final client = ref.read(supabaseProvider);
      await client?.rpc(
        'set_mechanic_availability',
        params: {
          'p_status': status,
          'p_starts_at': DateTime.now().toUtc().toIso8601String(),
          'p_ends_at': null,
        },
      );

      final vacation = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 730)),
        helpText: 'Programmer un congé (facultatif)',
      );

      if (vacation != null && mounted) {
        final reasonController = TextEditingController();
        final reason = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Période de congé'),
              content: TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motif (facultatif)',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    reasonController.text.trim(),
                  ),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );

        reasonController.dispose();
        if (!mounted) return;

        if (reason != null) {
          await client?.rpc(
            'schedule_mechanic_time_off',
            params: {
              'p_starts_at': DateTime(
                vacation.start.year,
                vacation.start.month,
                vacation.start.day,
              ).toUtc().toIso8601String(),
              'p_ends_at': DateTime(
                vacation.end.year,
                vacation.end.month,
                vacation.end.day,
                23,
                59,
                59,
              ).toUtc().toIso8601String(),
              'p_reason': reason,
            },
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disponibilité mise à jour.')),
      );
      setState(() {
        _mechanicsFuture = _loadMechanics();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mise à jour refusée : ' + error.toString())),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadQuotes() {
    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null) return Future.value(const []);
    return ref.read(mechanicRepositoryProvider)?.myQuotes() ??
        Future.value(const []);
  }

  Future<void> _request() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _MechanicRequestDialog(),
    );

    if (!mounted || result == null) return;

    try {
      final pos = await DeviceLocationService.current();
      if (!mounted) return;
      final repo = ref.read(mechanicRepositoryProvider);
      if (repo == null) return;

      final id = await repo.createRequest(
        vehicleType: result['vehicle_type']!,
        serviceLocationType: result['service_location_type']!,
        problemType: result['problem_type']!,
        description: result['description'],
        locationNote: result['location_note'],
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      if (!mounted) return;

      setState(() => _quotesFuture = _loadQuotes());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Demande envoyée. Référence : ' + id,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString();
      final message = errorText.contains('no_compatible_mechanics_available')
          ? 'Aucun mécanicien compatible n’est ouvert et disponible pour ce véhicule et ce lieu. Essayez un autre lieu ou revenez pendant ses heures de service.'
          : errorText.contains('service_location_details_required')
              ? 'Précisez l’adresse du domicile ou le nom du bureau.'
              : 'Impossible d’envoyer la demande. Vérifiez la position et réessayez.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _manageServiceProfile() async {
    final canManage = await _loadOwnMechanic();
    if (!mounted) return;
    if (!canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun profil mécanicien lié à ce compte.')),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const MechanicServiceProfileDialog(),
    );
    if (!mounted || result == null) return;

    final repo = ref.read(mechanicRepositoryProvider);
    if (repo == null) return;

    try {
      final rawVehicles = result['vehicle_types'];
      final rawServices = result['service_types'];
      final rawDays = result['service_days'];
      if (rawVehicles is! List || rawServices is! List || rawDays is! List) {
        throw StateError('Configuration du profil invalide.');
      }

      await repo.saveServiceProfile(
        vehicleTypes: rawVehicles.map((value) => value.toString()).toList(),
        serviceTypes: rawServices.map((value) => value.toString()).toList(),
        openTime: result['open_time'].toString(),
        closeTime: result['close_time'].toString(),
        serviceDays: rawDays
            .map((value) => int.tryParse(value.toString()) ?? 0)
            .toList(),
        homePrice: num.parse(result['home_price'].toString()),
        officePrice: num.parse(result['office_price'].toString()),
        roadsidePrice: num.parse(result['roadside_price'].toString()),
        adjustmentNote: result['adjustment_note']?.toString(),
      );

      if (!mounted) return;
      setState(() {
        _mechanicsFuture = _loadMechanics();
        _isMechanicFuture = _loadOwnMechanic();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compétences, horaires et tarifs enregistrés.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement refusé : $error')),
      );
    }
  }

  String _serviceLocationLabel(String? value) {
    switch (value) {
      case 'HOME':
        return 'maison';
      case 'OFFICE':
        return 'bureau';
      case 'ROADSIDE':
        return 'dépannage sur route';
      default:
        return 'intervention';
    }
  }

  String _serviceSummary(dynamic rawServices) {
    if (rawServices is! List || rawServices.isEmpty) {
      return 'Compétences non renseignées';
    }

    return rawServices.whereType<Map>().map((raw) {
      final service = Map<String, dynamic>.from(raw);
      final rates = service['rates'] is List
          ? (service['rates'] as List).whereType<Map>()
          : const <Map>[];
      final rateText = rates.map((rawRate) {
        final rate = Map<String, dynamic>.from(rawRate);
        return _serviceLocationLabel(
              rate['service_location_type']?.toString(),
            ) +
            ' : ' +
            (rate['base_price']?.toString() ?? '0') +
            ' XOF';
      }).join(', ');
      final serviceType = service['service_type']?.toString() ?? 'GENERAL_REPAIR';
      final label = serviceType
          .toLowerCase()
          .replaceAll('_', ' ');
      return _vehicleLabel(service['vehicle_type']?.toString()) +
          ' — ' +
          label +
          (rateText.isEmpty ? '' : ' ($rateText)');
    }).join('\n');
  }

  String _vehicleLabel(String? value) {
    switch (value) {
      case 'MOTORCYCLE':
        return 'Moto classique';
      case 'ELECTRIC_MOTORCYCLE':
        return 'Moto électrique';
      case 'CAR':
        return 'Voiture';
      case 'ELECTRIC_CAR':
        return 'Voiture électrique';
      case 'BICYCLE':
        return 'Vélo';
      case 'ELECTRIC_BICYCLE':
        return 'Vélo électrique';
      case 'TRUCK':
        return 'Camion';
      default:
        return 'Véhicule';
    }
  }

  Future<void> _accept(String quoteId) async {
    final repo = ref.read(mechanicRepositoryProvider);
    if (repo == null) return;

    try {
      await repo.acceptQuote(quoteId);
      if (!mounted) return;
      setState(() => _quotesFuture = _loadQuotes());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Devis indisponible : ' + error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mécaniciens'),
        actions: [
          IconButton(
            onPressed: _request,
            icon: const Icon(Icons.car_repair_outlined),
            tooltip: 'Demander un mécanicien',
          ),
          FutureBuilder<bool>(
            future: _isMechanicFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _manageServiceProfile,
                    icon: const Icon(Icons.build_circle_outlined),
                    tooltip: 'Mes compétences, horaires et tarifs',
                  ),
                  IconButton(
                    onPressed: _manageAvailability,
                    icon: const Icon(Icons.schedule_outlined),
                    tooltip: 'Gérer ma disponibilité',
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Mécaniciens disponibles',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _mechanicsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final items =
                  snapshot.data ?? const <Map<String, dynamic>>[];

              if (items.isEmpty) {
                return const Text('Aucun mécanicien vérifié disponible.');
              }

              return Column(
                children: items.map((mechanic) {
                  final raw = mechanic['mechanic_availability'];
                  final availability =
                      raw is List && raw.isNotEmpty
                          ? Map<String, dynamic>.from(raw.first as Map)
                          : null;

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.build_outlined),
                      ),
                      title: Text(
                        mechanic['display_name']?.toString() ?? 'Mécanicien',
                      ),
                      subtitle: Text(
                        _availabilityLabel(
                          availability?['status']?.toString(),
                        ) +
                            '\nHoraires : ' +
                            (mechanic['service_open_time']?.toString() ?? '08:00') +
                            '–' +
                            (mechanic['service_close_time']?.toString() ?? '20:00') +
                            '\n' +
                            _serviceSummary(mechanic['mechanic_services']) +
                            '\nRayon : ' +
                            (mechanic['service_radius_km']?.toString() ?? '-') +
                            ' km',
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Mes devis',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _quotesFuture,
            builder: (context, snapshot) {
              final quotes =
                  snapshot.data ?? const <Map<String, dynamic>>[];

              if (quotes.isEmpty) {
                return const Text('Aucun devis reçu.');
              }

              return Column(
                children: quotes.map((quote) {
                  final mechanic = quote['mechanics'] is Map
                      ? Map<String, dynamic>.from(
                          quote['mechanics'] as Map,
                        )
                      : const <String, dynamic>{};

                  return Card(
                    child: ListTile(
                      title: Text(
                        mechanic['display_name']?.toString() ?? 'Mécanicien',
                      ),
                      subtitle: Text(
                        (quote['diagnosis']?.toString() ?? '') +
                            '\n' +
                            (quote['amount']?.toString() ?? '0') +
                            ' ' +
                            (quote['currency']?.toString() ?? 'XOF') +
                            ' • ' +
                            (quote['status']?.toString() ?? ''),
                      ),
                      trailing: quote['status'] == 'PENDING'
                          ? FilledButton(
                              onPressed: () =>
                                  _accept(quote['id'].toString()),
                              child: const Text('Accepter'),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _availabilityLabel(String? value) {
    switch (value) {
      case 'AVAILABLE':
        return 'Disponible maintenant';
      case 'IN_10_MIN':
        return 'Disponible dans 10 min';
      case 'IN_20_MIN':
        return 'Disponible dans 20 min';
      case 'IN_30_MIN':
        return 'Disponible dans 30 min';
      case 'UNAVAILABLE':
        return 'Indisponible';
      default:
        return 'Indisponible';
    }
  }
}

class _MechanicRequestDialog extends StatefulWidget {
  const _MechanicRequestDialog();

  @override
  State<_MechanicRequestDialog> createState() => _MechanicRequestDialogState();
}

class _MechanicRequestDialogState extends State<_MechanicRequestDialog> {
  String _vehicle = 'MOTORCYCLE';
  String _locationType = 'ROADSIDE';
  final _problem = TextEditingController();
  final _description = TextEditingController();
  final _locationNote = TextEditingController();

  @override
  void dispose() {
    _problem.dispose();
    _description.dispose();
    _locationNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationLabel = switch (_locationType) {
      'HOME' => 'Adresse et repère du domicile',
      'OFFICE' => 'Nom du bureau, bâtiment et étage',
      _ => 'Repère de la panne (rue, quartier, point connu)',
    };

    return AlertDialog(
      title: const Text('Demander un mécanicien'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Véhicule'),
                items: const [
                  DropdownMenuItem(
                    value: 'MOTORCYCLE',
                    child: Text('Moto classique'),
                  ),
                  DropdownMenuItem(
                    value: 'ELECTRIC_MOTORCYCLE',
                    child: Text('Moto électrique'),
                  ),
                  DropdownMenuItem(
                    value: 'CAR',
                    child: Text('Voiture'),
                  ),
                  DropdownMenuItem(
                    value: 'ELECTRIC_CAR',
                    child: Text('Voiture électrique'),
                  ),
                  DropdownMenuItem(
                    value: 'BICYCLE',
                    child: Text('Vélo'),
                  ),
                  DropdownMenuItem(
                    value: 'ELECTRIC_BICYCLE',
                    child: Text('Vélo électrique'),
                  ),
                  DropdownMenuItem(
                    value: 'TRUCK',
                    child: Text('Camion'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _vehicle = value);
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Où se trouve le véhicule ?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'HOME',
                    icon: Icon(Icons.home_outlined),
                    label: Text('Maison'),
                  ),
                  ButtonSegment(
                    value: 'OFFICE',
                    icon: Icon(Icons.business_outlined),
                    label: Text('Bureau'),
                  ),
                  ButtonSegment(
                    value: 'ROADSIDE',
                    icon: Icon(Icons.warning_amber_outlined),
                    label: Text('En panne'),
                  ),
                ],
                selected: {_locationType},
                onSelectionChanged: (selection) {
                  setState(() => _locationType = selection.first);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _locationNote,
                maxLength: 240,
                decoration: InputDecoration(
                  labelText: locationLabel,
                  hintText: _locationType == 'OFFICE'
                      ? 'Ex. Immeuble Z, entrée principale'
                      : _locationType == 'HOME'
                          ? 'Ex. Porte verte, près du marché'
                          : 'Ex. Route de Kossodo, près de la station',
                ),
              ),
              TextField(
                controller: _problem,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Panne ou réparation recherchée',
                  hintText: 'Pneu crevé, batterie, moteur, diagnostic électronique…',
                ),
              ),
              TextField(
                controller: _description,
                maxLines: 3,
                maxLength: 600,
                decoration: const InputDecoration(
                  labelText: 'Autres détails (facultatif)',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Votre position GPS sera jointe à la demande. Le mécanicien ne recevra que les demandes correspondant aux types de véhicules et aux lieux qu’il prend en charge, pendant ses heures de service.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final problem = _problem.text.trim();
            final locationNote = _locationNote.text.trim();
            if (problem.isEmpty ||
                ((_locationType == 'HOME' || _locationType == 'OFFICE') &&
                    locationNote.isEmpty)) {
              return;
            }
            Navigator.pop(
              context,
              <String, String>{
                'vehicle_type': _vehicle,
                'service_location_type': _locationType,
                'location_note': locationNote,
                'problem_type': problem,
                'description': _description.text.trim(),
              },
            );
          },
          child: const Text('Envoyer la demande'),
        ),
      ],
    );
  }
}
