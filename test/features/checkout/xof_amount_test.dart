import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/checkout/models/xof_amount.dart';

void main() {
  group('XofAmount.parsePositiveInteger', () {
    test('accepts positive whole XOF amounts', () {
      expect(XofAmount.parsePositiveInteger('1'), 1);
      expect(XofAmount.parsePositiveInteger(' 1500 '), 1500);
      expect(XofAmount.parsePositiveInteger('00050'), 50);
      expect(
        XofAmount.parsePositiveInteger('9007199254740991'),
        9007199254740991,
      );
    });

    test('rejects fractional, zero, negative and coercible strings', () {
      for (final value in [
        '',
        ' ',
        '0',
        '-1',
        '+1',
        '1.5',
        '1.0',
        '1e3',
        'NaN',
        'Infinity',
        '9007199254740992',
      ]) {
        expect(
          XofAmount.parsePositiveInteger(value),
          isNull,
          reason: 'must reject $value',
        );
      }
    });
  });
}
