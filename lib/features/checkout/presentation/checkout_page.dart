import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/location/burkina_location_directory.dart';
import '../../../core/errors/backend_error_message.dart';
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
  bool _loading = false;
  bool _quoteLoading = false;
  bool _quoteError = false;
  int _quoteRequestId = 0;

  late final String _idempotencyKey;

  @override
  void dispose() {
    _couponController.dispose();
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
  final _neighborhood = TextEditingController();
  final _city = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  late final Future<BurkinaLocationDirectory> _directoryFuture;
  String? _selectedRegion;
  String? _selectedProvince;
  String? _selectedCommune;
  int? _selectedArrondissement;
  String? _selectedSectorOrVillage;

  @override
  void initState() {
    super.initState();
    _directoryFuture = BurkinaLocationDirectory.load();
  }

  @override
  void dispose() {
    _label.dispose();
    _recipient.dispose();
    _phone.dispose();
    _address.dispose();
    _neighborhood.dispose();
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
        SnackBar(
          content: Text(
            safeBackendErrorMessage(
              error,
              fallback: 'Position indisponible. Vérifiez les autorisations de localisation et réessayez.',
            ),
          ),
        ),
      );
    }
  }

  Widget _administrativeFields(BurkinaLocationDirectory directory) {
    final provinces = directory.provincesFor(_selectedRegion);
    final communes = directory.communesFor(
      _selectedRegion,
      _selectedProvince,
    );
    final city = _city.text.trim().isNotEmpty
        ? _city.text.trim()
        : (_selectedCommune ?? '');
    final arrondissements = directory.arrondissementsFor(city);
    final areaOptions = <String>[
      ...directory.sectorsFor(city, _selectedArrondissement)
          .map((sector) => 'Secteur $sector'),
      ...directory.attachedVillagesFor(city, _selectedArrondissement),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Référentiel administratif officiel',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedRegion,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Région',
            hintText: 'Sélectionner la région',
          ),
          items: directory.regionNames
              .map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedRegion = value;
              _selectedProvince = null;
              _selectedCommune = null;
              _city.clear();
              _selectedArrondissement = null;
              _selectedSectorOrVillage = null;
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: provinces.contains(_selectedProvince)
              ? _selectedProvince
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Province',
            hintText: 'Sélectionner la province',
          ),
          items: provinces
              .map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                ),
              )
              .toList(),
          onChanged: provinces.isEmpty
              ? null
              : (value) {
                  setState(() {
                    _selectedProvince = value;
                    _selectedCommune = null;
                    _city.clear();
                    _selectedArrondissement = null;
                    _selectedSectorOrVillage = null;
                  });
                },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: communes.contains(_selectedCommune)
              ? _selectedCommune
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Commune (sélection facultative)',
            hintText: 'Sélectionner la commune',
          ),
          items: communes
              .map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                ),
              )
              .toList(),
          onChanged: communes.isEmpty
              ? null
              : (value) {
                  setState(() {
                    _selectedCommune = value;
                    _city.text = value ?? '';
                    _selectedArrondissement = null;
                    _selectedSectorOrVillage = null;
                  });
                },
        ),
        const SizedBox(height: 8),
        if (arrondissements.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: arrondissements.contains(_selectedArrondissement)
                ? _selectedArrondissement
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Arrondissement (facultatif)',
            ),
            items: arrondissements
                .map(
                  (number) => DropdownMenuItem<int>(
                    value: number,
                    child: Text('Arrondissement n°$number'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedArrondissement = value;
                _selectedSectorOrVillage = null;
              });
            },
          ),
        ],
        if (directory.hasPublishedUrbanSectors(city) &&
            _selectedArrondissement == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Choisissez un arrondissement pour afficher ses secteurs officiels.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        if (areaOptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: areaOptions.contains(_selectedSectorOrVillage)
                ? _selectedSectorOrVillage
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Secteur officiel / village rattaché (facultatif)',
            ),
            items: areaOptions
                .map(
                  (name) => DropdownMenuItem<String>(
                    value: name,
                    child: Text(name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedSectorOrVillage = value);
            },
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _neighborhood,
          decoration: const InputDecoration(
            labelText: 'Quartier (nom usuel)',
            hintText: 'Saisir le quartier exact',
            helperText: 'Champ libre : les noms de quartiers ne sont pas normalisés nationalement.',
          ),
        ),
      ],
    );
  }

  String _buildAddressLine() {
    final parts = <String>[];
    if (_selectedRegion != null) parts.add('Région : $_selectedRegion');
    if (_selectedProvince != null) parts.add('Province : $_selectedProvince');
    if (_selectedArrondissement != null) {
      parts.add('Arrondissement n°$_selectedArrondissement');
    }
    if (_selectedSectorOrVillage != null) {
      parts.add(_selectedSectorOrVillage!);
    }
    if (_neighborhood.text.trim().isNotEmpty) {
      parts.add('Quartier : ${_neighborhood.text.trim()}');
    }
    if (_address.text.trim().isNotEmpty) {
      parts.add('Adresse / repère : ${_address.text.trim()}');
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle adresse'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 12),
            FutureBuilder<BurkinaLocationDirectory>(
              future: _directoryFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return _administrativeFields(snapshot.data!);
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Le répertoire hors ligne est momentanément indisponible. Vous pouvez toujours saisir votre ville et votre quartier manuellement.',
                    ),
                  );
                }
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _city,
              decoration: const InputDecoration(
                labelText: 'Ville / commune',
                hintText: 'Saisir si la localité est absente du répertoire',
                helperText: 'La saisie libre reste autorisée partout au Burkina Faso.',
              ),
              onChanged: (_) {
                setState(() {
                  _selectedArrondissement = null;
                  _selectedSectorOrVillage = null;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Rue, porte, bâtiment ou point de repère',
              ),
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

            final city = _city.text.trim().isNotEmpty
                ? _city.text.trim()
                : (_selectedCommune ?? '');
            Navigator.pop(
              context,
              <String, dynamic>{
                'label': _label.text.trim(),
                'recipient_name': recipient,
                'phone': _phone.text.trim(),
                'address_line': _buildAddressLine(),
                'city': city,
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
