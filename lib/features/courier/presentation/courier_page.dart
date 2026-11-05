import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/providers/repository_providers.dart';
import '../data/courier_repository.dart';

final courierRepositoryProvider = Provider<CourierRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : CourierRepository(client);
});

class CourierPage extends ConsumerStatefulWidget {
  const CourierPage({super.key});

  @override
  ConsumerState<CourierPage> createState() => _CourierPageState();
}

class _CourierPageState extends ConsumerState<CourierPage> {
  late Future<List<Map<String, dynamic>>> _future;
  Timer? _locationTimer;
  bool _sharingLocation = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) return Future.value(const []);
    return repo.assignments();
  }

  Future<void> _toggleLocation() async {
    if (_sharingLocation) {
      _locationTimer?.cancel();
      setState(() => _sharingLocation = false);
      return;
    }

    try {
      await _recordLocation();
      _locationTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _recordLocation(),
      );
      setState(() => _sharingLocation = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Localisation indisponible : ' + error.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _recordLocation() async {
    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) return;

    final Position position = await DeviceLocationService.current();

    await repo.recordLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  Future<bool> _confirmEvidenceCapture(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Photo obligatoire du colis'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<Map<String, bool>?> _confirmPhotoPrivacy() async {
    return showDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vérifier la confidentialité'),
        content: const Text(
          'Si un visage apparaît, remettez le téléphone au client pour qu’il confirme lui-même son accord. Sans accord, reprenez la photo sans visage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Reprendre la photo'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'person_visible': false,
              'person_consent': false,
            }),
            child: const Text('Aucun visage visible'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'person_visible': true,
              'person_consent': true,
            }),
            child: const Text('Le client accepte la photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDirections({
    required String address,
    String? latitude,
    String? longitude,
  }) async {
    final lat = double.tryParse(latitude ?? '');
    final lon = double.tryParse(longitude ?? '');
    final destination = address.trim();

    if ((lat == null || lon == null) && destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse ou coordonnées indisponibles.')),
      );
      return;
    }

    final uri = lat != null && lon != null
        ? Uri.https('www.google.com', '/maps/dir/', {
            'api': '1',
            'destination': '$lat,$lon',
          })
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': destination,
          });

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir l’itinéraire.')),
      );
    }
  }

  Future<void> _action(
    Map<String, dynamic> assignment,
    String action,
  ) async {
    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) return;

    try {
      final packageId = assignment['package_id'].toString();
      if (action == 'accept') {
        await repo.accept(assignment['id'].toString());
      } else if (action == 'pickup') {
        if (!await _confirmEvidenceCapture(
          'Photographiez uniquement l’article remis par le vendeur. Évitez tout visage et toute donnée personnelle.',
        )) return;
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
          maxWidth: 1600,
        );
        if (photo == null) return;
        await repo.uploadEvidence(
          packageId: packageId,
          file: photo,
          evidenceType: 'PICKUP',
        );
        final code = await _askCode('Code de retrait', 4);
        if (code == null) return;
        await repo.confirmPickup(packageId: packageId, pickupCode: code);
      } else if (action == 'start') {
        await repo.start(packageId);
      } else if (action == 'deliver') {
        if (!await _confirmEvidenceCapture(
          'Photographiez le colis déposé ou remis. Ne photographiez pas le visage du client sans son accord.',
        )) return;
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
          maxWidth: 1600,
        );
        if (photo == null) return;
        final privacy = await _confirmPhotoPrivacy();
        if (privacy == null) return;
        await repo.uploadEvidence(
          packageId: packageId,
          file: photo,
          evidenceType: 'DELIVERY',
          personVisible: privacy['person_visible'] ?? false,
          personConsent: privacy['person_consent'] ?? false,
        );
        final code = await _askCode('Code de confirmation du client', 6);
        if (code == null) return;
        await repo.confirmDelivery(packageId: packageId, deliveryCode: code);
      }

      if (!mounted) return;
      setState(() => _future = _load());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mise à jour enregistrée.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action impossible : ' + error.toString())),
      );
    }
  }

  Future<String?> _askCode(String title, int length) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: length,
          decoration: InputDecoration(
            labelText: 'Code à $length chiffres',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length == length && RegExp(r'^\d+$').hasMatch(value)) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace livreur'),
        actions: [
          IconButton(
            tooltip: 'Partager ma position',
            onPressed: _toggleLocation,
            icon: Icon(
              _sharingLocation
                  ? Icons.location_on
                  : Icons.location_off_outlined,
            ),
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
            return Center(
              child: Text('Erreur : ' + snapshot.error.toString()),
            );
          }

          final items =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (items.isEmpty) {
            return const Center(
              child: Text('Aucune livraison affectée.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = items[index];
              final status = item['status']?.toString();

              final shopAddress = item['shop_address']?.toString() ?? '';
              final shopPhone = item['shop_phone']?.toString() ?? '';
              final deliveryLine = item['delivery_address_line']?.toString() ?? '';
              final deliveryCity = item['delivery_city']?.toString() ?? '';
              final deliveryAddress = [deliveryLine, deliveryCity]
                  .where((part) => part.trim().isNotEmpty)
                  .join(', ');
              final deliveryLatitude = item['delivery_latitude']?.toString() ?? '';
              final deliveryLongitude = item['delivery_longitude']?.toString() ?? '';
              final hasDeliveryDestination = deliveryAddress.isNotEmpty ||
                  (deliveryLatitude.isNotEmpty && deliveryLongitude.isNotEmpty);
              final recipientName = item['recipient_name']?.toString() ?? '';
              final recipientPhone = item['recipient_phone']?.toString() ?? '';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(
                          'Colis ' + (item['package_id']?.toString() ?? '-'),
                        ),
                        subtitle: Text(
                          'État : ' +
                              (status ?? '-') +
                              '\nAffecté le : ' +
                              (item['assigned_at']?.toString() ?? '-'),
                        ),
                        trailing: _actions(item, status),
                      ),
                      if (shopAddress.isNotEmpty || hasDeliveryDestination)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (shopAddress.isNotEmpty) ...[
                                Text('Retrait : ' + shopAddress),
                                if (shopPhone.isNotEmpty)
                                  Text('Téléphone boutique : ' + shopPhone),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _openDirections(
                                      address: shopAddress,
                                    ),
                                    icon: const Icon(Icons.store_outlined),
                                    label: const Text('Itinéraire vers la boutique'),
                                  ),
                                ),
                              ],
                              if (hasDeliveryDestination) ...[
                                Text('Livraison : ' + (deliveryAddress.isEmpty ? 'Position GPS disponible' : deliveryAddress)),
                                Text('Livraison : ' + deliveryAddress),
                                if (recipientName.isNotEmpty)
                                  Text('Destinataire : ' + recipientName),
                                if (recipientPhone.isNotEmpty)
                                  Text('Téléphone : ' + recipientPhone),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _openDirections(
                                      address: deliveryAddress,
                                      latitude: deliveryLatitude,
                                      longitude: deliveryLongitude,
                                    ),
                                    icon: const Icon(Icons.directions_outlined),
                                    label: const Text('Itinéraire vers le client'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _actions(
    Map<String, dynamic> item,
    String? status,
  ) {
    if (status == 'ASSIGNED') {
      return FilledButton(
        onPressed: () => _action(item, 'accept'),
        child: const Text('Accepter'),
      );
    }

    if (status == 'ACCEPTED') {
      return FilledButton.tonal(
        onPressed: () => _action(item, 'pickup'),
        child: const Text('Photo + retrait'),
      );
    }

    if (status == 'PICKED_UP') {
      return FilledButton.tonal(
        onPressed: () => _action(item, 'start'),
        child: const Text('Démarrer'),
      );
    }

    if (status == 'IN_TRANSIT') {
      return FilledButton(
        onPressed: () => _action(item, 'deliver'),
        child: const Text('Livrer le colis'),
      );
    }

    return const Icon(Icons.check_circle_outline);
  }
}
