import 'package:supabase_flutter/supabase_flutter.dart';

class _CachedSignedUrl {
  const _CachedSignedUrl(this.value, this.expiresAt);

  final Future<String?> value;
  final DateTime expiresAt;
}

class CatalogRepository {
  const CatalogRepository(this.client);

  final SupabaseClient client;
  final Map<String, _CachedSignedUrl> _imageUrlCache = {};

  Future<List<Map<String, dynamic>>> categoryTypes() async {
    final rows = await client
        .from('category_types')
        .select('id,name,slug,is_active,sort_order')
        .eq('is_active', true)
        .order('sort_order')
        .limit(50);

    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final rows = await client
        .from('categories')
        .select(
          'id,category_type_id,parent_id,name,slug,icon_url,image_url,is_active,sort_order',
        )
        .eq('is_active', true)
        .order('sort_order')
        .limit(200);

    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> products({
    String? categoryId,
    int offset = 0,
    int limit = 24,
  }) async {
    if (offset < 0 || limit <= 0 || limit > 100) {
      throw ArgumentError('Pagination invalide.');
    }

    final end = offset + limit - 1;

    var query = client
        .from('products')
        .select(
          'id,shop_id,category_id,name,slug,description,price,compare_at_price,'
          'status,is_expirable,expiry_date,created_at,'
          'shops(name,status),product_images(storage_path,sort_order,alt_text)',
        )
        .eq('status', 'ACTIVE');

    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.eq('category_id', categoryId);
    }

    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, end);

    return _maps(rows);
  }

  Future<String?> productImageUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final now = DateTime.now();
    final cached = _imageUrlCache[path];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return cached.value;
    }

    // The signed URL lasts 60 minutes. Stop reusing it after 55 minutes so
    // images are refreshed before the URL expires in a long-lived app session.
    final pending = _createSignedImageUrl(path);
    final entry = _CachedSignedUrl(
      pending,
      now.add(const Duration(minutes: 55)),
    );
    _imageUrlCache[path] = entry;

    try {
      final url = await pending;
      if (url == null && identical(_imageUrlCache[path], entry)) {
        _imageUrlCache.remove(path);
      }
      return url;
    } catch (_) {
      if (identical(_imageUrlCache[path], entry)) {
        _imageUrlCache.remove(path);
      }
      rethrow;
    }
  }

  Future<String?> _createSignedImageUrl(String path) async {
    try {
      return await client.storage
          .from('product-media')
          .createSignedUrl(path, 60 * 60);
    } on StorageException {
      return null;
    }
  }

  List<Map<String, dynamic>> _maps(dynamic rows) {
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
