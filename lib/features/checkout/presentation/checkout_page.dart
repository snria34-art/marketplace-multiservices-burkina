import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/utils/xof_formatter.dart';

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
  late Future<Map<String, dynamic>?> _restaurantContextFuture;
  Map<String, dynamic>? _restaurantContext;
  bool _fulfillmentInitialized = false;
  String _fulfillmentMethod = 'DELIVERY';
  String? _selectedAddressId;
  Map<String, dynamic>? _selectedAddress;
  Map<String, dynamic>? _quote;
  String _paymentProvider = 'CINETPAY';
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _restaurantInstructionsController =
      TextEditingController();
  bool _loading = false;
  bool _quoteLoading = false;
  bool _quoteError = false;
  int _quoteRequestId = 0;

  late final String _idempotencyKey;

  @override
  void dispose() {
    _couponController.dispose();
    _restaurantInstructionsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'checkout-${DateTime.now().toUtc().microsecondsSinceEpoch}';

    final repo = ref.read(checkoutRepositoryProvider);
    _restaurantContextFuture = repo == null
        ? Future<Map<String, dynamic>?>.value(null)
        : repo.restaurantCartContext(cartId: widget.cartId);
    _addressesFuture = _loadAddresses();
  }

  Future<List<Map<String, dynamic>>> _loadAddresses() async {
    final repo = ref.read(checkoutRepositoryProvider);
    if (repo == null) return const [];

    _restaurantContext ??= await _restaurantContextFuture;
    if (!_fulfillmentInitialized && _restaurantContext != null) {
      final canDeliver = _restaurantContext!['delivery_available'] == true;
      final canPickup = _restaurantContext!['pickup_available'] == true;
      final storedMethod =
          _restaurantContext!['fulfillment_method']?.toString().toUpperCase();
      _fulfillmentMethod = storedMethod == 'PICKUP' && canPickup
          ? 'PICKUP'
          : canDeliver
              ? 'DELIVERY'
              : canPickup
                  ? 'PICKUP'
                  : 'DELIVERY';
      _restaurantInstructionsController.text =
          _restaurantContext!['customer_instructions']?.toString() ?? '';
      _fulfillmentInitialized = true;
    }

    if (_restaurantContext != null && _fulfillmentMethod == 'PICKUP') {
      return const [];
    }

    final rows = await repo.addresses();

    if (rows.isNotEmpty && (_selectedAddressId == null || _quote == null)) {
      final first = rows.firstWhere(
        (item) => item['id']?.toString() == _selectedAddressId,
        orElse: () => rows.first,
      );
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
            safeBackendErrorMessage(error, fallback: 'Calcul de la livraison impossible. Réessayez.'),
          ),
        ),
      );
    } finally {
      if (mounted && requestId == _quoteRequestId) {
        setState(() => _quoteLoading = false);
      }
    }
  }

  Future<void> _changeFulfillmentMethod(String method) async {
    if (_loading || method == _fulfillmentMethod) return;
    ++_quoteRequestId;
    setState(() {
      _fulfillmentMethod = method;
      _quote = null;
      _quoteLoading = false;
      _quoteError = false;
      _addressesFuture = method == 'PICKUP'
          ? Future.value(const <Map<String, dynamic>>[])
          : _loadAddresses();
    });
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
            safeBackendErrorMessage(error, fallback: 'Création de l’adresse impossible. Réessayez.'),
          ),
        ),
      );
    }
  }

  Future<void> _checkout() async {
    final repo = ref.read(checkoutRepositoryProvider);
    final isPickup =
        _restaurantContext != null && _fulfillmentMethod == 'PICKUP';
    final addressId = _selectedAddressId;
    final canPickup = _restaurantContext?['pickup_available'] == true;

    if (repo == null ||
        (isPickup && !canPickup) ||
        (!isPickup && (addressId == null || _quote == null))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPickup
                ? 'Le retrait au restaurant n’est pas disponible.'
                : 'Sélectionnez une adresse et calculez la livraison.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      if (_restaurantContext != null) {
        await repo.setRestaurantCartFulfillment(
          cartId: widget.cartId,
          method: _fulfillmentMethod,
          customerInstructions:
              _restaurantInstructionsController.text.trim(),
        );
      }

      final fee = isPickup
          ? 0
          : num.tryParse(_quote!['customer_fee']?.toString() ?? '') ?? 0;

      // Do not create an order or reserve inventory until the configured
      // payment service has passed its server-side availability check.
      await repo.ensurePaymentProviderConfigured(
        provider: _paymentProvider,
      );
      if (!mounted) return;

      final orderId = await repo.checkout(
        cartId: widget.cartId,
        addressId: isPickup ? null : addressId,
        deliveryFee: fee,
        fulfillmentMethod: isPickup ? 'PICKUP' : 'DELIVERY',
        couponCode: _couponController.text.trim().isEmpty
            ? null
            : _couponController.text.trim(),
        idempotencyKey: _idempotencyKey,
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
      context.go('/orders/$orderId');
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeBackendErrorMessage(error, fallback: 'Validation de la commande impossible. Vérifiez le panier et réessayez.'))),
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
                'Impossible de charger les adresses. Réessayez.',
              ),
            );
          }

          final addresses =
              snapshot.data ?? const <Map<String, dynamic>>[];
          final restaurant = _restaurantContext;
          final canDeliver = restaurant?['delivery_available'] == true;
          final canPickup = restaurant?['pickup_available'] == true;
          final isPickup = restaurant != null && _fulfillmentMethod == 'PICKUP';
          final canSubmit = restaurant == null
              ? address != null && _quote != null
              : isPickup
                  ? canPickup
                  : canDeliver && address != null && _quote != null;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (restaurant != null) ...[
                Text(
                  'Comment recevoir votre commande ?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (canDeliver || canPickup)
                  SegmentedButton<String>(
                    segments: [
                      if (canDeliver)
                        const ButtonSegment<String>(
                          value: 'DELIVERY',
                          icon: Icon(Icons.delivery_dining_outlined),
                          label: Text('Livraison'),
                        ),
                      if (canPickup)
                        const ButtonSegment<String>(
                          value: 'PICKUP',
                          icon: Icon(Icons.storefront_outlined),
                          label: Text('Retrait'),
                        ),
                    ],
                    selected: {_fulfillmentMethod},
                    onSelectionChanged: _loading
                        ? null
                        : (selection) {
                            if (selection.isNotEmpty) {
                              _changeFulfillmentMethod(selection.first);
                            }
                          },
                  )
                else
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Aucun mode de réception disponible'),
                      subtitle: Text(
                        'Ce restaurant ne propose actuellement ni livraison ni retrait.',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (isPickup) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(
                      restaurant['restaurant_name']?.toString() ?? 'Retrait au restaurant',
                    ),
                    subtitle: Text([
                      if ((restaurant['pickup_address']?.toString() ?? '').isNotEmpty)
                        restaurant['pickup_address'].toString(),
                      if ((restaurant['restaurant_phone']?.toString() ?? '').isNotEmpty)
                        'Téléphone : ${restaurant['restaurant_phone']}',
                      if (restaurant['preparation_time_min'] != null)
                        'Préparation estimée : ${restaurant['preparation_time_min']} min',
                    ].join('\n')),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!isPickup) ...[
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
                  RadioGroup<String>(
                    groupValue: _selectedAddressId,
                    onChanged: (value) {
                      if (value == null) return;
                      for (final item in addresses) {
                        if (item['id'].toString() == value) {
                          _selectAddress(item);
                          break;
                        }
                      }
                    },
                    child: Column(
                      children: [
                        ...addresses.map(
                          (item) => Card(
                            child: RadioListTile<String>(
                              value: item['id'].toString(),
                              title: Text(
                                item['label']?.toString() ??
                                    item['recipient_name']?.toString() ??
                                    'Adresse',
                              ),
                              subtitle: Text(
                                '${item['recipient_name']?.toString() ?? ''}\n${item['address_line']?.toString() ?? ''}${item['city']?.toString().isEmpty == true
                                        ? ''
                                        : ' — ${item['city']?.toString() ?? ''}'}',
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      fee == null
                          ? 'Devis non calculé'
                          : formatXof(num.tryParse(fee) ?? 0),
                    ),
                    subtitle: Text(
                      distance == null
                          ? 'Sélectionnez une adresse'
                          : 'Distance : $distance km • ${stops ?? '1'} point(s)',
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
              ],
              if (restaurant != null) ...[
                Text(
                  'Instructions pour le restaurant (facultatif)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _restaurantInstructionsController,
                  enabled: !_loading,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Précisions pour préparer ou remettre votre commande',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
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
                onPressed: _loading || !canSubmit ? null : _checkout,
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
        SnackBar(content: Text(safeBackendErrorMessage(error, fallback: 'Position indisponible. Vérifiez les autorisations de localisation et réessayez.'))),
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
