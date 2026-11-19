import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/seller/data/seller_payout_validation.dart';

void main() {
  const validSellerId = '9f7b7f2c-6a88-4a64-aebf-7f7c6df7d4b1';
  const validPayoutId = 'f76bcd21-c66c-4f09-95b4-5778bb9849b6';

  group('isCanonicalUuid', () {
    test('accepts canonical UUID strings', () {
      expect(isCanonicalUuid(validSellerId), isTrue);
      expect(isCanonicalUuid(' $validSellerId '), isTrue);
    });

    test('rejects project references and malformed identifiers', () {
      expect(isCanonicalUuid('piojnvhpqbyvaijzhatm'), isFalse);
      expect(isCanonicalUuid(''), isFalse);
      expect(isCanonicalUuid('not-a-uuid'), isFalse);
      expect(isCanonicalUuid('9f7b7f2c-6a88-4a64-aebf'), isFalse);
    });
  });

  group('validateSellerPayoutRequest', () {
    test('accepts a valid seller, positive integer XOF and allowed provider', () {
      expect(
        validateSellerPayoutRequest(
          sellerId: validSellerId,
          amount: 12500,
          provider: 'ORANGE_MONEY',
        ),
        isNull,
      );
    });

    test('rejects invalid seller identifiers before an RPC can be called', () {
      expect(
        validateSellerPayoutRequest(
          sellerId: 'piojnvhpqbyvaijzhatm',
          amount: 12500,
          provider: 'WAVE',
        ),
        'seller_id_invalid',
      );
    });

    test('rejects zero, negative, decimal and non-finite amounts', () {
      for (final amount in <num>[0, -1, 10.5, double.nan, double.infinity]) {
        expect(
          validateSellerPayoutRequest(
            sellerId: validSellerId,
            amount: amount,
            provider: 'WAVE',
          ),
          'amount_invalid',
        );
      }
    });

    test('accepts the three supported providers case-insensitively', () {
      for (final provider in <String>[
        'ORANGE_MONEY',
        'wave',
        'Moov_Money',
      ]) {
        expect(
          validateSellerPayoutRequest(
            sellerId: validSellerId,
            amount: 1000,
            provider: provider,
          ),
          isNull,
        );
      }
    });

    test('rejects unsupported providers', () {
      expect(
        validateSellerPayoutRequest(
          sellerId: validSellerId,
          amount: 1000,
          provider: 'UNKNOWN',
        ),
        'provider_invalid',
      );
    });
  });

  group('isValidSellerPayoutResponse', () {
    test('accepts a UUID returned by the secure RPC', () {
      expect(isValidSellerPayoutResponse(validPayoutId), isTrue);
    });

    test('rejects null-like and malformed RPC responses', () {
      expect(isValidSellerPayoutResponse('null'), isFalse);
      expect(isValidSellerPayoutResponse(''), isFalse);
      expect(isValidSellerPayoutResponse('unexpected-response'), isFalse);
    });
  });
}
