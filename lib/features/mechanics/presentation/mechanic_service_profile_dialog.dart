import 'package:flutter/material.dart';

class MechanicServiceProfileDialog extends StatefulWidget {
  const MechanicServiceProfileDialog({super.key});

  @override
  State<MechanicServiceProfileDialog> createState() =>
      _MechanicServiceProfileDialogState();
}

class _MechanicServiceProfileDialogState
    extends State<MechanicServiceProfileDialog> {
  static const _vehicles = <String, String>{
    'MOTORCYCLE': 'Moto classique',
    'ELECTRIC_MOTORCYCLE': 'Moto électrique',
    'CAR': 'Voiture',
    'ELECTRIC_CAR': 'Voiture électrique',
    'BICYCLE': 'Vélo',
    'ELECTRIC_BICYCLE': 'Vélo électrique',
    'TRUCK': 'Camion',
  };

  static const _serviceTypes = <String, String>{
    'GENERAL_REPAIR': 'Réparation générale',
    'ENGINE': 'Moteur',
    'ELECTRICAL': 'Électricité',
    'ELECTRONIC_DIAGNOSTICS': 'Diagnostic électronique',
    'BRAKES': 'Freins',
    'TIRES': 'Pneus',
    'BATTERY': 'Batterie',
  };

  static const _days = <int, String>{
    1: 'Lun',
    2: 'Mar',
    3: 'Mer',
    4: 'Jeu',
    5: 'Ven',
    6: 'Sam',
    7: 'Dim',
  };

  final Set<String> _selectedVehicles = {};
  final Set<String> _selectedServices = {'GENERAL_REPAIR'};
  final Set<int> _selectedDays = {1, 2, 3, 4, 5, 6};
  final _customServiceController = TextEditingController();
  final _homePrice = TextEditingController(text: '1500');
  final _officePrice = TextEditingController(text: '1500');
  final _roadsidePrice = TextEditingController(text: '1500');
  final _note = TextEditingController();
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void dispose() {
    _homePrice.dispose();
    _officePrice.dispose();
    _roadsidePrice.dispose();
    _note.dispose();
    _customServiceController.dispose();
    super.dispose();
  }

  String _timeValue(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool opening) async {
    final initial = opening ? _openTime : _closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: opening ? 'Heure d’ouverture' : 'Heure de fermeture',
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (opening) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  void _submit() {
    final home = num.tryParse(_homePrice.text.trim());
    final office = num.tryParse(_officePrice.text.trim());
    final roadside = num.tryParse(_roadsidePrice.text.trim());
    final opens = _openTime.hour * 60 + _openTime.minute;
    final closes = _closeTime.hour * 60 + _closeTime.minute;

    if (_selectedVehicles.isEmpty ||
        _selectedServices.isEmpty ||
        _selectedDays.isEmpty ||
        home == null ||
        home < 0 ||
        office == null ||
        office < 0 ||
        roadside == null ||
        roadside < 0 ||
        opens >= closes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choisissez au moins un véhicule, des jours valides et des tarifs corrects.',
          ),
        ),
      );
      return;
    }

    Navigator.pop<Map<String, dynamic>>(
      context,
      {
        'vehicle_types': _selectedVehicles.toList(),
        'service_types': _selectedServices.toList(),
        'open_time': _timeValue(_openTime),
        'close_time': _timeValue(_closeTime),
        'service_days': _selectedDays.toList()..sort(),
        'home_price': home,
        'office_price': office,
        'roadside_price': roadside,
        'adjustment_note': _note.text.trim(),
      },
    );
  }

  Widget _priceField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'XOF',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mes compétences et horaires'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Véhicules que vous savez réparer',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in _vehicles.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _selectedVehicles.contains(entry.key),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedVehicles.add(entry.key);
                          } else {
                            _selectedVehicles.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                'Types de réparation proposés',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in _serviceTypes.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _selectedServices.contains(entry.key),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedServices.add(entry.key);
                          } else {
                            _selectedServices.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customServiceController,
                      decoration: const InputDecoration(
                        labelText: 'Autre compétence',
                        hintText: 'Ex. Climatisation',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajouter cette compétence',
                    onPressed: () {
                      final value = _customServiceController.text.trim();
                      if (value.length < 2 || value.length > 80) return;
                      setState(() => _selectedServices.add(value.toUpperCase()));
                      _customServiceController.clear();
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final service in _selectedServices.where(
                    (value) => !_serviceTypes.containsKey(value),
                  ))
                    InputChip(
                      label: Text(service),
                      onDeleted: () => setState(
                        () => _selectedServices.remove(service),
                      ),
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                'Jours de service',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in _days.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _selectedDays.contains(entry.key),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedDays.add(entry.key);
                          } else {
                            _selectedDays.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(true),
                      icon: const Icon(Icons.login_outlined),
                      label: Text('Ouvre ${_timeValue(_openTime)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(false),
                      icon: const Icon(Icons.logout_outlined),
                      label: Text('Ferme ${_timeValue(_closeTime)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Après l’heure de fermeture, votre profil ne sera plus proposé pour de nouvelles demandes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              Text(
                'Tarifs de déplacement / diagnostic',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _priceField('Intervention à domicile', _homePrice),
              _priceField('Intervention au bureau', _officePrice),
              _priceField('Dépannage sur place / route', _roadsidePrice),
              TextField(
                controller: _note,
                maxLength: 240,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Précision sur les tarifs (facultatif)',
                  hintText: 'Réparation supplémentaire après diagnostic et accord du client.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Le prix final d’une réparation différente du diagnostic doit être proposé au client et accepté avant le travail. Aucun supplément ne sera prélevé sans son accord.',
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
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
