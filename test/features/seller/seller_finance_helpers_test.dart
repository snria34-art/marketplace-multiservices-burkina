import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/seller/presentation/seller_finance_helpers.dart';

void main() {
  group('parsePositiveXofAmount', () {
    test('accepts a positive whole XOF amount', () {
      expect(parsePositiveXofAmount('12500'), 12500);
      expect(parsePositiveXofAmount('  12500  '), 12500);
    });

    test('rejects decimals and scientific notation', () {
      expect(parsePositiveXofAmount('12500.50'), isNull);
      expect(parsePositiveXofAmount('1e3'), isNull);
      expect(parsePositiveXofAmount('1,000'), isNull);
    });

    test('rejects zero, negative, empty, and non-numeric values', () {
      expect(parsePositiveXofAmount('0'), isNull);
      expect(parsePositiveXofAmount('-1'), isNull);
      expect(parsePositiveXofAmount(''), isNull);
      expect(parsePositiveXofAmount('abc'), isNull);
    });
  });

  group('sellerPayoutErrorMessage', () {
    test('explains reconciliation and balance blocks', () {
      expect(
        sellerPayoutErrorMessage(
          Exception('seller_payout_blocked_by_refund_reconciliation'),
        ),
        contains('remboursement'),
      );
      expect(
        sellerPayoutErrorMessage(Exception('insufficient_seller_balance')),
        contains('insuffisant'),
      );
    });

    test('explains account, provider, and session errors', () {
      expect(
        sellerPayoutErrorMessage(Exception('seller_not_owned')),
        contains('associé'),
      );
      expect(
        sellerPayoutErrorMessage(Exception('provider_invalid')),
        contains('pas pris en charge'),
      );
      expect(
        sellerPayoutErrorMessage(Exception('not_authenticated')),
        contains('session a expiré'),
      );
    });

    test('does not surface unknown raw backend errors', () {
      expect(
        sellerPayoutErrorMessage(Exception('sensitive_database_detail')),
        'Demande impossible pour le moment. Vérifiez votre solde et réessayez.',
      );
    });
  });
}
