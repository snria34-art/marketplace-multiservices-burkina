import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class ShopPage extends ConsumerStatefulWidget {
  const ShopPage({super.key, required this.shopId});
  final String shopId;

  @override
  ConsumerState<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends ConsumerState<ShopPage> {
  late Future<_ShopContent> _future;
  bool? _isFollowing;
  bool _followLoading = false;
  String _sort = 'newest';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ShopContent> _load() async {
    final repo = ref.read(catalogRepositoryProvider);
    if (repo == null) throw StateError('Catalogue indisponible.');
    final results = await Future.wait<dynamic>([
      repo.shopDetails(widget.shopId),
      repo.products(shopId: widget.shopId, limit: 60),
    ]);
    final shop = results[0] as Map<String, dynamic>?;
    if (shop == null) throw StateError('Boutique introuvable ou indisponible.');

    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser != null) {
      try {
        final followed = await client!.rpc(
          'my_followed_shops',
          params: {'p_limit': 100},
        );
        final rows = followed is List
            ? followed.whereType<Map>().toList()
            : const <Map>[];
        _isFollowing = rows.any(
          (row) => row['shop_id']?.toString() == widget.shopId,
        );
      } catch (_) {
        _isFollowing ??= false;
      }
    }
    return _ShopContent(
      shop: shop,
      products: results[1] as List<Map<String, dynamic>>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _toggleFollow() async {
    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null) {
      if (mounted) context.push('/auth');
      return;
    }
    if (_followLoading) return;
    setState(() => _followLoading = true);
    try {
      final result = await client!.rpc(
        'toggle_shop_follow',
        params: {'p_shop_id': widget.shopId},
      );
      if (!mounted) return;
      setState(() => _isFollowing = result == true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == true
                ? 'Boutique ajoutée à vos suivis.'
                : 'Boutique retirée de vos suivis.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeBackendErrorMessage(
              error,
              fallback: 'Impossible de modifier le suivi de cette boutique.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final client = ref.read(supabaseProvider);
    final cart = ref.read(cartRepositoryProvider);
    if (client?.auth.currentUser == null || cart == null) {
      if (mounted) context.push('/auth');
      return;
    }
    try {
      await cart.addToCart(productId: product['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit ajouté au panier.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeBackendErrorMessage(
              error,
              fallback: 'Impossible d’ajouter ce produit au panier.',
            ),
          ),
        ),
      );
    }
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> products) {
    final rows = [...products];
    switch (_sort) {
      case 'price_low':
        rows.sort(
          (a, b) => ((a['price'] as num?) ?? 0)
              .compareTo((b['price'] as num?) ?? 0),
        );
        break;
      case 'price_high':
        rows.sort(
          (a, b) => ((b['price'] as num?) ?? 0)
              .compareTo((a['price'] as num?) ?? 0),
        );
        break;
      default:
        rows.sort(
          (a, b) => (DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
    }
    return rows;
  }

  Widget _image(
    BuildContext context,
    Future<String?> future, {
    required double height,
    IconData fallback = Icons.storefront_outlined,
  }) {
    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return Container(
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(fallback, size: 48),
          );
        }
        return Image.network(
          url,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(fallback, size: 48),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(catalogRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boutique'),
        actions: [
          IconButton(
            tooltip: 'Panier',
            onPressed: () => context.push('/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
        ],
      ),
      body: FutureBuilder<_ShopContent>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.store_mall_directory_outlined, size: 46),
                    const SizedBox(height: 12),
                    const Text(
                      'Boutique indisponible.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      safeBackendErrorMessage(
                        snapshot.error ?? StateError('Boutique introuvable.'),
                        fallback: 'Vérifiez votre connexion et réessayez.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final content = snapshot.data!;
          final shop = content.shop;
          final products = _sorted(content.products);
          final cover = shop['cover_url']?.toString() ?? '';
          final logo = shop['logo_url']?.toString() ?? '';

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (repo != null && cover.isNotEmpty)
                        _image(
                          context,
                          repo.shopImageUrl(cover),
                          height: 156,
                          fallback: Icons.image_outlined,
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (repo != null && logo.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: FutureBuilder<String?>(
                                    future: repo.shopImageUrl(logo),
                                    builder: (context, image) {
                                      final url = image.data;
                                      return url == null
                                          ? const Icon(Icons.storefront_outlined)
                                          : Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(Icons.storefront_outlined),
                                            );
                                    },
                                  ),
                                ),
                              )
                            else
                              const CircleAvatar(
                                radius: 32,
                                child: Icon(Icons.storefront_outlined, size: 30),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shop['name']?.toString() ?? 'Boutique',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  if ((shop['description']?.toString() ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        shop['description'].toString(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if ((shop['address']?.toString() ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        shop['address'].toString(),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _followLoading ? null : _toggleFollow,
                                icon: _followLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _isFollowing == true
                                            ? Icons.check
                                            : Icons.add,
                                      ),
                                label: Text(
                                  _isFollowing == true
                                      ? 'Suivie'
                                      : 'Suivre la boutique',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Contacter la boutique',
                              onPressed: () => context.push('/messages'),
                              icon: const Icon(Icons.chat_bubble_outline),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Tous les produits (' + products.length.toString() + ')',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            DropdownButton<String>(
                              value: _sort,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'newest',
                                  child: Text('Nouveautés'),
                                ),
                                DropdownMenuItem(
                                  value: 'price_low',
                                  child: Text('Prix croissant'),
                                ),
                                DropdownMenuItem(
                                  value: 'price_high',
                                  child: Text('Prix décroissant'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _sort = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (products.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('Aucun produit disponible dans cette boutique.'),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = products[index];
                          final rawImages = product['product_images'];
                          final image = rawImages is List &&
                                  rawImages.isNotEmpty &&
                                  rawImages.first is Map
                              ? Map<String, dynamic>.from(rawImages.first as Map)
                              : const <String, dynamic>{};
                          final path = image['storage_path']?.toString() ?? '';
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: FutureBuilder<String?>(
                                    future: repo!.productImageUrl(path),
                                    builder: (context, imageSnapshot) {
                                      final url = imageSnapshot.data;
                                      if (url == null || url.isEmpty) {
                                        return const Center(
                                          child: Icon(Icons.image_outlined, size: 46),
                                        );
                                      }
                                      return Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const Center(
                                          child: Icon(Icons.image_outlined, size: 46),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                                  child: Text(
                                    product['name']?.toString() ?? 'Produit',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    (product['price'] ?? 0).toString() + ' XOF',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    tooltip: 'Ajouter au panier',
                                    onPressed: () => _addToCart(product),
                                    icon: const Icon(Icons.add_shopping_cart_outlined),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        childCount: products.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 230,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 320,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShopContent {
  const _ShopContent({required this.shop, required this.products});
  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> products;
}
