import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/account_session_action_button.dart';
import '../../modules/presentation/service_module_sliver.dart';
import '../../modules/presentation/future_capabilities_sliver.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  late Future<_CatalogMetadata> _metadataFuture;
  List<Map<String, dynamic>> _products = [];
  String? _selectedTypeId;
  String? _selectedCategoryId;
  int _page = 0;
  bool _loadingProducts = false;
  bool _hasMore = true;
  int _productRequestId = 0;
  String? _productsError;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _metadataFuture = _loadMetadata();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<_CatalogMetadata> _loadMetadata() async {
    final repo = ref.read(catalogRepositoryProvider);

    if (repo == null) {
      return const _CatalogMetadata(types: [], categories: []);
    }

    final results = await Future.wait([
      repo.categoryTypes(),
      repo.categories(),
    ]);

    final types = results[0];
    final categories = results[1];

    if (!mounted) {
      return _CatalogMetadata(types: types, categories: categories);
    }

    if (types.isNotEmpty && _selectedTypeId == null) {
      _selectedTypeId = types.first['id']?.toString();
    }

    await _loadProducts(reset: true);

    return _CatalogMetadata(types: types, categories: categories);
  }

  Future<void> _loadProducts({required bool reset}) async {
    if ((!reset && _loadingProducts) || (!reset && !_hasMore)) return;

    final repo = ref.read(catalogRepositoryProvider);
    if (repo == null) return;

    if (reset) {
      _page = 0;
      _hasMore = true;
      _productsError = null;
    }

    final requestId = ++_productRequestId;
    if (mounted) setState(() => _loadingProducts = true);

    try {
      final rows = await repo.products(
        categoryId: _selectedCategoryId,
        searchQuery: _searchTerm,
        offset: _page * 24,
        limit: 24,
      );

      if (!mounted || requestId != _productRequestId) return;

      setState(() {
        if (reset) {
          _products = rows;
        } else {
          _products = [..._products, ...rows];
        }

        _hasMore = rows.length == 24;
        if (_hasMore) _page++;
        _productsError = null;
      });
    } catch (error) {
      if (!mounted || requestId != _productRequestId) return;
      setState(
        () => _productsError = safeBackendErrorMessage(
          error,
          fallback: 'Catalogue indisponible. Vérifiez Internet et réessayez.',
        ),
      );
    } finally {
      if (mounted && requestId == _productRequestId) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.extentAfter < 700) {
      _loadProducts(reset: false);
    }
  }

  void _selectCategory(String? categoryId) {
    setState(() => _selectedCategoryId = categoryId);
    _loadProducts(reset: true);
  }

  void _submitSearch(String value) {
    final term = value.trim();
    if (term == _searchTerm) return;
    setState(() => _searchTerm = term);
    _loadProducts(reset: true);
  }

  List<Map<String, dynamic>> _visibleCategories(_CatalogMetadata metadata) {
    if (_selectedTypeId == null) return metadata.categories;

    return metadata.categories
        .where(
          (item) => item['category_type_id']?.toString() == _selectedTypeId,
        )
        .toList();
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final cart = ref.read(cartRepositoryProvider);
    final client = ref.read(marketplaceCustomerClientProvider);

    if (client == null || cart == null || client.auth.currentUser == null) {
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
              fallback: 'Impossible d’ajouter ce produit au panier. Réessayez.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace Burkina'),
        actions: [
          IconButton(
            tooltip: 'Panier',
            onPressed: () => context.push('/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Paramètres de l’application',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          const AccountSessionActionButton(),
        ],
      ),
      body: FutureBuilder<_CatalogMetadata>(
        future: _metadataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return AppErrorView(
              message: 'Catalogue indisponible. Réessayez.',
              onRetry: () {
                setState(() => _metadataFuture = _loadMetadata());
              },
            );
          }

          final metadata =
              snapshot.data ??
              const _CatalogMetadata(types: [], categories: []);

          final categories = _visibleCategories(metadata);

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _CatalogHeaderDelegate(
                  searchController: _searchController,
                  onSearchSubmitted: _submitSearch,
                  types: metadata.types,
                  categories: categories,
                  selectedTypeId: _selectedTypeId,
                  selectedCategoryId: _selectedCategoryId,
                  onTypeSelected: (id) {
                    setState(() {
                      _selectedTypeId = id;
                      _selectedCategoryId = null;
                    });
                    _loadProducts(reset: true);
                  },
                  onCategorySelected: _selectCategory,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: _HomePromotionBanner(
                    onTap: () => context.push('/promotions'),
                  ),
                ),
              ),
              const ServiceModuleSliver(),
              const FutureCapabilitiesSliver(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _searchTerm.isEmpty ? 'À découvrir' : 'Résultats de recherche',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _searchTerm.isEmpty
                            ? 'Des produits sélectionnés pour votre quotidien'
                            : 'Recherche : « $_searchTerm »',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_productsError != null && _products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_outlined, size: 42),
                          const SizedBox(height: 8),
                          const Text('Le catalogue n’a pas pu être chargé.'),
                          Text(
                            _productsError!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _loadProducts(reset: true),
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_products.isEmpty && !_loadingProducts)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('Aucun produit disponible actuellement.'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= _products.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final product = _products[index];
                        final rawImages = product['product_images'];
                        final firstImage =
                            rawImages is List &&
                                rawImages.isNotEmpty &&
                                rawImages.first is Map
                            ? Map<String, dynamic>.from(rawImages.first as Map)
                            : const <String, dynamic>{};
                        final storagePath = firstImage['storage_path']
                            ?.toString();
                        final catalog = ref.read(catalogRepositoryProvider);

                        return _ProductCard(
                          product: product,
                          imageUrl: storagePath == null || catalog == null
                              ? Future.value(null)
                              : catalog.productImageUrl(storagePath),
                          onAdd: () => _addToCart(product),
                        );
                      },
                      childCount: _products.length + (_loadingProducts ? 1 : 0),
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 320,
                        ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/services'),
        icon: const Icon(Icons.apps_outlined),
        label: const Text('Services'),
      ),
    );
  }
}

