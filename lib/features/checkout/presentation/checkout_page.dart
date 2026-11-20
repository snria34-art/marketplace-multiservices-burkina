import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/providers/repository_providers.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({
    super.key,
    required this.cartId,
  });

  final String cartId;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  late Future<List<Map<String, dynamic>>> _addressesFuture;
  String? _selectedAddressId;
  Map<String, dynamic>? _selectedAddress;
  Map<String, dynamic>? _quote;
  String _paymentProvider = 'CINETPAY';
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _deliveryInstructionsController = TextEditingController();
  String _deliveryPlaceType = 'HOME';
  DateTime _deliveryDate = DateTime.now();
  int _deliveryHour = 12;
  bool _loading = false;
  bool _quoteLoading = false;
  bool _quoteError = false;
  int _quoteRequestId = 0;

  late final String _idempotencyKey;

  @override
  void dispose() {
    _couponController.dispose();
    _deliveryInstructionsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'checkout-' +
        DateTime.now().toUtc().microsecondsSinceEpoch.toString();

    _addressesFuture = _loadAddresses();
  }

  Future<List<Map<String, dynamic>>> _loadAddresses() async {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return const [];

    final rows = await repo.addresses();

    if (rows.isNotEmpty && _selectedAddressId == null) {
      final first = rows.first;
      final addressId = first['id']?.toString();
      final requestId = ++_quoteRequestId;
      _selectedAddressId = addressId;
      _selectedAddress = first;
      _quoteLoading = true;
      _quoteError = false;

      try {
        final quote = await _calculateQuote(first);
        if (mounted &&
            requestId == _quoteRequestId &&
            _selectedAddressId == addressId) {
          _quote = quote;
        }
      } catch (_) {
        if (mounted &&
            requestId == _quoteRequestId &&
            _selectedAddressId == addressId) {
          _quoteError = true;
        }
      } finally {
        if (mounted && requestId == _quoteRequestId) {
          _quoteLoading = false;
        }
      }
    }

    return rows;
  }

  Future<Map<String, dynamic>> _calculateQuote(
    Map<String, dynamic> address,
  ) {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) {
      return Future.error(StateError('Service indisponible.'));
    }

    return repo.calculateDeliveryFee(
      cartId: widget.cartId,
      address: address,
    );
  }

  Future<void> _selectAddress(Map<String, dynamic> address) async {
    final requestId = ++_quoteRequestId;
    final addressId = address['id']?.toString();

    setState(() {
      _selectedAddressId = addressId;
      _selectedAddress = address;
      _quote = null;
      _quoteLoading = true;
      _quoteError = false;
    });

    try {
      final quote = await _calculateQuote(address);
      if (!mounted ||
          requestId != _quoteRequestId ||
          _selectedAddressId != addressId) {
        return;
      }
      setState(() => _quote = quote);
    } catch (error) {
      if (!mounted ||
          requestId != _quoteRequestId ||
          _selectedAddressId != addressId) {
        return;
      }

      setState(() => _quoteError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de calculer la livraison : ' + error.toString(),
          ),
        ),
      );
    } finally {
      if (mounted && requestId == _quoteRequestId) {
        setState(() => _quoteLoading = false);
      }
    }
  }

  Future<void> _retryQuote() async {
    final address = _selectedAddress;
    if (address == null || _quoteLoading || _loading) return;
    await _selectAddress(address);
  }

  Future<void> _addAddress() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );

    if (!mounted || result == null) return;

    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return;

    try {
      final createdAddress = await repo.createAddress(
        label: result['label']?.toString(),
        recipientName: result['recipient_name'].toString(),
        phone: result['phone']?.toString(),
        addressLine: result['address_line']?.toString(),
        city: result['city']?.toString(),
        latitude: double.tryParse(result['latitude']?.toString() ?? ''),
        longitude: double.tryParse(result['longitude']?.toString() ?? ''),
      );

      final createdAddressId = createdAddress['id']?.toString();
      if (createdAddressId == null || createdAddressId.trim().isEmpty) {
        throw StateError(
          'L’adresse a été enregistrée sans identifiant exploitable.',
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedAddressId = createdAddressId;
        _selectedAddress = createdAddress;
        _quote = null;
        _quoteError = false;
        _addressesFuture = _loadAddresses();
      });

      await _selectAddress(createdAddress);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Création de l’adresse impossible : ' + error.toString(),
          ),
        ),
      );
    }
  }

  DateTime get _scheduledDeliveryAt => DateTime.utc(
        _deliveryDate.year,
        _deliveryDate.month,
        _deliveryDate.day,
        _deliveryHour,
      );

  String _formatDeliveryDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  Future<void> _chooseDeliveryDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate.isBefore(DateTime(today.year, today.month, today.day))
          ? DateTime(today.year, today.month, today.day)
          : _deliveryDate,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year, today.month, today.day).add(
        const Duration(days: 30),
      ),
      helpText: 'Choisir le jour de livraison',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _deliveryDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _checkout() async {
    final repo = ref.read(checkoutRepositoryProvider);
    final addressId = _selectedAddressId;

    if (repo == null || addressId == null || _quote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sélectionnez une adresse et calculez la livraison.',
          ),
        ),
      );
      return;
    }

    if (_deliveryPlaceType == 'OFFICE' &&
        !_scheduledDeliveryAt.isAfter(DateTime.now().toUtc())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez une heure de bureau encore à venir.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final fee =
          num.tryParse(_quote!['customer_fee']?.toString() ?? '') ?? 0;

      // Do not create an order or reserve inventory until the chosen provider
      // has all server-side credentials needed for payment and webhooks.
      await repo.ensurePaymentProviderConfigured(
        provider: _paymentProvider,
      );
      if (!mounted) return;

      final orderId = await repo.checkout(
        cartId: widget.cartId,
        addressId: addressId,
        deliveryFee: fee,
        couponCode: _couponController.text.trim().isEmpty
            ? null
            : _couponController.text.trim(),
        idempotencyKey: _idempotencyKey,
        deliveryPlaceType: _deliveryPlaceType,
        scheduledDeliveryAt:
            _deliveryPlaceType == 'OFFICE' ? _scheduledDeliveryAt : null,
        deliveryInstructions: _deliveryInstructionsController.text,
      );
      if (!mounted) return;

      final paymentSession = await repo.createPaymentSession(
        orderId: orderId,
        provider: _paymentProvider,
      );
      if (!mounted) return;

      final checkoutUrl = paymentSession['checkout_url']?.toString();
      if (checkoutUrl == null || checkoutUrl.trim().isEmpty) {
        throw StateError('Le guichet de paiement n’a pas été fourni.');
      }

      final paymentUri = Uri.tryParse(checkoutUrl.trim());
      if (paymentUri == null ||
          paymentUri.scheme.toLowerCase() != 'https' ||
          paymentUri.host.isEmpty ||
          paymentUri.userInfo.isNotEmpty) {
        throw StateError(
          'Adresse de paiement invalide : une URL HTTPS sécurisée est requise.',
        );
      }

      final opened = await launchUrl(
        paymentUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Impossible d’ouvrir le guichet de paiement.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Guichet de paiement ouvert. Revenez dans l’application après le paiement.',
          ),
        ),
      );
      context.go('/orders/' + orderId);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout impossible : ' + error.toString())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finaliser la commande')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _addressesFuture,
        builder: (context, snapshot) {
          // Read the latest selection and quote each time FutureBuilder rebuilds.
          final address = _selectedAddress;
          final fee = _quote?['customer_fee']?.toString();
          final distance = _quote?['distance_km']?.toString();
          final stops = _quote?['stop_count']?.toString();

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Erreur des adresses : ' + snapshot.error.toString(),
              ),
            );
          }

          final addresses =
              snapshot.data ?? const <Map<String, dynamic>>[];

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Adresse de livraison',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton.icon(
                    onPressed: _addAddress,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              if (addresses.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aucune adresse enregistrée. Ajoutez une adresse pour continuer.',
                    ),
                  ),
                )
              else
                ...addresses.map(
                  (item) => Card(
                    child: RadioListTile<String>(
                      value: item['id'].toString(),
                      groupValue: _selectedAddressId,
                      onChanged: (_) => _selectAddress(item),
                      title: Text(
                        item['label']?.toString() ??
                            item['recipient_name']?.toString() ??
                            'Adresse',
                      ),
                      subtitle: Text(
                        (item['recipient_name']?.toString() ?? '') +
                            '\n' +
                            (item['address_line']?.toString() ?? '') +
                            (item['city']?.toString().isEmpty == true
                                ? ''
                                : ' — ' + (item['city']?.toString() ?? '')),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Livraison',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(
                    fee == null ? 'Devis non calculé' : fee + ' XOF',
                  ),
                  subtitle: Text(
                    distance == null
                        ? 'Sélectionnez une adresse'
                        : 'Distance : ' +
                            distance +
                            ' km • ' +
                            (stops ?? '1') +
                            ' point(s)',
                  ),
                  trailing: _quoteLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _quote == null
                          ? const Icon(Icons.calculate_outlined)
                          : const Icon(Icons.check_circle_outline),
                ),
              ),
              if (address != null && _quote == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _quoteLoading || _loading ? null : _retryQuote,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _quoteLoading
                          ? 'Calcul du devis…'
                          : _quoteError
                              ? 'Réessayer le calcul de livraison'
                              : 'Calculer la livraison',
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Lieu de réception',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'HOME',
                    icon: Icon(Icons.home_outlined),
                    label: Text('Domicile'),
                  ),
                  ButtonSegment(
                    value: 'OFFICE',
                    icon: Icon(Icons.business_outlined),
                    label: Text('Bureau'),
                  ),
                ],
                selected: {_deliveryPlaceType},
                onSelectionChanged: _loading
                    ? null
                    : (selection) {
                        setState(() {
                          _deliveryPlaceType = selection.first;
                          if (_deliveryPlaceType == 'OFFICE') {
                            _deliveryDate = DateTime.now();
                          }
                        });
                      },
              ),
              if (_deliveryPlaceType == 'OFFICE') ...[
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Heure exacte souhaitée',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : _chooseDeliveryDate,
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(_formatDeliveryDate(_deliveryDate)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: _deliveryHour,
                                decoration: const InputDecoration(
                                  labelText: 'À pile',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (var hour = 6; hour <= 22; hour++)
                                    DropdownMenuItem(
                                      value: hour,
                                      child: Text(
                                        '${hour.toString().padLeft(2, '0')}:00',
                                      ),
                                    ),
                                ],
                                onChanged: _loading
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() => _deliveryHour = value);
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Livraison demandée le ${_formatDeliveryDate(_deliveryDate)} à ${_deliveryHour.toString().padLeft(2, '0')}:00 pile.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _deliveryInstructionsController,
                          enabled: !_loading,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: 'Nom du bureau, étage ou repère',
                            hintText: 'Ex. Bâtiment B, 2e étage',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Code promotionnel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _couponController,
                enabled: !_loading,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code coupon (optionnel)',
                  hintText: 'Ex. PROMO10',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Paiement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _paymentProvider,
                decoration: const InputDecoration(
                  labelText: 'Opérateur',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'CINETPAY',
                    child: Text('Orange Money / Moov Money'),
                  ),
                  DropdownMenuItem(
                    value: 'WAVE',
                    child: Text('Wave'),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _paymentProvider = value);
                        }
                      },
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed:
                    _loading || address == null || _quote == null
                        ? null
                        : _checkout,
                icon: const Icon(Icons.lock_outline),
                label: Text(
                  _loading
                      ? 'Traitement…'
                      : 'Créer la commande et le paiement',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _label = TextEditingController();
  final _recipient = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _recipient.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      final position = await DeviceLocationService.current();
      if (!mounted) return;
      setState(() {
        _latitude.text = position.latitude.toStringAsFixed(6);
        _longitude.text = position.longitude.toStringAsFixed(6);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Position indisponible : ' + error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle adresse'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
            TextField(
              controller: _recipient,
              decoration: const InputDecoration(
                labelText: 'Nom du destinataire',
              ),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Ville'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_outlined),
                label: const Text('Utiliser ma position actuelle'),
              ),
            ),
            TextField(
              controller: _latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude (optionnel)',
              ),
            ),
            TextField(
              controller: _longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude (optionnel)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final recipient = _recipient.text.trim();
            if (recipient.isEmpty) return;

            Navigator.pop(
              context,
              <String, dynamic>{
                'label': _label.text.trim(),
                'recipient_name': recipient,
                'phone': _phone.text.trim(),
                'address_line': _address.text.trim(),
                'city': _city.text.trim(),
                'latitude': _latitude.text.trim(),
                'longitude': _longitude.text.trim(),
              },
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
