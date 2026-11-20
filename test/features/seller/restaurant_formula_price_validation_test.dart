import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/seller/data/restaurant_formula_price_validation.dart';

void main() {
  group('parseRestaurantFormulaPriceDelta', () {
    test('accepts zero as an included choice', () {
      expect(parseRestaurantFormulaPriceDelta('0'), 0);
    });

    test('accepts a seller-defined XOF surcharge', () {
      expect(parseRestaurantFormulaPriceDelta('750'), 750);
    });

    test('accepts a decimal numeric value supported by the database', () {
      expect(parseRestaurantFormulaPriceDelta('125.50'), 125.5);
    });

    test('rejects blank, malformed, non-finite and negative values', () {
      for (final value in ['', 'abc', 'NaN', 'Infinity', '-1']) {
        expect(
          parseRestaurantFormulaPriceDelta(value),
          isNull,
          reason: 'Invalid value: $value',
        );
      }
    });

    test('rejects values above the database upper bound', () {
      expect(parseRestaurantFormulaPriceDelta('100000001'), isNull);
    });
  });
}
