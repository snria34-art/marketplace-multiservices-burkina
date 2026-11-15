import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/providers/repository_providers.dart';
import '../data/vertical_repository.dart';

final verticalRepositoryProvider = Provider<VerticalRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : VerticalRepository(client);
});

class VerticalDiscoveryPage extends ConsumerStatefulWidget {
  const VerticalDiscoveryPage({
    required this.module,
    super.key,
  });

  final VerticalModule module;

  @override
  ConsumerState<VerticalDiscoveryPage> createState() =>
      _VerticalDiscoveryPageState();
}

class _VerticalDiscoveryPageState
    extends ConsumerState<VerticalDiscoveryPage> {
  late Future<List<Map<String, dynamic>>> _future;

  VerticalConfig get config => VerticalRepository.configs[widget.module]!;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final repo = ref.read(verticalRepositoryProvider);
    return repo?.list(widget.module) ?? Future.value(const []);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  bool get _requiresAuth =>
      widget.module == VerticalModule.rides ||
      widget.module == VerticalModule.freight ||
      widget.module == VerticalModule.parcels;

  Future<bool> _ensureAuth() async {
    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser != null) return true;
    _info('Connectez-vous pour continuer.');
    return false;
  }

  Future<void> _act(Map<String, dynamic> item) async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null) return;
    if (!await _ensureAuth() || !mounted) return;

    try {
      switch (widget.module) {
        case VerticalModule.rides:
          await _requestRide(repo);
          break;
        case VerticalModule.events:
          final quantity = await _quantityDialog('Nombre de billets');
          if (!mounted || quantity == null) return;
          final id = await repo.reserveEvent(
            eventId: item['id'].toString(),
            quantity: quantity,
          );
          _success('Réservation créée : $id');
          break;
        case VerticalModule.rentals:
          final range = await _dateRangeDialog();
          if (!mounted || range == null) return;
          final id = await repo.bookRental(
            rentalId: item['id'].toString(),
            startsAt: range.start,
            endsAt: range.end,
          );
          _success('Demande de location créée : $id');
          break;
        case VerticalModule.accommodations:
          final rawUnits = item['accommodation_units'];
          if (rawUnits is! List || rawUnits.isEmpty) {
            _info('Aucune chambre/unité disponible.');
            return;
          }
          final units = rawUnits
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final selected = await _unitDialog(units);
          if (!mounted || selected == null) return;
          final stay = await _stayDialog();
          if (!mounted || stay == null) return;
          final guests = await _quantityDialog('Nombre de personnes');
          if (!mounted || guests == null) return;
          final id = await repo.bookAccommodation(
            unitId: selected['id'].toString(),
            checkIn: stay.start,
            checkOut: stay.end,
            guests: guests,
          );
          _success('Demande d’hébergement créée : $id');
          break;
        case VerticalModule.jobs:
          final id = await repo.applyToJob(item['id'].toString());
          _success('Candidature envoyée : $id');
          break;
        case VerticalModule.training:
          final id = await repo.enrollTraining(item['id'].toString());
          _success('Inscription créée : $id');
          break;
        case VerticalModule.digital:
          final id = await repo.orderDigital(item['id'].toString());
          _success('Commande numérique créée : $id');
          break;
        case VerticalModule.beauty:
          final dateTime = await _pickDateTime();
          if (!mounted || dateTime == null) return;
          final id = await repo.bookBeauty(
            serviceId: item['id'].toString(),
            scheduledAt: dateTime,
          );
          _success('Rendez-vous demandé : $id');
          break;
        case VerticalModule.homeServices:
          final dateTime = await _pickDateTime();
          if (!mounted || dateTime == null) return;
          final address = await _addressDialog();
          if (!mounted || address == null) return;
          final id = await repo.requestHomeService(
            serviceId: item['id'].toString(),
            scheduledAt: dateTime,
            address: {'label': address},
          );
          _success('Demande à domicile créée : $id');
          break;
        case VerticalModule.freight:
          await _createFreight(repo);
          break;
        case VerticalModule.parcels:
          await _createParcel(repo);
          break;
        case VerticalModule.health:
          await _requestHealthProduct(item);
          break;
        case VerticalModule.agriculture:
          await _requestAgricultureOrder(item);
          break;
        case VerticalModule.professionals:
          final draft = await _professionalRequestDialog();
          if (!mounted || draft == null) return;
          final id = await repo.createProfessionalServiceRequest(
            professionalProfileId: item['id'].toString(),
            description: draft['description'].toString(),
            scheduledAt: draft['scheduled_at'] as DateTime?,
          );
          _success('Demande de devis envoyée au professionnel : ' + id);
          break;
        case VerticalModule.realEstate:
          final draft = await _realEstateVisitDialog();
          if (!mounted || draft == null) return;
          final id = await repo.requestRealEstateVisit(
            listingId: item['id'].toString(),
            preferredVisitAt: draft['preferred_at'] as DateTime?,
            message: draft['message'] as String?,
          );
          _success('Demande de visite envoyée au propriétaire : $id');
          break;
        case VerticalModule.creative:
          final id = await repo.requestCreativeBooking(
            serviceId: item['id'].toString(),
          );
          _success('Demande envoyée au prestataire : $id');
          break;
      }
    } catch (error) {
      _info('Opération impossible : $error');
    }
  }

  Future<Map<String, dynamic>?> _realEstateVisitDialog() async {
    final messageController = TextEditingController();
    DateTime? preferredVisitAt;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Demander une visite / des informations'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Le propriétaire recevra votre demande et devra la confirmer. '
                  'La date souhaitée reste une préférence, pas un rendez-vous garanti.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 180)),
                      initialDate: now.add(const Duration(days: 1)),
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time == null || !mounted) return;
                    final selected = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    if (!selected.isAfter(DateTime.now())) {
                      _info('Choisissez une date et une heure futures.');
                      return;
                    }
                    setDialogState(() => preferredVisitAt = selected);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    preferredVisitAt == null
                        ? 'Choisir une date souhaitée (facultatif)'
                        : 'Date : ' +
                            preferredVisitAt!.toLocal().toString().substring(0, 16),
                  ),
                ),
                if (preferredVisitAt != null)
                  TextButton(
                    onPressed: () => setDialogState(() => preferredVisitAt = null),
                    child: const Text('Retirer la date'),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Votre message (facultatif)',
                    hintText: 'Précisez votre demande ou vos questions...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final message = messageController.text.trim();
                Navigator.pop(dialogContext, {
                  'preferred_at': preferredVisitAt,
                  'message': message.isEmpty ? null : message,
                });
              },
              child: const Text('Envoyer la demande'),
            ),
          ],
        ),
      ),
    );

    messageController.dispose();
    return result;
  }

  Future<void> _showMyRealEstateVisitRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;

    try {
      final requests = await repo.myRealEstateVisitRequests();
      if (!mounted) return;
      if (requests.isEmpty) {
        _info('Vous n’avez aucune demande immobilière pour le moment.');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes demandes immobilières'),
          content: SizedBox(
            width: 520,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: requests.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final request = requests[index];
                final status = request['status']?.toString() ?? '-';
                final preferred = request['preferred_visit_at']?.toString();
                final message = request['message']?.toString();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    request['listing_title']?.toString() ?? 'Annonce immobilière',
                  ),
                  subtitle: Text(
                    'Statut : ' + _realEstateStatus(status) +
                    (request['city'] == null ? '' : '\nVille : ' + request['city'].toString()) +
                    (preferred == null ? '' : '\nDate souhaitée : ' + preferred) +
                    (message == null || message.isEmpty ? '' : '\nMessage : ' + message),
                  ),
                  isThreeLine: true,
                  trailing: status == 'REQUESTED'
                      ? IconButton(
                          tooltip: 'Annuler la demande',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () async {
                            try {
                              await repo.cancelRealEstateVisit(
                                request['request_id'].toString(),
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Demande immobilière annulée.');
                              await _showMyRealEstateVisitRequests();
                            } catch (error) {
                              _info('Annulation impossible : ' + error.toString());
                            }
                          },
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes immobilières impossible : ' + error.toString());
    }
  }

  Future<void> _showProviderRealEstateVisitRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;

    try {
      final requests = await repo.providerRealEstateVisitRequests();
      if (!mounted) return;
      if (requests.isEmpty) {
        _info('Aucune demande de visite reçue pour vos annonces.');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Demandes reçues pour mes annonces'),
          content: SizedBox(
            width: 540,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: requests.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final request = requests[index];
                final status = request['status']?.toString() ?? '-';
                final preferred = request['preferred_visit_at']?.toString();
                final message = request['message']?.toString();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    request['listing_title']?.toString() ?? 'Annonce immobilière',
                  ),
                  subtitle: Text(
                    'Statut : ' + _realEstateStatus(status) +
                    (request['city'] == null ? '' : '\nVille : ' + request['city'].toString()) +
                    (preferred == null ? '' : '\nDate souhaitée : ' + preferred) +
                    (message == null || message.isEmpty ? '' : '\nMessage : ' + message),
                  ),
                  isThreeLine: true,
                  trailing: status == 'REQUESTED'
                      ? Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Refuser',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                final confirmed = await _confirmRealEstateDecision(
                                  title: 'Refuser cette demande ?',
                                  message: 'Le demandeur verra que sa demande a été refusée.',
                                  actionLabel: 'Refuser',
                                );
                                if (!mounted || !confirmed) return;
                                try {
                                  await repo.respondRealEstateVisit(
                                    requestId: request['request_id'].toString(),
                                    decision: 'DECLINE',
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Demande immobilière refusée.');
                                  await _showProviderRealEstateVisitRequests();
                                } catch (error) {
                                  _info('Refus impossible : ' + error.toString());
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Accepter la demande',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () async {
                                final confirmed = await _confirmRealEstateDecision(
                                  title: 'Accepter cette demande ?',
                                  message: 'Vous confirmez la demande de visite. L’heure exacte devra encore être coordonnée avec le demandeur.',
                                  actionLabel: 'Accepter',
                                );
                                if (!mounted || !confirmed) return;
                                try {
                                  await repo.respondRealEstateVisit(
                                    requestId: request['request_id'].toString(),
                                    decision: 'ACCEPT',
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Demande acceptée. Coordonnez l’heure exacte avec le demandeur.');
                                  await _showProviderRealEstateVisitRequests();
                                } catch (error) {
                                  _info('Acceptation impossible : ' + error.toString());
                                }
                              },
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes reçues impossible : ' + error.toString());
    }
  }

  Future<bool> _confirmRealEstateDecision({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  String _realEstateStatus(String status) {
    switch (status) {
      case 'REQUESTED':
        return 'En attente';
      case 'ACCEPTED':
        return 'Acceptée';
      case 'DECLINED':
        return 'Refusée';
      case 'CANCELLED':
        return 'Annulée';
      default:
        return status;
    }
  }

  Future<Map<String, dynamic>?> _professionalRequestDialog() async {
    final description = TextEditingController();
    DateTime? scheduledAt;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Demander un devis'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: description,
                  maxLines: 4,
                  maxLength: 2000,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Décrivez votre besoin',
                    border: OutlineInputBorder(),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(scheduledAt == null
                      ? 'Date souhaitée (facultatif)'
                      : 'Date : ' + scheduledAt!.toLocal().toString().substring(0, 16)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 180)),
                      initialDate: now.add(const Duration(days: 1)),
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time == null || !mounted) return;
                    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                    if (!value.isAfter(DateTime.now())) {
                      _info('Choisissez une date future.');
                      return;
                    }
                    setDialogState(() => scheduledAt = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: description.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'description': description.text.trim(),
                        'scheduled_at': scheduledAt,
                      }),
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    description.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _professionalQuoteDialog() async {
    final amount = TextEditingController();
    final message = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Proposer un devis'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Montant en XOF'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: message,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Détails (facultatif)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: num.tryParse(amount.text.trim()) == null ||
                      num.parse(amount.text.trim()) < 0
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'amount': num.parse(amount.text.trim()),
                        'message': message.text.trim(),
                      }),
              child: const Text('Envoyer le devis'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    message.dispose();
    return result;
  }

  Future<num?> _agricultureOrderQuantityDialog({
    required num available,
    required String unit,
  }) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Commander ce produit agricole'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock disponible : ' + available.toString() + ' ' + unit),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantité en ' + unit),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final value = num.tryParse(controller.text.trim());
              if (value != null && value > 0 && value <= available) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Réserver le stock'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _agricultureListingDialog({
    Map<String, dynamic>? initial,
  }) async {
    final editing = initial != null;
    final name = TextEditingController(text: initial?['name']?.toString() ?? '');
    final description = TextEditingController(text: initial?['description']?.toString() ?? '');
    final price = TextEditingController(text: initial?['price']?.toString() ?? '');
    final unit = TextEditingController(text: initial?['unit']?.toString() ?? 'kg');
    final quantity = TextEditingController(text: initial?['quantity']?.toString() ?? '');
    var listingType = initial?['listing_type']?.toString() ?? 'PRODUCE';
    var active = initial?['active'] == true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(editing ? 'Modifier mon annonce agricole' : 'Nouvelle annonce agricole'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: listingType,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: const [
                      DropdownMenuItem(value: 'PRODUCE', child: Text('Produits agricoles')),
                      DropdownMenuItem(value: 'LIVESTOCK', child: Text('Bétail / élevage')),
                      DropdownMenuItem(value: 'SEEDS', child: Text('Semences')),
                      DropdownMenuItem(value: 'EQUIPMENT', child: Text('Équipements')),
                      DropdownMenuItem(value: 'INPUTS', child: Text('Intrants')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => listingType = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: name, maxLength: 160, onChanged: (_) => setDialogState(() {}), decoration: const InputDecoration(labelText: 'Nom du produit ou matériel')),
                  TextField(controller: description, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(labelText: 'Description (facultatif)')),
                  TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setDialogState(() {}), decoration: const InputDecoration(labelText: 'Prix unitaire en XOF')),
                  TextField(controller: unit, maxLength: 32, onChanged: (_) => setDialogState(() {}), decoration: const InputDecoration(labelText: 'Unité (kg, sac, tête, pièce...)')),
                  TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setDialogState(() {}), decoration: const InputDecoration(labelText: 'Quantité totale en stock')),
                  if (editing)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Annonce visible'),
                      value: active,
                      onChanged: (value) => setDialogState(() => active = value),
                    ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('La quantité ne peut pas être réduite sous le stock déjà réservé.', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: name.text.trim().isEmpty ||
                      num.tryParse(price.text.trim()) == null ||
                      num.tryParse(quantity.text.trim()) == null ||
                      unit.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'listing_type': listingType,
                        'name': name.text.trim(),
                        'description': description.text.trim(),
                        'price': num.parse(price.text.trim()),
                        'unit': unit.text.trim(),
                        'quantity': num.parse(quantity.text.trim()),
                        'active': active,
                      }),
              child: Text(editing ? 'Enregistrer' : 'Publier'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    price.dispose();
    unit.dispose();
    quantity.dispose();
    return result;
  }

  Future<void> _createAgricultureListing() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    final draft = await _agricultureListingDialog();
    if (!mounted || draft == null) return;
    try {
      final id = await repo.createAgricultureListing(
        listingType: draft['listing_type'].toString(),
        name: draft['name'].toString(),
        description: draft['description'].toString(),
        price: draft['price'] as num,
        unit: draft['unit'].toString(),
        quantity: draft['quantity'] as num,
      );
      _success('Annonce agricole créée : ' + id);
      await _showMyAgricultureListings();
    } catch (error) {
      _info('Publication impossible : ' + error.toString());
    }
  }

  Future<void> _showMyAgricultureListings() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final listings = await repo.myAgricultureListings();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes annonces agricoles'),
          content: SizedBox(
            width: 560,
            child: listings.isEmpty
                ? const Text('Aucune annonce. La publication est réservée aux vendeurs dont le compte et la vérification sont actifs.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: listings.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, index) {
                      final listing = listings[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(listing['name']?.toString() ?? 'Annonce'),
                        subtitle: Text(
                          (listing['price']?.toString() ?? '-') + ' XOF / ' + (listing['unit']?.toString() ?? '-') +
                          '\nStock libre : ' + (listing['available_quantity']?.toString() ?? '0') +
                          '\nRéservé : ' + (listing['reserved_quantity']?.toString() ?? '0') +
                          '\nStatut : ' + (listing['active'] == true ? 'Visible' : 'Masquée'),
                        ),
                        trailing: IconButton(
                          tooltip: 'Modifier l’annonce',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final draft = await _agricultureListingDialog(initial: listing);
                            if (!mounted || draft == null) return;
                            try {
                              await repo.updateAgricultureListing(
                                listingId: listing['listing_id'].toString(),
                                listingType: draft['listing_type'].toString(),
                                name: draft['name'].toString(),
                                description: draft['description'].toString(),
                                price: draft['price'] as num,
                                unit: draft['unit'].toString(),
                                quantity: draft['quantity'] as num,
                                active: draft['active'] == true,
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Annonce agricole mise à jour.');
                              await _showMyAgricultureListings();
                            } catch (error) {
                              _info('Modification impossible : ' + error.toString());
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _createAgricultureListing();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle annonce'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des annonces impossible : ' + error.toString());
    }
  }

  Future<void> _showMyAgricultureOrderRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final orders = await repo.myAgricultureOrderRequests();
      if (!mounted) return;
      if (orders.isEmpty) {
        _info('Vous n’avez aucune commande agricole.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes commandes agricoles'),
          content: SizedBox(
            width: 560,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? '-';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(order['listing_name']?.toString() ?? 'Produit agricole'),
                  subtitle: Text(
                    (order['quantity']?.toString() ?? '-') + ' ' + (order['unit']?.toString() ?? '') +
                    ' • ' + (order['total_amount']?.toString() ?? '-') + ' XOF' +
                    '\nVendeur : ' + (order['seller_name']?.toString() ?? 'Vendeur') +
                    '\nStatut : ' + _agricultureStatus(status),
                  ),
                  trailing: ['REQUESTED', 'ACCEPTED'].contains(status)
                      ? IconButton(
                          tooltip: 'Annuler la commande',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () async {
                            try {
                              await repo.cancelAgricultureOrderRequest(order['order_id'].toString());
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Commande annulée et stock libéré.');
                              await _showMyAgricultureOrderRequests();
                            } catch (error) {
                              _info('Annulation impossible : ' + error.toString());
                            }
                          },
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des commandes impossible : ' + error.toString());
    }
  }

  Future<void> _showSellerAgricultureOrderRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final orders = await repo.sellerAgricultureOrderRequests();
      if (!mounted) return;
      if (orders.isEmpty) {
        _info('Aucune commande agricole reçue pour vos annonces.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Commandes agricoles reçues'),
          content: SizedBox(
            width: 560,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? '-';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(order['listing_name']?.toString() ?? 'Produit agricole'),
                  subtitle: Text(
                    (order['quantity']?.toString() ?? '-') + ' ' + (order['unit']?.toString() ?? '') +
                    ' • ' + (order['total_amount']?.toString() ?? '-') + ' XOF' +
                    '\nÉtat : ' + _agricultureStatus(status),
                  ),
                  trailing: status == 'REQUESTED'
                      ? Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Refuser et libérer le stock',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                try {
                                  await repo.respondAgricultureOrderRequest(
                                    orderId: order['order_id'].toString(),
                                    decision: 'DECLINE',
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Commande refusée ; stock libéré.');
                                  await _showSellerAgricultureOrderRequests();
                                } catch (error) {
                                  _info('Refus impossible : ' + error.toString());
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Accepter',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () async {
                                try {
                                  await repo.respondAgricultureOrderRequest(
                                    orderId: order['order_id'].toString(),
                                    decision: 'ACCEPT',
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Commande acceptée. Le stock reste réservé.');
                                  await _showSellerAgricultureOrderRequests();
                                } catch (error) {
                                  _info('Acceptation impossible : ' + error.toString());
                                }
                              },
                            ),
                          ],
                        )
                      : status == 'ACCEPTED'
                          ? IconButton(
                              tooltip: 'Marquer comme remise effectuée',
                              icon: const Icon(Icons.inventory_2_outlined),
                              onPressed: () async {
                                try {
                                  await repo.fulfillAgricultureOrderRequest(order['order_id'].toString());
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Commande clôturée ; stock vendu déduit.');
                                  await _showSellerAgricultureOrderRequests();
                                } catch (error) {
                                  _info('Clôture impossible : ' + error.toString());
                                }
                              },
                            )
                          : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des commandes reçues impossible : ' + error.toString());
    }
  }

  Future<void> _requestAgricultureOrder(Map<String, dynamic> item) async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    final available = item['available_quantity'];
    if (available is! num) {
      _info('Ce produit n’a pas de stock quantifié. Contactez le vendeur.');
      return;
    }
    if (available <= 0) {
      _info('Ce produit est momentanément indisponible.');
      return;
    }
    final unit = item['unit']?.toString() ?? 'unité';
    final requested = await _agricultureOrderQuantityDialog(available: available, unit: unit);
    if (!mounted || requested == null) return;
    try {
      final id = await repo.createAgricultureOrderRequest(
        listingId: item['id'].toString(),
        quantity: requested,
      );
      _success('Stock réservé. En attente de la réponse du vendeur : ' + id);
    } catch (error) {
      _info('Réservation impossible : ' + error.toString());
    }
  }

  String _agricultureStatus(String status) {
    switch (status) {
      case 'REQUESTED': return 'En attente du vendeur';
      case 'ACCEPTED': return 'Acceptée';
      case 'REJECTED': return 'Refusée';
      case 'CANCELLED': return 'Annulée';
      case 'FULFILLED': return 'Remise effectuée';
      default: return status;
    }
  }

  Future<Map<String, dynamic>?> _healthOrderDialog(
    Map<String, dynamic> item,
    num available,
  ) async {
    final quantityController = TextEditingController(text: '1');
    final requiresPrescription = item['requires_prescription'] == true;
    XFile? prescription;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Commander auprès de la pharmacie'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stock disponible : ' + available.toString()),
                const SizedBox(height: 8),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantité (boîtes / unités)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (requiresPrescription) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Ordonnance obligatoire. Joignez une photo nette et lisible. Elle sera envoyée dans un espace privé accessible uniquement à vous et à la pharmacie concernée.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 90,
                          );
                          if (picked != null && mounted) {
                            setDialogState(() => prescription = picked);
                          }
                        },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galerie'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(
                            source: ImageSource.camera,
                            imageQuality: 90,
                          );
                          if (picked != null && mounted) {
                            setDialogState(() => prescription = picked);
                          }
                        },
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Photographier'),
                      ),
                    ],
                  ),
                  if (prescription != null)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        prescription!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('Photo prête à être envoyée'),
                      trailing: IconButton(
                        tooltip: 'Retirer la photo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setDialogState(() => prescription = null),
                      ),
                    ),
                  const Text(
                    'Formats acceptés : JPEG et PNG. Les PDF ne sont pas encore pris en charge dans cette version.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final quantity = int.tryParse(quantityController.text.trim());
                if (quantity == null ||
                    quantity < 1 ||
                    quantity > 50 ||
                    quantity > available ||
                    (requiresPrescription && prescription == null)) {
                  return;
                }
                Navigator.pop(dialogContext, {
                  'quantity': quantity,
                  'prescription': prescription,
                });
              },
              child: const Text('Envoyer la demande'),
            ),
          ],
        ),
      ),
    );

    quantityController.dispose();
    return result;
  }

  Future<void> _requestHealthProduct(Map<String, dynamic> item) async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    if (item['provider_type']?.toString() != 'PHARMACY') {
      _info('Seules les pharmacies vérifiées peuvent traiter une commande de produit dans ce parcours.');
      return;
    }
    final available = item['available_quantity'];
    if (available is! num || available <= 0) {
      _info('Ce produit est momentanément indisponible.');
      return;
    }

    final draft = await _healthOrderDialog(item, available);
    if (!mounted || draft == null) return;
    try {
      final image = draft['prescription'] as XFile?;
      final extension = image?.name.toLowerCase() ?? '';
      if (image != null &&
          !extension.endsWith('.png') &&
          !extension.endsWith('.jpg') &&
          !extension.endsWith('.jpeg')) {
        _info('Format de photo non pris en charge. Utilisez une image JPEG ou PNG.');
        return;
      }
      final bytes = image == null ? null : await image.readAsBytes();
      if (bytes != null && bytes.length > 10 * 1024 * 1024) {
        _info('La photo de l’ordonnance dépasse la limite de 10 Mo.');
        return;
      }
      final mimeType = image == null
          ? null
          : extension.endsWith('.png')
              ? 'image/png'
              : 'image/jpeg';

      final id = await repo.createHealthOrderRequest(
        productId: item['id'].toString(),
        quantity: draft['quantity'] as int,
        prescriptionBytes: bytes,
        prescriptionMimeType: mimeType,
      );
      _success(
        item['requires_prescription'] == true
            ? 'Demande envoyée. La pharmacie doit examiner l’ordonnance avant toute délivrance : ' + id
            : 'Demande envoyée à la pharmacie : ' + id,
      );
      await _showMyHealthOrders();
    } catch (error) {
      _info('Demande de santé impossible : ' + error.toString());
    }
  }

  Future<void> _showMyHealthOrders() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final orders = await repo.myHealthOrderRequests();
      if (!mounted) return;
      if (orders.isEmpty) {
        _info('Vous n’avez aucune demande de santé pour le moment.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes demandes de santé'),
          content: SizedBox(
            width: 560,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? '-';
                final canCancel = [
                  'PENDING_REVIEW',
                  'REQUESTED',
                  'APPROVED_FOR_DISPENSING',
                  'ACCEPTED',
                ].contains(status);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    order['product_name']?.toString() ?? 'Produit de santé',
                  ),
                  subtitle: Text(
                    (order['provider_name']?.toString() ?? 'Pharmacie') +
                    '\nQuantité : ' + (order['quantity']?.toString() ?? '-') +
                    '\nTotal : ' + (order['total_amount']?.toString() ?? '-') + ' XOF' +
                    '\nStatut : ' + _healthOrderStatus(status) +
                    (order['review_note'] == null ||
                            order['review_note'].toString().isEmpty
                        ? ''
                        : '\nNote pharmacie : ' + order['review_note'].toString()),
                  ),
                  isThreeLine: true,
                  trailing: canCancel
                      ? IconButton(
                          tooltip: 'Annuler et libérer le stock',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () async {
                            try {
                              await repo.cancelHealthOrderRequest(
                                order['request_id'].toString(),
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Demande annulée ; le stock réservé a été libéré.');
                              await _showMyHealthOrders();
                            } catch (error) {
                              _info('Annulation impossible : ' + error.toString());
                            }
                          },
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes de santé impossible : ' + error.toString());
    }
  }

  String _healthOrderStatus(String status) {
    switch (status) {
      case 'PENDING_REVIEW':
        return 'Ordonnance à examiner';
      case 'REQUESTED':
        return 'En attente de la pharmacie';
      case 'APPROVED_FOR_DISPENSING':
        return 'Ordonnance validée — remise à organiser';
      case 'ACCEPTED':
        return 'Acceptée — remise à organiser';
      case 'REJECTED':
        return 'Refusée';
      case 'CANCELLED':
        return 'Annulée';
      case 'EXPIRED':
        return 'Expirée';
      case 'DISPENSED':
        return 'Produit remis';
      default:
        return status;
    }
  }

  Future<String?> _healthReviewNoteDialog({
    required String title,
    required String actionLabel,
    required bool requiredNote,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 1000,
            onChanged: (_) => setDialogState(() {}),
            decoration: InputDecoration(
              labelText: requiredNote ? 'Motif obligatoire' : 'Note (facultative)',
              hintText: requiredNote ? 'Expliquez brièvement le refus...' : 'Information destinée au client...',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: requiredNote && controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _reviewHealthOrder(
    Map<String, dynamic> order, {
    required String decision,
  }) async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null) return;
    final rejecting = decision == 'REJECT';
    final note = await _healthReviewNoteDialog(
      title: rejecting
          ? 'Motif du refus'
          : decision == 'APPROVE'
              ? 'Valider l’ordonnance'
              : 'Accepter la demande',
      actionLabel: rejecting
          ? 'Refuser la demande'
          : decision == 'APPROVE'
              ? 'Valider'
              : 'Accepter',
      requiredNote: rejecting,
    );
    if (!mounted || note == null) return;
    try {
      await repo.respondHealthOrderRequest(
        requestId: order['request_id'].toString(),
        decision: decision,
        reviewNote: note,
      );
      _success(
        rejecting
            ? 'Demande refusée et stock libéré.'
            : decision == 'APPROVE'
                ? 'Ordonnance validée. La remise du produit reste une étape séparée.'
                : 'Demande acceptée. La remise du produit reste une étape séparée.',
      );
      await _showPharmacyHealthOrders();
    } catch (error) {
      _info('Décision impossible : ' + error.toString());
    }
  }

  Future<void> _openHealthPrescription(String path) async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null) return;
    try {
      final url = await repo.createHealthPrescriptionSignedUrl(path);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _info('Impossible d’ouvrir l’ordonnance.');
    } catch (error) {
      _info('Accès à l’ordonnance refusé ou indisponible : ' + error.toString());
    }
  }

  Future<void> _showPharmacyHealthOrders() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final orders = await repo.pharmacyHealthOrderRequests();
      if (!mounted) return;
      if (orders.isEmpty) {
        _info('Aucune demande de santé reçue pour cette pharmacie.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Demandes reçues par la pharmacie'),
          content: SizedBox(
            width: 620,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? '-';
                final requiresPrescription = order['requires_prescription'] == true;
                final isReview = status == 'PENDING_REVIEW';
                final isRequest = status == 'REQUESTED';
                final canDispense = status == 'ACCEPTED' ||
                    status == 'APPROVED_FOR_DISPENSING';
                final path = order['prescription_path']?.toString();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(order['product_name']?.toString() ?? 'Produit de santé'),
                      subtitle: Text(
                        (order['quantity']?.toString() ?? '-') +
                        ' unité(s) • ' +
                        (order['total_amount']?.toString() ?? '-') + ' XOF' +
                        '\nStatut : ' + _healthOrderStatus(status) +
                        (requiresPrescription
                            ? '\nOrdonnance obligatoire'
                            : '\nSans ordonnance'),
                      ),
                    ),
                    if (path != null && path.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openHealthPrescription(path),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Ouvrir l’ordonnance (lien temporaire)'),
                        ),
                      ),
                    if (isReview || isRequest)
                      Wrap(
                        spacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: () => _reviewHealthOrder(
                              order,
                              decision: 'REJECT',
                            ),
                            icon: const Icon(Icons.close),
                            label: const Text('Refuser'),
                          ),
                          FilledButton.icon(
                            onPressed: () => _reviewHealthOrder(
                              order,
                              decision: isReview ? 'APPROVE' : 'ACCEPT',
                            ),
                            icon: const Icon(Icons.check),
                            label: Text(
                              isReview ? 'Valider l’ordonnance' : 'Accepter',
                            ),
                          ),
                        ],
                      ),
                    if (canDispense)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (confirmContext) => AlertDialog(
                                title: const Text('Confirmer la remise ?'),
                                content: const Text(
                                  'Cette action marque le produit comme remis au client et déduit la quantité du stock. Elle ne déclenche aucun paiement.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(confirmContext, false),
                                    child: const Text('Retour'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(confirmContext, true),
                                    child: const Text('Confirmer la remise'),
                                  ),
                                ],
                              ),
                            );
                            if (!mounted || confirm != true) return;
                            try {
                              await repo.fulfillHealthOrderRequest(
                                order['request_id'].toString(),
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Remise enregistrée ; stock déduit.');
                              await _showPharmacyHealthOrders();
                            } catch (error) {
                              _info('Clôture impossible : ' + error.toString());
                            }
                          },
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Marquer comme remis'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes pharmacie impossible : ' + error.toString());
    }
  }

  Future<Map<String, dynamic>?> _healthProductDialog({
    Map<String, dynamic>? initial,
  }) async {
    final editing = initial != null;
    final name = TextEditingController(
      text: initial?['name']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: initial?['description']?.toString() ?? '',
    );
    final price = TextEditingController(
      text: initial?['price']?.toString() ?? '',
    );
    final stock = TextEditingController(
      text: initial?['stock_quantity']?.toString() ?? '0',
    );
    var requiresPrescription = initial?['requires_prescription'] == true;
    var active = initial?['active'] == true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            editing ? 'Modifier le produit de santé' : 'Ajouter un produit de santé',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 160,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Nom du médicament / produit',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Description (facultatif)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Prix en XOF',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stock,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Stock total',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ordonnance obligatoire'),
                    value: requiresPrescription,
                    onChanged: (value) {
                      setDialogState(() => requiresPrescription = value);
                    },
                  ),
                  if (editing)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Produit visible'),
                      value: active,
                      onChanged: (value) {
                        setDialogState(() => active = value);
                      },
                    ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Le stock ne peut pas être abaissé sous les quantités déjà réservées.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty ||
                      num.tryParse(price.text.trim()) == null ||
                      int.tryParse(stock.text.trim()) == null
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'name': name.text.trim(),
                        'description': description.text.trim(),
                        'price': num.parse(price.text.trim()),
                        'stock_quantity': int.parse(stock.text.trim()),
                        'requires_prescription': requiresPrescription,
                        'active': active,
                      }),
              child: Text(editing ? 'Enregistrer' : 'Publier'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    description.dispose();
    price.dispose();
    stock.dispose();
    return result;
  }

  Future<void> _createHealthProduct() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    final draft = await _healthProductDialog();
    if (!mounted || draft == null) return;
    try {
      final id = await repo.createHealthProduct(
        name: draft['name'].toString(),
        description: draft['description'].toString(),
        price: draft['price'] as num,
        requiresPrescription: draft['requires_prescription'] == true,
        stockQuantity: draft['stock_quantity'] as int,
      );
      _success('Produit de santé ajouté : ' + id);
      await _showMyHealthProducts();
    } catch (error) {
      _info(
        'Publication impossible. La gestion est réservée aux pharmacies vérifiées et actives : ' +
            error.toString(),
      );
    }
  }

  Future<void> _showMyHealthProducts() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final products = await repo.myHealthProducts();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mon catalogue pharmacie'),
          content: SizedBox(
            width: 560,
            child: products.isEmpty
                ? const Text(
                    'Aucun produit. Cette gestion est réservée aux pharmacies vérifiées et actives.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, index) {
                      final product = products[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(product['name']?.toString() ?? 'Produit'),
                        subtitle: Text(
                          (product['price']?.toString() ?? '-') + ' XOF' +
                          '\nStock libre : ' +
                              (product['available_quantity']?.toString() ?? '0') +
                          '\nRéservé : ' +
                              (product['reserved_quantity']?.toString() ?? '0') +
                          '\nPrescription : ' +
                              (product['requires_prescription'] == true ? 'Oui' : 'Non') +
                          '\nStatut : ' +
                              (product['active'] == true ? 'Visible' : 'Masqué'),
                        ),
                        trailing: IconButton(
                          tooltip: 'Modifier le produit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final draft = await _healthProductDialog(
                              initial: product,
                            );
                            if (!mounted || draft == null) return;
                            try {
                              await repo.updateHealthProduct(
                                productId: product['product_id'].toString(),
                                name: draft['name'].toString(),
                                description: draft['description'].toString(),
                                price: draft['price'] as num,
                                requiresPrescription:
                                    draft['requires_prescription'] == true,
                                stockQuantity: draft['stock_quantity'] as int,
                                active: draft['active'] == true,
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Produit de santé mis à jour.');
                              await _showMyHealthProducts();
                            } catch (error) {
                              _info('Modification impossible : ' + error.toString());
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _createHealthProduct();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement du catalogue pharmacie impossible : ' + error.toString());
    }
  }

  Future<void> _showMyProfessionalRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final rows = await repo.myProfessionalServiceRequests();
      if (!mounted) return;
      if (rows.isEmpty) {
        _info('Vous n’avez aucune demande professionnelle.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes demandes professionnelles'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final request in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(request['profession']?.toString() ?? 'Professionnel'),
                    subtitle: Text(
                      (request['provider_name']?.toString() ?? 'Prestataire') +
                      '\nStatut : ' + _professionalStatus(request['status']?.toString() ?? '-') +
                      (request['scheduled_at'] == null ? '' : '\nDate : ' + request['scheduled_at'].toString()) +
                      '\nBesoin : ' + (request['description']?.toString() ?? '-'),
                    ),
                    trailing: ['REQUESTED', 'QUOTED'].contains(request['status'])
                        ? IconButton(
                            tooltip: 'Annuler la demande',
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () async {
                              try {
                                await repo.cancelProfessionalServiceRequest(request['request_id'].toString());
                                if (!mounted) return;
                                Navigator.pop(dialogContext);
                                _success('Demande annulée.');
                                await _showMyProfessionalRequests();
                              } catch (error) {
                                _info('Annulation impossible : ' + error.toString());
                              }
                            },
                          )
                        : null,
                  ),
                  if (request['quotes'] is List)
                    for (final raw in request['quotes'] as List)
                      if (raw is Map)
                        Builder(builder: (context) {
                          final quote = Map<String, dynamic>.from(raw);
                          final proposed = quote['status']?.toString() == 'PROPOSED';
                          return Card(
                            margin: const EdgeInsets.only(left: 8, bottom: 8),
                            child: ListTile(
                              title: Text('Devis : ' + (quote['amount']?.toString() ?? '-') +
                                  ' ' + (quote['currency']?.toString() ?? 'XOF')),
                              subtitle: Text(
                                _professionalStatus(quote['status']?.toString() ?? '-') +
                                (quote['message'] == null ? '' : '\n' + quote['message'].toString()),
                              ),
                              trailing: proposed
                                  ? Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: 'Refuser',
                                          icon: const Icon(Icons.close),
                                          onPressed: () async {
                                            try {
                                              await repo.respondProfessionalServiceQuote(
                                                quoteId: quote['id'].toString(),
                                                decision: 'REJECT',
                                              );
                                              if (!mounted) return;
                                              Navigator.pop(dialogContext);
                                              _success('Devis refusé.');
                                              await _showMyProfessionalRequests();
                                            } catch (error) {
                                              _info('Refus impossible : ' + error.toString());
                                            }
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Accepter',
                                          icon: const Icon(Icons.check_circle_outline),
                                          onPressed: () async {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (confirmContext) => AlertDialog(
                                                title: const Text('Accepter ce devis ?'),
                                                content: const Text('Le rendez-vous et le paiement restent à organiser avec le professionnel.'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('Retour')),
                                                  FilledButton(onPressed: () => Navigator.pop(confirmContext, true), child: const Text('Accepter')),
                                                ],
                                              ),
                                            );
                                            if (!mounted || confirmed != true) return;
                                            try {
                                              await repo.respondProfessionalServiceQuote(
                                                quoteId: quote['id'].toString(),
                                                decision: 'ACCEPT',
                                              );
                                              if (!mounted) return;
                                              Navigator.pop(dialogContext);
                                              _success('Devis accepté. Organisez maintenant la prestation avec le professionnel.');
                                              await _showMyProfessionalRequests();
                                            } catch (error) {
                                              _info('Acceptation impossible : ' + error.toString());
                                            }
                                          },
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        }),
                  const Divider(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes impossible : ' + error.toString());
    }
  }

  Future<void> _showProviderProfessionalRequests() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;
    try {
      final rows = await repo.providerProfessionalServiceRequests();
      if (!mounted) return;
      if (rows.isEmpty) {
        _info('Aucune demande reçue pour vos prestations.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Demandes professionnelles reçues'),
          content: SizedBox(
            width: 560,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final request = rows[index];
                final status = request['request_status']?.toString() ?? '-';
                final quoteStatus = request['quote_status']?.toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(request['profession']?.toString() ?? 'Prestation'),
                  subtitle: Text(
                    'Statut : ' + _professionalStatus(status) +
                    (request['scheduled_at'] == null ? '' : '\nDate souhaitée : ' + request['scheduled_at'].toString()) +
                    '\nBesoin : ' + (request['description']?.toString() ?? '-') +
                    (quoteStatus == null ? '' : '\nVotre devis : ' +
                      (request['quote_amount']?.toString() ?? '-') + ' ' +
                      (request['quote_currency']?.toString() ?? 'XOF') +
                      ' (' + _professionalStatus(quoteStatus) + ')'),
                  ),
                  isThreeLine: true,
                  trailing: status == 'REQUESTED'
                      ? IconButton(
                          tooltip: 'Proposer un devis',
                          icon: const Icon(Icons.request_quote_outlined),
                          onPressed: () async {
                            final draft = await _professionalQuoteDialog();
                            if (!mounted || draft == null) return;
                            try {
                              final quoteId = await repo.createProfessionalServiceQuote(
                                requestId: request['request_id'].toString(),
                                amount: draft['amount'] as num,
                                message: draft['message']?.toString(),
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Devis envoyé : ' + quoteId);
                              await _showProviderProfessionalRequests();
                            } catch (error) {
                              _info('Envoi du devis impossible : ' + error.toString());
                            }
                          },
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement des demandes reçues impossible : ' + error.toString());
    }
  }

  String _professionalStatus(String status) {
    switch (status) {
      case 'REQUESTED': return 'En attente';
      case 'QUOTED': return 'Devis envoyé';
      case 'PROPOSED': return 'Proposé';
      case 'ACCEPTED': return 'Accepté';
      case 'REJECTED': return 'Refusé';
      case 'EXPIRED': return 'Expiré';
      case 'CANCELLED': return 'Annulé';
      case 'IN_PROGRESS': return 'En cours';
      case 'COMPLETED': return 'Terminé';
      default: return status;
    }
  }

  Future<void> _showMyCreativeBookings() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;

    try {
      final bookings = await repo.myCreativeBookings();
      if (!mounted) return;
      if (bookings.isEmpty) {
        _info('Vous n’avez aucune demande créative pour le moment.');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mes demandes créatives'),
          content: SizedBox(
            width: 460,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: bookings.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final booking = bookings[index];
                final rawService = booking['creative_services'];
                final service = rawService is Map
                    ? Map<String, dynamic>.from(rawService)
                    : const <String, dynamic>{};
                final status = booking['status']?.toString() ?? '-';
                final scheduledAt = booking['scheduled_at']?.toString();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(service['name']?.toString() ?? 'Prestation créative'),
                  subtitle: Text(
                    'Statut : $status'
                    '${scheduledAt == null ? '' : '\nPrévu : $scheduledAt'}'
                    '${booking['agreed_amount'] == null ? '' : '\nMontant : ${booking['agreed_amount']} XOF'}',
                  ),
                  trailing: status == 'REQUESTED'
                      ? IconButton(
                          tooltip: 'Annuler la demande',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () async {
                            try {
                              await repo.cancelCreativeBooking(
                                booking['id'].toString(),
                              );
                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              _success('Demande créative annulée.');
                              await _showMyCreativeBookings();
                            } catch (error) {
                              _info('Annulation impossible : $error');
                            }
                          },
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Chargement de vos demandes impossible : $error');
    }
  }

  Future<void> _showProviderCreativeBookings() async {
    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null || !await _ensureAuth() || !mounted) return;

    try {
      final bookings = await repo.providerCreativeBookings();
      if (!mounted) return;
      if (bookings.isEmpty) {
        _info('Aucune demande reçue pour vos prestations créatives.');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Demandes reçues'),
          content: SizedBox(
            width: 520,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: bookings.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final booking = bookings[index];
                final status = booking['status']?.toString() ?? '-';
                final scheduledAt = booking['scheduled_at']?.toString();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    booking['service_name']?.toString() ?? 'Prestation créative',
                  ),
                  subtitle: Text(
                    'Statut : $status'
                    '${scheduledAt == null ? '' : '\nDate demandée : $scheduledAt'}'
                    '${booking['agreed_amount'] == null ? '' : '\nMontant convenu : ${booking['agreed_amount']} XOF'}',
                  ),
                  isThreeLine: true,
                  trailing: status == 'REQUESTED'
                      ? Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Refuser',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                final confirmed = await _confirmCreativeDecline();
                                if (!mounted || !confirmed) return;
                                try {
                                  await repo.respondCreativeBooking(
                                    bookingId: booking['booking_id'].toString(),
                                    decision: 'DECLINE',
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Demande refusée.');
                                  await _showProviderCreativeBookings();
                                } catch (error) {
                                  _info('Refus impossible : $error');
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Confirmer et fixer le montant',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () async {
                                final amount = await _creativeAmountDialog();
                                if (!mounted || amount == null) return;
                                try {
                                  await repo.respondCreativeBooking(
                                    bookingId: booking['booking_id'].toString(),
                                    decision: 'CONFIRM',
                                    agreedAmount: amount,
                                  );
                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  _success('Réservation confirmée.');
                                  await _showProviderCreativeBookings();
                                } catch (error) {
                                  _info('Confirmation impossible : $error');
                                }
                              },
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Accès aux demandes prestataire impossible : $error');
    }
  }

  Future<num?> _creativeAmountDialog() async {
    final controller = TextEditingController();
    final amount = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Montant convenu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Montant en XOF',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = num.tryParse(controller.text.trim());
              if (parsed != null && parsed >= 0) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return amount;
  }

  Future<bool> _confirmCreativeDecline() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refuser cette demande ?'),
        content: const Text('Le client verra que sa demande a été refusée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _trackParcel() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suivre un colis'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code de suivi',
            hintText: 'PKG-XXXXXXXXXXXX',
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
              if (value.isNotEmpty) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Suivre'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || code == null) return;

    final repo = ref.read(verticalRepositoryProvider);
    if (repo == null) return;

    try {
      final tracking = await repo.trackParcel(code);
      if (!mounted) return;
      final rawEvents = tracking['events'];
      final events = rawEvents is List
          ? rawEvents
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : const <Map<String, dynamic>>[];

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Colis ' + (tracking['tracking_code']?.toString() ?? code),
          ),
          content: SizedBox(
            width: 460,
            child: events.isEmpty
                ? Text(
                    'Statut actuel : ' +
                        (tracking['status']?.toString() ?? '-'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('Statut actuel'),
                        subtitle: Text(
                          tracking['status']?.toString() ?? '-',
                        ),
                      ),
                      const Divider(),
                      for (final event in events)
                        ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: Text(
                            event['status']?.toString() ?? '-',
                          ),
                          subtitle: Text(
                            event['created_at']?.toString() ?? '-',
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _info('Suivi impossible : ' + error.toString());
    }
  }

  Future<void> _createFreight(VerticalRepository repo) async {
    final pickup = await _addressDialog();
    if (!mounted || pickup == null) return;
    final destination = await _addressDialog();
    if (!mounted || destination == null) return;
    final weight = TextEditingController();
    final description = TextEditingController();

    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle demande de fret'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Poids en kg (facultatif)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description de la marchandise',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              <String>[weight.text.trim(), description.text.trim()],
            ),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    weight.dispose();
    description.dispose();
    if (!mounted || values == null) return;

    try {
      final id = await repo.createFreight(
        pickup: {'label': pickup},
        delivery: {'label': destination},
        weightKg: num.tryParse(values[0]),
        description: values[1].isEmpty ? null : values[1],
      );
      _success('Demande de fret créée : $id');
    } catch (error) {
      _info('Demande de fret impossible : $error');
    }
  }

  Future<void> _createParcel(VerticalRepository repo) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final pickup = TextEditingController();
    final delivery = TextEditingController();
    final weight = TextEditingController();

    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Envoyer un colis'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom du destinataire'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone du destinataire'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pickup,
                decoration: const InputDecoration(labelText: 'Lieu de dépôt / départ'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: delivery,
                decoration: const InputDecoration(labelText: 'Lieu de livraison'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Poids en kg (facultatif)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty ||
                  pickup.text.trim().isEmpty ||
                  delivery.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                dialogContext,
                <String>[
                  name.text.trim(),
                  phone.text.trim(),
                  pickup.text.trim(),
                  delivery.text.trim(),
                  weight.text.trim(),
                ],
              );
            },
            child: const Text('Créer le colis'),
          ),
        ],
      ),
    );

    name.dispose();
    phone.dispose();
    pickup.dispose();
    delivery.dispose();
    weight.dispose();

    if (!mounted || values == null) return;

    try {
      final id = await repo.createParcel(
        recipientName: values[0],
        recipientPhone: values[1],
        pickupAddress: {'label': values[2]},
        deliveryAddress: {'label': values[3]},
        weightKg: num.tryParse(values[4]),
      );
      _success('Colis créé : $id');
    } catch (error) {
      _info('Création du colis impossible : $error');
    }
  }

  Future<void> _requestRide(VerticalRepository repo) async {
    try {
      final position = await DeviceLocationService.current();
      if (!mounted) return;
      final destination = await _destinationDialog(
        LatLng(position.latitude, position.longitude),
      );
      if (!mounted || destination == null) return;

      final id = await repo.createRide(
        pickup: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
        },
        destination: {
          'latitude': destination.latitude,
          'longitude': destination.longitude,
          'label': destination.label,
        },
      );
      _success('Trajet demandé : $id');
    } catch (error) {
      _info(error.toString());
    }
  }

  Future<int?> _quantityDialog(String title) async {
    final controller = TextEditingController(text: '1');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantité',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null && parsed > 0 && parsed <= 20) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<String?> _addressDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adresse d’intervention'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Quartier, rue, repère...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<_Destination?> _destinationDialog(LatLng initialCenter) async {
    final lat = TextEditingController();
    final lng = TextEditingController();
    final label = TextEditingController();
    LatLng selected = initialCenter;

    final value = await showDialog<_Destination>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Destination'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text(
                    'Touchez la carte pour choisir la destination.',
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 260,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: selected,
                          initialZoom: 14,
                          minZoom: 5,
                          maxZoom: 19,
                          onTap: (_, point) {
                            setDialogState(() {
                              selected = point;
                              lat.text = point.latitude.toStringAsFixed(6);
                              lng.text = point.longitude.toStringAsFixed(6);
                            });
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'marketplace_multiservices_burkina',
                            maxZoom: 19,
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: selected,
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.location_pin,
                                  size: 44,
                                ),
                              ),
                              Marker(
                                point: initialCenter,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.my_location_outlined,
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                          SimpleAttributionWidget(
                            source: const Text(
                              'OpenStreetMap contributors',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Repère / destination',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null &&
                          parsed >= -90 &&
                          parsed <= 90) {
                        setDialogState(() {
                          selected = LatLng(parsed, selected.longitude);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null &&
                          parsed >= -180 &&
                          parsed <= 180) {
                        setDialogState(() {
                          selected = LatLng(selected.latitude, parsed);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sélection : ' +
                          selected.latitude.toStringAsFixed(6) +
                          ', ' +
                          selected.longitude.toStringAsFixed(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final parsedLat = double.tryParse(lat.text.trim());
                final parsedLng = double.tryParse(lng.text.trim());

                final finalLat = parsedLat ?? selected.latitude;
                final finalLng = parsedLng ?? selected.longitude;

                if (finalLat >= -90 &&
                    finalLat <= 90 &&
                    finalLng >= -180 &&
                    finalLng <= 180) {
                  Navigator.pop(
                    dialogContext,
                    _Destination(
                      latitude: finalLat,
                      longitude: finalLng,
                      label: label.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('Demander'),
            ),
          ],
        ),
      ),
    );

    lat.dispose();
    lng.dispose();
    label.dispose();
    return value;
  }

  Future<DateTime?> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<DateTimeRange?> _dateRangeDialog() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: DateTime.now().add(const Duration(days: 1)),
        end: DateTime.now().add(const Duration(days: 2)),
      ),
    );
    if (range == null || !mounted) return null;
    return DateTimeRange(
      start: DateTime(range.start.year, range.start.month, range.start.day, 9),
      end: DateTime(range.end.year, range.end.month, range.end.day, 18),
    );
  }

  Future<DateTimeRange?> _stayDialog() => _dateRangeDialog();

  Future<Map<String, dynamic>?> _unitDialog(
    List<Map<String, dynamic>> units,
  ) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choisir une chambre / unité'),
        children: units.map((unit) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, unit),
            child: ListTile(
              title: Text(unit['name']?.toString() ?? 'Unité'),
              subtitle: Text(
                (unit['price_per_night']?.toString() ?? '0') +
                    ' XOF / nuit • capacité ' +
                    (unit['capacity']?.toString() ?? '0'),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _success(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    setState(() => _future = _load());
  }

  void _info(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _hasAction(VerticalModule module) => const {
        VerticalModule.rentals,
        VerticalModule.realEstate,
        VerticalModule.professionals,
        VerticalModule.agriculture,
        VerticalModule.health,
        VerticalModule.accommodations,
        VerticalModule.events,
        VerticalModule.jobs,
        VerticalModule.beauty,
        VerticalModule.homeServices,
        VerticalModule.digital,
        VerticalModule.training,
        VerticalModule.creative,
        VerticalModule.freight,
        VerticalModule.parcels,
      }.contains(module);

  String _actionLabel(VerticalModule module) {
    switch (module) {
      case VerticalModule.rides:
        return 'Demander';
      case VerticalModule.agriculture:
      case VerticalModule.health:
        return 'Commander';
      case VerticalModule.professionals:
        return 'Demander un devis';
      case VerticalModule.realEstate:
        return 'Visiter / contacter';
      case VerticalModule.rentals:
      case VerticalModule.accommodations:
        return 'Réserver';
      case VerticalModule.events:
        return 'Billets';
      case VerticalModule.jobs:
        return 'Postuler';
      case VerticalModule.beauty:
        return 'Rendez-vous';
      case VerticalModule.homeServices:
        return 'Demander';
      case VerticalModule.digital:
        return 'Commander';
      case VerticalModule.training:
        return 'S’inscrire';
      case VerticalModule.creative:
        return 'Demander';
      case VerticalModule.freight:
        return 'Demander';
      case VerticalModule.parcels:
        return 'Envoyer';
    }
  }

  IconData _icon(int value) {
    const icons = <IconData>[
      Icons.directions_car_outlined,
      Icons.directions_car_filled_outlined,
      Icons.home_work_outlined,
      Icons.hotel_outlined,
      Icons.event_outlined,
      Icons.work_outline,
      Icons.engineering_outlined,
      Icons.agriculture_outlined,
      Icons.local_shipping_outlined,
      Icons.health_and_safety_outlined,
      Icons.content_cut_outlined,
      Icons.home_repair_service_outlined,
      Icons.devices_outlined,
      Icons.school_outlined,
      Icons.camera_alt_outlined,
      Icons.inventory_2_outlined,
    ];
    return icons[value.clamp(0, icons.length - 1).toInt()];
  }

  String _title(Map<String, dynamic> item) {
    switch (widget.module) {
      case VerticalModule.realEstate:
        return item['title']?.toString() ?? 'Bien immobilier';
      case VerticalModule.events:
        return item['title']?.toString() ?? 'Événement';
      case VerticalModule.jobs:
        return item['title']?.toString() ?? 'Offre d’emploi';
      case VerticalModule.training:
        return item['title']?.toString() ?? 'Formation';
      case VerticalModule.accommodations:
        return item['name']?.toString() ?? 'Hébergement';
      default:
        return item['name']?.toString() ??
            item['vehicle_type']?.toString() ??
            item['profession']?.toString() ??
            'Annonce';
    }
  }

  String _subtitle(Map<String, dynamic> item) {
    final price = item['price'] ??
        item['daily_price'] ??
        item['starting_price'] ??
        item['hourly_rate'] ??
        item['ticket_price'];

    final base = <String>[
      if (item['city'] != null) item['city'].toString(),
      if (item['location'] != null) item['location'].toString(),
      if (item['service_area'] != null) item['service_area'].toString(),
      if (item['vehicle_type'] != null) item['vehicle_type'].toString(),
      if (widget.module == VerticalModule.agriculture)
        if (item['unit'] != null && item['available_quantity'] is num)
          'Stock disponible : ' +
              (item['available_quantity'] as num).toString() +
              ' ' +
              item['unit'].toString(),
      if (widget.module == VerticalModule.health && item['available_quantity'] is num)
        'Stock disponible : ' + item['available_quantity'].toString(),
      if (widget.module == VerticalModule.health && item['requires_prescription'] == true)
        'Ordonnance requise',
      if (price != null) price.toString() + ' XOF',
    ];

    if (widget.module == VerticalModule.agriculture &&
        item['seller_name'] != null) {
      base.insert(0, item['seller_name'].toString());
    }
    if (widget.module == VerticalModule.health && item['provider_name'] != null) {
      base.insert(0, item['provider_name'].toString());
    }

    return base.isNotEmpty
        ? base.join(' • ')
        : item['description']?.toString() ?? 'Voir les détails';
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(config.title),
        actions: [
          if (widget.module == VerticalModule.parcels)
            IconButton(
              tooltip: 'Suivre un colis',
              onPressed: _trackParcel,
              icon: const Icon(Icons.qr_code_scanner_outlined),
            ),
          if (widget.module == VerticalModule.health &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes demandes de santé',
              onPressed: _showMyHealthOrders,
              icon: const Icon(Icons.medication_outlined),
            ),
          if (widget.module == VerticalModule.health &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Demandes reçues (pharmacie)',
              onPressed: _showPharmacyHealthOrders,
              icon: const Icon(Icons.inbox_outlined),
            ),
          if (widget.module == VerticalModule.health &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mon catalogue pharmacie',
              onPressed: _showMyHealthProducts,
              icon: const Icon(Icons.local_pharmacy_outlined),
            ),
          if (widget.module == VerticalModule.agriculture &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes commandes agricoles',
              onPressed: _showMyAgricultureOrderRequests,
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
          if (widget.module == VerticalModule.agriculture &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Commandes reçues (vendeur)',
              onPressed: _showSellerAgricultureOrderRequests,
              icon: const Icon(Icons.inbox_outlined),
            ),
          if (widget.module == VerticalModule.agriculture &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes annonces agricoles',
              onPressed: _showMyAgricultureListings,
              icon: const Icon(Icons.storefront_outlined),
            ),
          if (widget.module == VerticalModule.professionals &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes demandes professionnelles',
              onPressed: _showMyProfessionalRequests,
              icon: const Icon(Icons.request_quote_outlined),
            ),
          if (widget.module == VerticalModule.professionals &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Demandes reçues (professionnel)',
              onPressed: _showProviderProfessionalRequests,
              icon: const Icon(Icons.inbox_outlined),
            ),
          if (widget.module == VerticalModule.realEstate &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes demandes immobilières',
              onPressed: _showMyRealEstateVisitRequests,
              icon: const Icon(Icons.bookmark_outline),
            ),
          if (widget.module == VerticalModule.realEstate &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Demandes reçues (propriétaire)',
              onPressed: _showProviderRealEstateVisitRequests,
              icon: const Icon(Icons.inbox_outlined),
            ),
          if (widget.module == VerticalModule.creative &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Mes demandes',
              onPressed: _showMyCreativeBookings,
              icon: const Icon(Icons.bookmark_outline),
            ),
          if (widget.module == VerticalModule.creative &&
              client?.auth.currentUser != null)
            IconButton(
              tooltip: 'Demandes reçues (prestataire)',
              onPressed: _showProviderCreativeBookings,
              icon: const Icon(Icons.inbox_outlined),
            ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.module == VerticalModule.rides
          ? FloatingActionButton.extended(
              onPressed: () async {
                final repo = ref.read(verticalRepositoryProvider);
                if (repo != null && await _ensureAuth() && mounted) {
                  await _requestRide(repo);
                }
              },
              icon: const Icon(Icons.local_taxi_outlined),
              label: const Text('Nouveau trajet'),
            )
          : null,
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

          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            final message = _requiresAuth && client?.auth.currentUser == null
                ? 'Connectez-vous pour voir vos demandes.'
                : 'Aucune offre disponible actuellement.';
            return Center(child: Text(message));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final item = items[index];
              final action = _hasAction(widget.module);

              return Card(
                child: ExpansionTile(
                  leading: CircleAvatar(child: Icon(_icon(config.icon))),
                  title: Text(_title(item)),
                  subtitle: Text(_subtitle(item)),
                  trailing: action
                      ? FilledButton(
                          onPressed: () => _act(item),
                          child: Text(_actionLabel(widget.module)),
                        )
                      : null,
                  children: [
                    if (item['description'] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(item['description'].toString()),
                        ),
                      ),
                    if (item['address'] != null)
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(item['address'].toString()),
                      ),
                    if (item['status'] != null)
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Statut'),
                        subtitle: Text(item['status'].toString()),
                      ),
                    if (item['tracking_code'] != null)
                      ListTile(
                        leading: const Icon(Icons.qr_code_2_outlined),
                        title: const Text('Code de suivi'),
                        subtitle: Text(item['tracking_code'].toString()),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}