class _HomePromotionBanner extends StatelessWidget {
  const _HomePromotionBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 136),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary,
                Color.alphaBlend(colors.tertiary.withValues(alpha: 0.42), colors.primary),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Vos achats,\nplus simplement',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Produits, services et boutiques près de vous',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: colors.onPrimary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        'Découvrir les offres  ›',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.shopping_bag_rounded,
                size: 68,
                color: colors.onPrimary.withValues(alpha: 0.88),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogMetadata {
  const _CatalogMetadata({required this.types, required this.categories});

  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmitted;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> categories;
}

class _CatalogHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CatalogHeaderDelegate({
    required this.searchController,
    required this.onSearchSubmitted,
    required this.types,
    required this.categories,
    required this.selectedTypeId,
    required this.selectedCategoryId,
    required this.onTypeSelected,
    required this.onCategorySelected,
  });

  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> categories;
  final String? selectedTypeId;
  final String? selectedCategoryId;
  final ValueChanged<String?> onTypeSelected;
  final ValueChanged<String?> onCategorySelected;

  @override
  double get minExtent => 204;

  @override
  double get maxExtent => 204;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      elevation: overlapsContent ? 2 : 0,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: onSearchSubmitted,
                decoration: InputDecoration(
                  hintText: 'Rechercher un produit…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Effacer la recherche',
                    onPressed: () {
                      searchController.clear();
                      onSearchSubmitted('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final type = types[index];
                  final id = type['id']?.toString();

                  return ChoiceChip(
                    selected: id == selectedTypeId,
                    onSelected: (_) => onTypeSelected(id),
                    label: Text(type['name']?.toString() ?? ''),
                  );
                },
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) {
                  final category = categories[index];
                  final id = category['id']?.toString();
                  final selected = id == selectedCategoryId;

                  return InkWell(
                    borderRadius: BorderRadius.circular(42),
                    onTap: () => onCategorySelected(selected ? null : id),
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 28,
                            child: Icon(
                              selected ? Icons.check : Icons.category_outlined,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            category['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CatalogHeaderDelegate oldDelegate) {
    return oldDelegate.searchController != searchController ||
        oldDelegate.onSearchSubmitted != onSearchSubmitted ||
        oldDelegate.types != types ||
        oldDelegate.categories != categories ||
        oldDelegate.selectedTypeId != selectedTypeId ||
        oldDelegate.selectedCategoryId != selectedCategoryId;
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.imageUrl,
    required this.onAdd,
  });

  final Map<String, dynamic> product;
  final Future<String?> imageUrl;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final rawShop = product['shops'];
    final shop = rawShop is Map
        ? Map<String, dynamic>.from(rawShop)
        : const <String, dynamic>{};

    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<String?>(
                  future: imageUrl,
                  builder: (context, snapshot) {
                    final url = snapshot.data;
                    if (url == null || url.isEmpty) {
                      return const _ProductImagePlaceholder();
                    }
                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ProductImagePlaceholder(),
                    );
                  },
                ),
                Positioned(
                  top: 9,
                  left: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      child: Text(
                        'Marketplace',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
              product['name']?.toString() ?? 'Produit',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${product['price']?.toString() ?? '0'} XOF',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shop['name']?.toString() ?? 'Boutique',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Ajouter au panier',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
