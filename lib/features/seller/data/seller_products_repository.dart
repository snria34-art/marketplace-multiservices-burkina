import 'package:image_picker/image_picker.dart';

import '../../../core/media/upload_media_validator.dart';
import 'seller_product_validation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerProductsRepository {
  const SellerProductsRepository(this.client);

  final SupabaseClient client;

  Future<String?> _sellerId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    final sellerId = (rows.first as Map)['id']?.toString().trim();
    if (sellerId == null || !isValidSellerProductUuid(sellerId)) {
      throw StateError('seller_id_invalid');
    }
    return sellerId;
  }

  Future<List<Map<String, dynamic>>> shops() async {
    final sellerId = await _sellerId();
    if (sellerId == null) return const [];

    final rows = await client
        .from('shops')
        .select('id,name,status,verification_status')
        .eq('seller_id', sellerId)
        .order('created_at');

    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final rows = await client
        .from('categories')
        .select('id,name,slug')
        .eq('is_active', true)
        .order('sort_order')
        .limit(200);

    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> products() async {
    final sellerId = await _sellerId();
    if (sellerId == null) return const [];

    final shopsRows = await client
        .from('shops')
        .select('id')
        .eq('seller_id', sellerId);

    final shopIds = (shopsRows as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .toList();

    if (shopIds.isEmpty) return const [];

    final rows = await client
        .from('products')
        .select(
          'id,shop_id,category_id,name,slug,description,price,status,is_expirable,expiry_date,created_at,shops(name),inventory(quantity,reserved_quantity,updated_at)',
        )
        .inFilter('shop_id', shopIds)
        .order('created_at', ascending: false)
        .limit(500);

    return _maps(rows);
  }

  Future<String> createProduct({
    required String shopId,
    required String name,
    required num price,
    String? categoryId,
    String? description,
    int initialStock = 0,
    bool isExpirable = false,
    DateTime? expiryDate,
  }) async {
    final issue = validateSellerProductDraft(
      shopId: shopId,
      name: name,
      price: price,
      categoryId: categoryId,
      initialStock: initialStock,
      isExpirable: isExpirable,
      expiryDate: expiryDate,
    );
    if (issue != null) throw StateError(issue);

    final raw = await client.rpc(
      'create_seller_product',
      params: {
        'p_shop_id': shopId.trim(),
        'p_name': name.trim(),
        'p_price': price,
        'p_category_id': categoryId?.trim().isEmpty == true
            ? null
            : categoryId?.trim(),
        'p_description': description?.trim(),
        'p_initial_stock': initialStock,
        'p_is_expirable': isExpirable,
        'p_expiry_date':
            expiryDate?.toIso8601String().split('T').first,
      },
    );
    if (!isValidSellerProductResponse(raw)) {
      throw StateError('product_response_invalid');
    }
    return raw.toString().trim();
  }

  Future<void> uploadProductImage({
    required String productId,
    required XFile file,
    required String imageRole,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');
    if (!isValidSellerProductUuid(productId)) throw StateError('product_id_invalid');
    final roleIssue = validateSellerProductImageRole(imageRole);
    if (roleIssue != null) throw StateError(roleIssue);
    final normalizedImageRole = imageRole.trim().toUpperCase();
    const maxBytes = 5 * 1024 * 1024;
    final fileSize = await file.length();
    if (fileSize <= 0 || fileSize > maxBytes) {
      throw StateError('Chaque image doit faire au maximum 5 Mo.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Chaque image doit faire au maximum 5 Mo.');
    }
    const allowedImageTypes = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/heic': 'heic',
    };
    final reportedMime = (file.mimeType ?? '').toLowerCase().trim();
    final reportedExtension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final mime = reportedMime.isNotEmpty
        ? reportedMime
        : switch (reportedExtension) {
            'jpg' || 'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'webp' => 'image/webp',
            'heic' => 'image/heic',
            _ => '',
          };
    final extension = allowedImageTypes[mime];
    if (extension == null) {
      throw StateError(
        'Format non pris en charge. Utilisez une image JPEG, PNG, WebP ou HEIC.',
      );
    }
    UploadMediaValidator.requireMimeType(bytes, mime);

    final path =
        'products/$productId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage.from('product-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );

    try {
      await client.rpc('add_seller_product_image', params: {
        'p_product_id': productId,
        'p_storage_path': path,
        'p_image_role': normalizedImageRole,
        'p_alt_text': normalizedImageRole == 'PACKAGING'
            ? 'Photo de l’emballage'
            : normalizedImageRole == 'LABEL'
                ? 'Photo de l’étiquette'
                : 'Photo du produit',
      });
    } catch (_) {
      // Avoid leaving an unreferenced object when metadata registration fails.
      try {
        await client.storage.from('product-media').remove([path]);
      } catch (_) {
        // Storage cleanup is best-effort; the original error remains primary.
      }
      rethrow;
    }
  }

  Future<void> submitForReview(String productId) async {
    if (!isValidSellerProductUuid(productId)) throw StateError('product_id_invalid');
    await client.rpc('submit_seller_product_for_review', params: {
      'p_product_id': productId.trim(),
    });
  }

  Future<void> analyzeProduct(String productId) async {
    if (!isValidSellerProductUuid(productId)) throw StateError('product_id_invalid');
    await client.functions.invoke(
      'analyze-product',
      body: {'product_id': productId.trim()},
    );
  }

  Future<void> setStock({
    required String productId,
    required int quantity,
  }) async {
    if (!isValidSellerProductUuid(productId)) throw StateError('product_id_invalid');
    final issue = validateSellerStockQuantity(quantity);
    if (issue != null) throw StateError(issue);
    await client.rpc(
      'set_seller_stock',
      params: {
        'p_product_id': productId.trim(),
        'p_quantity': quantity,
      },
    );
  }

  Future<List<Map<String, dynamic>>> variantInventory(
    String productId,
  ) async {
    if (!isValidSellerProductUuid(productId)) throw StateError('product_id_invalid');
    final rows = await client.rpc(
      'get_seller_product_variant_inventory',
      params: {'p_product_id': productId.trim()},
    );
    return _maps(rows);
  }

  Future<void> setVariantStock({
    required String variantId,
    required int quantity,
  }) async {
    if (!isValidSellerProductUuid(variantId)) throw StateError('variant_id_invalid');
    final issue = validateSellerStockQuantity(quantity);
    if (issue != null) throw StateError(issue);
    await client.rpc(
      'set_seller_variant_stock',
      params: {
        'p_variant_id': variantId.trim(),
        'p_quantity': quantity,
      },
    );
  }

  List<Map<String, dynamic>> _maps(dynamic rows) {
    if (rows is! List) return const [];

    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
