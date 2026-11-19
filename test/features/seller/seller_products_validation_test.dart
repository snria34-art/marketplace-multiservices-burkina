import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/seller/data/seller_product_validation.dart';

void main() {
  const shopId = '9f7b7f2c-6a88-4a64-aebf-7f7c6df7d4b1';
  const categoryId = 'f76bcd21-c66c-4f09-95b4-5778bb9849b6';

  group('validateSellerProductDraft', () {
    test('accepts a valid ordinary product draft', () {
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Riz local', price: 1500,
        categoryId: categoryId, initialStock: 12, isExpirable: false,
      ), isNull);
    });

    test('rejects malformed shop and category identifiers', () {
      expect(validateSellerProductDraft(
        shopId: 'not-a-uuid', name: 'Riz', price: 1000,
        initialStock: 1, isExpirable: false,
      ), 'shop_id_invalid');
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Riz', price: 1000,
        categoryId: 'bad-category-id', initialStock: 1, isExpirable: false,
      ), 'category_invalid');
    });

    test('enforces SQL name and price constraints', () {
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'A', price: 1000, initialStock: 0, isExpirable: false,
      ), 'name_invalid');
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Riz', price: -1, initialStock: 0, isExpirable: false,
      ), 'price_invalid');
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Riz', price: double.infinity, initialStock: 0, isExpirable: false,
      ), 'price_invalid');
    });

    test('bounds initial stock', () {
      for (final stock in [-1, 1000001]) {
        expect(validateSellerProductDraft(
          shopId: shopId, name: 'Riz', price: 1000,
          initialStock: stock, isExpirable: false,
        ), 'stock_invalid');
      }
    });

    test('requires a non-expired date for expirable products', () {
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Yaourt', price: 500, initialStock: 10,
        isExpirable: true, today: DateTime(2026, 11, 20),
      ), 'expiry_date_required');
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Yaourt', price: 500, initialStock: 10,
        isExpirable: true, expiryDate: DateTime(2026, 11, 19, 23, 59),
        today: DateTime(2026, 11, 20, 12),
      ), 'expiry_date_invalid');
      expect(validateSellerProductDraft(
        shopId: shopId, name: 'Yaourt', price: 500, initialStock: 10,
        isExpirable: true, expiryDate: DateTime(2026, 11, 20),
        today: DateTime(2026, 11, 20, 12),
      ), isNull);
    });
  });

  group('stock, media and RPC response validation', () {
    test('bounds stock changes', () {
      expect(validateSellerStockQuantity(0), isNull);
      expect(validateSellerStockQuantity(1000000), isNull);
      expect(validateSellerStockQuantity(-1), 'stock_invalid');
      expect(validateSellerStockQuantity(1000001), 'stock_invalid');
    });

    test('allows documented product media roles only', () {
      expect(validateSellerProductImageRole('PRODUCT'), isNull);
      expect(validateSellerProductImageRole('packaging'), isNull);
      expect(validateSellerProductImageRole('LABEL'), isNull);
      expect(validateSellerProductImageRole('UNREVIEWED'), 'image_role_invalid');
    });

    test('requires UUID from product creation RPC', () {
      expect(isValidSellerProductResponse(shopId), isTrue);
      expect(isValidSellerProductResponse(null), isFalse);
      expect(isValidSellerProductResponse('null'), isFalse);
      expect(isValidSellerProductResponse('unexpected-response'), isFalse);
    });
  });
}
