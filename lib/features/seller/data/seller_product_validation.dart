final RegExp _sellerProductUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isValidSellerProductUuid(String value) =>
    _sellerProductUuidPattern.hasMatch(value.trim());

/// Mirrors the public constraints of create_seller_product.
/// The secure SQL RPC remains authoritative for ownership and category status.
String? validateSellerProductDraft({
  required String shopId,
  required String name,
  required num price,
  String? categoryId,
  required int initialStock,
  required bool isExpirable,
  DateTime? expiryDate,
  DateTime? today,
}) {
  if (!isValidSellerProductUuid(shopId)) return 'shop_id_invalid';
  final normalizedName = name.trim();
  if (normalizedName.length < 2 || normalizedName.length > 180) {
    return 'name_invalid';
  }
  if (!price.isFinite || price < 0) return 'price_invalid';
  if (initialStock < 0 || initialStock > 1000000) return 'stock_invalid';
  final normalizedCategory = categoryId?.trim();
  if (normalizedCategory != null &&
      normalizedCategory.isNotEmpty &&
      !isValidSellerProductUuid(normalizedCategory)) {
    return 'category_invalid';
  }
  if (isExpirable) {
    if (expiryDate == null) return 'expiry_date_required';
    final referenceDate = today ?? DateTime.now();
    final todayDate = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    if (expiry.isBefore(todayDate)) return 'expiry_date_invalid';
  }
  return null;
}

String? validateSellerStockQuantity(int quantity) {
  if (quantity < 0 || quantity > 1000000) return 'stock_invalid';
  return null;
}

String? validateSellerProductImageRole(String imageRole) {
  const roles = {'PRODUCT', 'PACKAGING', 'LABEL'};
  return roles.contains(imageRole.trim().toUpperCase()) ? null : 'image_role_invalid';
}

bool isValidSellerProductResponse(Object? response) =>
    response != null && isValidSellerProductUuid(response.toString());
