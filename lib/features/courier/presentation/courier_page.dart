import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/widgets/account_session_action_button.dart';
import '../domain/courier_route_plan.dart';

class CourierPage extends ConsumerStatefulWidget {
  const CourierPage({super.key});

  @override
  ConsumerState<CourierPage> createState() => _CourierPageState();
}

class _CourierPageState extends ConsumerState<CourierPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _assignments;
  Object? _assignmentsError;
  bool _assignmentsLoading = true;
  StreamSubscription<Position>? _locationSubscription;
  bool _sharingLocation = false;
  bool _locationStarting = false;
  bool _locationInFlight = false;
  bool _locationErrorShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadInitialAssignments());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshAssignmentsAfterResume());
    }
  }

  Future<void> _loadInitialAssignments() async {
    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) {
      if (mounted) {
        setState(() {
          _assignments = const [];
          _assignmentsLoading = false;
          _assignmentsError = null;
        });
      }
      return;
    }

    try {
      final assignments = await repo.assignments();
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _assignmentsLoading = false;
        _assignmentsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _assignmentsError = error;
        _assignmentsLoading = false;
      });
    }
  }

  /// Refreshes assignments after returning to the foreground. The server
  /// remains authoritative for every GPS write; this refresh also stops the
  /// local stream promptly when the last active assignment ended in background.
  Future<void> _refreshAssignmentsAfterResume() async {
    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) return;

    setState(() => _assignmentsLoading = true);
    try {
      final assignments = await repo.assignments();
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _assignmentsError = null;
        _assignmentsLoading = false;
      });

      if (_sharingLocation && CourierRoutePlan.build(assignments).isEmpty) {
        await _stopLocation(
          message:
              'Votre dernière mission est terminée. Le partage GPS est arrêté.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _assignmentsLoading = false);
      _showLocationMessage(
        'Impossible de rafraîchir vos missions. Le serveur continue de '
        'vérifier chaque position GPS avant de l’accepter.',
      );
    }
  }

  Future<void> _toggleLocation() async {
    if (_sharingLocation) {
      await _stopLocation(
        message: 'Le partage de votre position est arrêté.',
      );
      return;
    }

    if (_locationStarting) return;
    setState(() => _locationStarting = true);

    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) {
      _showLocationMessage('Service de livraison indisponible.');
      if (mounted) setState(() => _locationStarting = false);
      return;
    }

    try {
      final assignments = await repo.assignments();
      if (!mounted) return;
      if (CourierRoutePlan.build(assignments).isEmpty) {
        _showLocationMessage(
          'Aucune mission active : la position ne peut pas être partagée.',
        );
        return;
      }

      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Partager votre position'),
          content: const Text(
            'Pendant une mission active, votre position GPS sera transmise '
            'régulièrement pour permettre au client de suivre la livraison. '
            'Le suivi peut continuer lorsque l’application est en arrière-plan. '
            'Pour cela, le téléphone demandera l’autorisation de localisation '
            '« Toujours » ou « Autoriser tout le temps ». Android affiche une '
            'notification persistante. Vous pouvez arrêter le partage à tout '
            'moment ; il s’arrête aussi quand vous n’avez plus de mission active.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Pas maintenant'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Autoriser le suivi'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) return;

      await DeviceLocationService.ensureBackgroundTrackingPermission();
      if (!mounted) return;

      setState(() {
        _sharingLocation = true;
        _locationErrorShown = false;
      });

      _locationSubscription = DeviceLocationService.positionStream().listen(
        (position) => unawaited(_recordLocation(position)),
        onError: (Object error) {
          unawaited(
            _stopLocation(
              message:
                  'Le GPS a interrompu le suivi. Réactivez-le pour reprendre '
                  'la transmission de position.',
            ),
          );
        },
      );
    } catch (error) {
      final subscription = _locationSubscription;
      _locationSubscription = null;
      await subscription?.cancel();

      if (!mounted) return;
      // A stream factory/listen error (for example on a web build) must not
      // leave the UI showing an active GPS session without a live subscription.
      if (_sharingLocation) {
        setState(() => _sharingLocation = false);
      }
      _locationInFlight = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Localisation indisponible. Vérifiez le GPS et les autorisations de localisation.'),
          action: SnackBarAction(
            label: 'Paramètres',
            onPressed: () async {
              await Geolocator.openAppSettings();
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locationStarting = false);
    }
  }

  Future<void> _recordLocation(Position position) async {
    if (!_sharingLocation || _locationInFlight) return;

    final repo = ref.read(courierRepositoryProvider);
    if (repo == null) {
      await _stopLocation(
        message: 'Le service de livraison est indisponible.',
      );
      return;
    }

    _locationInFlight = true;
    try {
      await repo.recordLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      _locationErrorShown = false;
    } catch (error) {
      if (error.toString().contains('active_courier_assignment_required')) {
        await _stopLocation(
          message:
              'Votre mission est terminée ou annulée. Le partage GPS est arrêté.',
        );
      } else if (!_locationErrorShown && mounted) {
        _locationErrorShown = true;
        _showLocationMessage(
          'Position non transmise. Vérifiez votre connexion ; le suivi '
          'reprendra à la prochaine mesure GPS.',
        );
      }
    } finally {
      _locationInFlight = false;
    }
  }

  Future<void> _stopLocation({String? message}) async {
    final subscription = _locationSubscription;
    _locationSubscription = null;
    await subscription?.cancel();

    if (!mounted) return;
    if (_sharingLocation) {
      setState(() => _sharingLocation = false);
    }
    if (message != null) _showLocationMessage(message);
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
        await repo.accept(CourierRoutePlan.requireAssignmentId(assignment));
      } else if (action == 'pickup') {
        final pickupEvidenceConfirmed = await _confirmEvidenceCapture(
          'Photographiez uniquement l’article remis par le vendeur. Évitez tout visage et toute donnée personnelle.',
        );
        if (!mounted || !pickupEvidenceConfirmed) return;
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
          maxWidth: 1600,
        );
        if (!mounted || photo == null) return;
        await repo.uploadEvidence(
          packageId: packageId,
          file: photo,
          evidenceType: 'PICKUP',
        );
        if (!mounted) return;
        final code = await _askCode('Code de retrait', 4);
        if (!mounted || code == null) return;
        await repo.confirmPickup(packageId: packageId, pickupCode: code);
      } else if (action == 'start') {
        await repo.start(packageId);
      } else if (action == 'deliver') {
        final deliveryEvidenceConfirmed = await _confirmEvidenceCapture(
          'Photographiez le colis déposé ou remis. Ne photographiez pas le visage du client sans son accord.',
        );
        if (!mounted || !deliveryEvidenceConfirmed) return;
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
          maxWidth: 1600,
        );
        if (!mounted || photo == null) return;
        final privacy = await _confirmPhotoPrivacy();
        if (!mounted || privacy == null) return;
        await repo.uploadEvidence(
          packageId: packageId,
          file: photo,
          evidenceType: 'DELIVERY',
          personVisible: privacy['person_visible'] ?? false,
          personConsent: privacy['person_consent'] ?? false,
        );
        if (!mounted) return;
        final code = await _askCode('Code de confirmation du client', 6);
        if (!mounted || code == null) return;
        await repo.confirmDelivery(packageId: packageId, deliveryCode: code);
      }

      if (!mounted) return;
      final remainingAssignments = await repo.assignments();
      if (!mounted) return;

      if (CourierRoutePlan.build(remainingAssignments).isEmpty &&
          _sharingLocation) {
        await _stopLocation(
          message:
              'Vous n’avez plus de mission active. Le partage GPS est arrêté.',
        );
      }
      if (!mounted) return;
      setState(() {
        _assignments = remainingAssignments;
        _assignmentsError = null;
        _assignmentsLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mise à jour enregistrée.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeBackendErrorMessage(error, fallback: 'Action coursier impossible. Vérifiez votre mission et réessayez.'))),
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
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace livreur'),
        actions: [
          IconButton(
            tooltip: _locationStarting
                ? 'Activation du suivi GPS'
                : (_sharingLocation
                    ? 'Arrêter le partage de position'
                    : 'Partager ma position'),
            onPressed: _locationStarting ? null : _toggleLocation,
            icon: _locationStarting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _sharingLocation
                        ? Icons.location_on
                        : Icons.location_off_outlined,
                  ),
          ),
          const AccountSessionActionButton(),
        ],
      ),
      body: _assignmentsLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignmentsError != null && _assignments == null
              ? Center(
                  child: Text('Erreur : $_assignmentsError'),
                )
              : _buildAssignments(_assignments ?? const []),
    );
  }

  Widget _buildAssignments(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Aucune livraison affectée.'));
    }

    final routeStops = CourierRoutePlan.build(items);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (routeStops.isNotEmpty) _groupedRouteCard(routeStops),
        for (final item in items) _assignmentCard(item),
      ],
    );
  }

  Widget _groupedRouteCard(List<CourierRouteStop> stops) {
    final packageCount = stops.map((stop) => stop.packageId).toSet().length;
    final completedPickups = stops.where(
      (stop) => stop.kind == 'PICKUP' && stop.completed,
    ).length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.alt_route_outlined),
        title: Text('Tournée groupée • $packageCount colis'),
        subtitle: Text(
          '$completedPickups retrait(s) déjà effectué(s) • '
          '${stops.length} étapes au total',
        ),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Regroupement de toutes les missions affectées à ce compte. '
              'L’ordre proposé place les retraits avant les livraisons ; '
              'il ne calcule pas le trafic ni la distance routière. Chaque '
              'colis conserve sa propre preuve et son code de confirmation.',
            ),
          ),
          for (final stop in stops)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                child: Text(stop.sequence.toString()),
              ),
              title: Text(
                stop.kind == 'PICKUP'
                    ? 'Retrait • colis ${stop.packageId}'
                    : 'Livraison • colis ${stop.packageId}',
              ),
              subtitle: Text(
                stop.address.isEmpty
                    ? 'Adresse non disponible'
                    : stop.address,
              ),
              trailing: stop.completed
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : IconButton(
                      tooltip: 'Ouvrir cette étape dans Maps',
                      onPressed: stop.address.isEmpty &&
                              (stop.latitude == null ||
                                  stop.longitude == null)
                          ? null
                          : () => _openDirections(
                                address: stop.address,
                                latitude: stop.latitude,
                                longitude: stop.longitude,
                              ),
                      icon: const Icon(Icons.directions_outlined),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _assignmentCard(Map<String, dynamic> item) {
    final status = item['status']?.toString();
    final shopAddress = item['shop_address']?.toString() ?? '';
    final shopPhone = item['shop_phone']?.toString() ?? '';
    final deliveryLine = item['delivery_address_line']?.toString() ?? '';
    final deliveryCity = item['delivery_city']?.toString() ?? '';
    final deliveryAddress = [deliveryLine, deliveryCity]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    final deliveryLatitude =
        item['delivery_latitude']?.toString() ?? '';
    final deliveryLongitude =
        item['delivery_longitude']?.toString() ?? '';
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
                'Colis ${item['package_id']?.toString() ?? '-'}',
              ),
              subtitle: Text(
                'État : ${status ?? '-'}\nAffecté le : ${item['assigned_at']?.toString() ?? '-'}',
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
                      Text('Retrait : $shopAddress'),
                      if (shopPhone.isNotEmpty)
                        Text('Téléphone boutique : $shopPhone'),
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
                      Text(
                        'Livraison : ${deliveryAddress.isEmpty
                                ? 'Position GPS disponible'
                                : deliveryAddress}',
                      ),
                      if (recipientName.isNotEmpty)
                        Text('Destinataire : $recipientName'),
                      if (recipientPhone.isNotEmpty)
                        Text('Téléphone : $recipientPhone'),
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
