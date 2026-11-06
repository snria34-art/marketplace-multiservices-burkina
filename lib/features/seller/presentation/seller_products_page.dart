import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/seller_products_repository.dart';

final sellerProductsRepositoryProvider =
    Provider<SellerProductsRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SellerProductsRepository(client);
});

class SellerProductsPage extends ConsumerStatefulWidget {
  const SellerProductsPage({super.key});

  @override
  ConsumerState<SellerProductsPage> createState() =>
      _SellerProductsPageState();
}

class _SellerProductsPageState
    extends ConsumerState<SellerProductsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  late Future<List<Map<String, dynamic>>> _shopsFuture;

  @override
  void initState() {
    super.initState();
    _future = _loadProducts();
    _shopsFuture = _loadShops();
  }

  Future<List<Map<String, dynamic>>> _loadProducts() {
    return ref.read(sellerProductsRepositoryProvider)?.products() ??
        Future.value(const []);
  }

  Future<List<Map<String, dynamic>>> _loadShops() {
    return ref.read(sellerProductsRepositoryProvider)?.shops() ??
        Future.value(const []);
  }

  Future<void> _create() async {
    final repo = ref.read(sellerProductsRepositoryProvider);
    if (repo == null) return;

    late final List<Map<String, dynamic>> shops;
    late final List<Map<String, dynamic>> categories;
    try {
      shops = await _shopsFuture;
      categories = await repo.categories();
    } catch (_) {
      _show('Impossible de charger les boutiques et catégories. Réessayez.');
      return;
    }

    if (!mounted) return;

    if (shops.isEmpty) {
      _show('Aucune boutique disponible pour ce compte.');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewProductDialog(
        shops: shops,
        categories: categories,
      ),
    );

    if (!mounted || result == null) return;

    String? createdProductId;
    try {
      final id = await repo.createProduct(
        shopId: result['shop_id'].toString(),
        name: result['name'].toString(),
        price: num.tryParse(result['price'].toString()) ?? 0,
        categoryId: result['category_id']?.toString(),
        description: result['description']?.toString(),
        initialStock:
            int.tryParse(result['initial_stock'].toString()) ?? 0,
        isExpirable: result['is_expirable'] == true,
        expiryDate: result['expiry_date'] as DateTime?,
      );
      createdProductId = id;
      if (id.trim().isEmpty || id.toLowerCase() == 'null') {
        throw StateError('Identifiant du produit invalide.');
      }

      if (!mounted) return;

      var submissionMessage = 'Produit créé en brouillon : ajoutez au moins une photo.';
      final productPhotos = await ImagePicker().pickMultiImage(
        limit: 5,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (!mounted) return;
      if (productPhotos.isNotEmpty) {
        for (final photo in productPhotos) {
          await repo.uploadProductImage(
            productId: id,
            file: photo,
            imageRole: 'PRODUCT',
          );
        }
        if (!mounted) return;
        final addPackaging = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Photo de l’emballage'),
            content: const Text('Ajoutez une photo de la boîte, du sachet ou de l’étiquette si le produit en possède un.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Pas maintenant'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Ajouter'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (addPackaging == true) {
          final packaging = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 75,
            maxWidth: 1600,
          );
          if (!mounted) return;
          if (packaging != null) {
            await repo.uploadProductImage(
              productId: id,
              file: packaging,
              imageRole: 'PACKAGING',
            );
          }
        }
        await repo.submitForReview(id);
        submissionMessage = 'Photos enregistrées. Annonce envoyée en attente de validation.';
        try {
          await repo.analyzeProduct(id);
          submissionMessage += ' Analyse IA terminée.';
        } catch (_) {
          submissionMessage += ' Analyse IA non disponible pour le moment; l’annonce reste en attente.';
        }
      }

      if (!mounted) return;
      setState(() => _future = _loadProducts());
      _show(submissionMessage);
    } catch (error) {
      final message = createdProductId == null
          ? 'Création impossible. Vérifiez les informations et réessayez.'
          : 'Produit créé en brouillon, mais les photos ou la validation ont échoué. Ne recréez pas ce produit : réessayez d’ajouter les photos depuis la liste.';
      _show(message);
    }
  }

  Future<void> _editStock(Map<String, dynamic> product) async {
    final repo = ref.read(sellerProductsRepositoryProvider);
    if (repo == null) return;

    try {
      final variants = await repo.variantInventory(product['id'].toString());
      if (!mounted) return;
      if (variants.isNotEmpty) {
        await _showVariantInventoryDialog(variants);
        return;
      }
    } catch (_) {
      // Do not fall back to parent stock when the variant read failed:
      // the app cannot safely determine which stock model this product uses.
      _show('Impossible de charger les stocks par variante. Réessayez ; aucun stock n’a été modifié.');
      return;
    }

    final rawInventory = product['inventory'];
    final inventory = rawInventory is Map
        ? Map<String, dynamic>.from(rawInventory)
        : const <String, dynamic>{};

    final controller = TextEditingController(
      text: inventory['quantity']?.toString() ?? '0',
    );

    final value = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le stock'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantité totale',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final quantity = int.tryParse(controller.text.trim());
              if (quantity != null && quantity >= 0) {
                Navigator.pop(context, quantity);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted || value == null) return;

    try {
      await repo.setStock(
        productId: product['id'].toString(),
        quantity: value,
      );

      if (!mounted) return;
      setState(() => _future = _loadProducts());
    } catch (error) {
      final rawError = error.toString();
      final message = rawError.contains('use_variant_stock_editor')
          ? 'Ce produit utilise un stock par variante. Rechargez les variantes ; le stock parent n’a pas été modifié.'
          : rawError.contains('stock_below_reserved')
              ? 'Le stock ne peut pas être inférieur à la quantité déjà réservée.'
              : 'Stock non modifié. Vérifiez la quantité et réessayez.';
      _show(message);
    }
  }

  Future<void> _showVariantInventoryDialog(
    List<Map<String, dynamic>> variants,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stocks par variante'),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: variants.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, index) {
              final variant = variants[index];
              final quantity = int.tryParse(
                    variant['quantity']?.toString() ?? '',
                  ) ??
                  0;
              final reserved = int.tryParse(
                    variant['reserved_quantity']?.toString() ?? '',
                  ) ??
                  0;
              final available = quantity - reserved;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(variant['name']?.toString() ?? 'Variante'),
                subtitle: Text(
                  'Total : $quantity • Réservé : $reserved • Disponible : $available',
                ),
                trailing: IconButton(
                  tooltip: 'Modifier ce stock',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _setVariantStock(variant),
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
        ],
      ),
    );
  }

  Future<void> _setVariantStock(Map<String, dynamic> variant) async {
    final controller = TextEditingController(
      text: variant['quantity']?.toString() ?? '0',
    );
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Stock : ${variant['name']?.toString() ?? 'variante'}',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantité totale',
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
              if (parsed != null && parsed >= 0 && parsed <= 1000000) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || quantity == null) return;
    final repo = ref.read(sellerProductsRepositoryProvider);
    if (repo == null) return;

    try {
      await repo.setVariantStock(
        variantId: variant['variant_id'].toString(),
        quantity: quantity,
      );
      if (!mounted) return;
      _show('Stock de la variante mis à jour.');
      // Close the variant list so it is reopened with fresh server values.
      Navigator.of(context).pop();
      setState(() => _future = _loadProducts());
    } catch (error) {
      final message = error.toString().contains('stock_below_reserved')
          ? 'Le stock ne peut pas être inférieur à la quantité réservée.'
          : error.toString().contains('variant_not_owned') ||
                  error.toString().contains('product_not_owned')
              ? 'Vous ne pouvez pas modifier le stock de cette variante.'
              : 'Stock non modifié. Vérifiez la quantité et réessayez.';
      _show(message);
    }
  }

  Future<void> _addPhotosForProduct(String productId) async {
    final repo = ref.read(sellerProductsRepositoryProvider);
    if (repo == null) return;
    try {
      final photos = await ImagePicker().pickMultiImage(
        limit: 5,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (!mounted || photos.isEmpty) return;
      for (final photo in photos) {
        await repo.uploadProductImage(
          productId: productId,
          file: photo,
          imageRole: 'PRODUCT',
        );
      }
      if (!mounted) return;
      final addPackaging = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Photo de l’emballage'),
          content: const Text('Ajoutez aussi une photo de la boîte, du sachet ou de l’étiquette si elle existe.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Pas maintenant'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (addPackaging == true) {
        final packaging = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 75,
          maxWidth: 1600,
        );
        if (!mounted) return;
        if (packaging != null) {
          await repo.uploadProductImage(
            productId: productId,
            file: packaging,
            imageRole: 'PACKAGING',
          );
        }
      }
      await repo.submitForReview(productId);
      var message = 'Photos enregistrées. Annonce envoyée en validation.';
      try {
        await repo.analyzeProduct(productId);
        message += ' Analyse IA terminée.';
      } catch (_) {
        message += ' Analyse IA en attente de configuration.';
      }
      if (!mounted) return;
      setState(() => _future = _loadProducts());
      _show(message);
    } catch (error) {
      _show('Ajout des photos impossible. Vérifiez le format et la taille des images, puis réessayez.');
    }
  }

  void _show(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits vendeur'),
        actions: [
          IconButton(
            onPressed: _create,
            tooltip: 'Ajouter un produit',
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            onPressed: () => setState(() => _future = _loadProducts()),
            icon: const Icon(Icons.refresh),
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de charger vos produits. Réessayez.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _loadProducts()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final products =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (products.isEmpty) {
            return const Center(
              child: Text('Aucun produit pour vos boutiques.'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _loadProducts());
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final product = products[index];
                final inventory = product['inventory'] is Map
                    ? Map<String, dynamic>.from(product['inventory'] as Map)
                    : const <String, dynamic>{};
                final shop = product['shops'] is Map
                    ? Map<String, dynamic>.from(product['shops'] as Map)
                    : const <String, dynamic>{};

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_outlined),
                    ),
                    title: Text(
                      product['name']?.toString() ?? 'Produit',
                    ),
                    subtitle: Text(
                      (shop['name']?.toString() ?? 'Boutique') +
                          '\nStatut : ' +
                          (product['status']?.toString() ?? '-') +
                          '\nStock : ' +
                          (inventory['quantity']?.toString() ?? '0') +
                          ' • Réservé : ' +
                          (inventory['reserved_quantity']?.toString() ??
                              '0'),
                    ),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        if (product['status']?.toString() != 'ACTIVE')
                          IconButton(
                            onPressed: () => _addPhotosForProduct(product['id'].toString()),
                            icon: const Icon(Icons.add_a_photo_outlined),
                            tooltip: 'Ajouter des photos et soumettre',
                          ),
                        IconButton(
                          onPressed: () => _editStock(product),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Modifier le stock',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog({
    required this.shops,
    required this.categories,
  });

  final List<Map<String, dynamic>> shops;
  final List<Map<String, dynamic>> categories;

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _description = TextEditingController();

  late String _shopId;
  String? _categoryId;
  bool _expirable = false;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _shopId = widget.shops.first['id'].toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate:
          _expiryDate ?? DateTime.now().add(const Duration(days: 30)),
    );

    if (!mounted || picked == null) return;
    setState(() => _expiryDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un produit'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _shopId,
              decoration: const InputDecoration(labelText: 'Boutique'),
              items: widget.shops
                  .map(
                    (shop) => DropdownMenuItem<String>(
                      value: shop['id'].toString(),
                      child: Text(shop['name']?.toString() ?? 'Boutique'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _shopId = value);
              },
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Prix XOF'),
            ),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock initial',
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sans catégorie'),
                ),
                ...widget.categories.map(
                  (category) => DropdownMenuItem<String?>(
                    value: category['id'].toString(),
                    child: Text(
                      category['name']?.toString() ?? 'Catégorie',
                    ),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _categoryId = value),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Produit avec date d’expiration'),
              value: _expirable,
              onChanged: (value) =>
                  setState(() => _expirable = value),
            ),
            if (_expirable)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _expiryDate == null
                      ? 'Date d’expiration'
                      : _expiryDate!
                          .toIso8601String()
                          .split('T')
                          .first,
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickExpiry,
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
            final name = _name.text.trim();
            final price = num.tryParse(_price.text.trim());
            final stock = int.tryParse(_stock.text.trim());

            if (name.length < 2 ||
                price == null ||
                price < 0 ||
                stock == null ||
                stock < 0 ||
                (_expirable && _expiryDate == null)) {
              return;
            }

            Navigator.pop(
              context,
              {
                'shop_id': _shopId,
                'name': name,
                'price': price,
                'initial_stock': stock,
                'category_id': _categoryId,
                'description': _description.text.trim(),
                'is_expirable': _expirable,
                'expiry_date': _expiryDate,
              },
            );
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
