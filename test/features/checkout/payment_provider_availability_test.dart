import 'package:flutter_test/flutter_test.dart';

import 'package:marketplace_multiservices_burkina/features/checkout/models/payment_provider_availability.dart';

void main() {
  group('PaymentProviderAvailability', () {
    test('normalizes provider identifiers consistently for repository calls', () {
      expect(PaymentProviderAvailability.normalizeProvider(' wave '), 'WAVE');
      expect(PaymentProviderAvailability.normalizeProvider('CinetPay'), 'CINETPAY');
      expect(
        () => PaymentProviderAvailability.normalizeProvider('ORANGE_MONEY'),
        throwsFormatException,
      );
      expect(
        () => PaymentProviderAvailability.normalizeProvider(''),
        throwsFormatException,
      );
    });

    test('accepts a configured Wave response', () {
      final result = PaymentProviderAvailability.fromResponse({
        'provider': 'WAVE',
        'configured': true,
        'status': 'CONFIGURED',
      });

      expect(result.provider, 'WAVE');
      expect(result.configured, isTrue);
    });

    test('accepts a not-configured CinetPay response without exposing secrets', () {
      final result = PaymentProviderAvailability.fromResponse({
        'provider': 'CINETPAY',
        'configured': false,
        'status': 'NOT_CONFIGURED',
      });

      expect(result.provider, 'CINETPAY');
      expect(result.configured, isFalse);
      expect(result.unavailableMessage, contains('CinetPay'));
      expect(result.unavailableMessage, contains('Aucune commande ne sera créée'));
    });

    test('normalizes provider casing but rejects inconsistent status', () {
      final result = PaymentProviderAvailability.fromResponse({
        'provider': 'wave',
        'configured': true,
        'status': 'CONFIGURED',
      });

      expect(result.provider, 'WAVE');

      expect(
        () => PaymentProviderAvailability.fromResponse({
          'provider': 'WAVE',
          'configured': true,
          'status': 'NOT_CONFIGURED',
        }),
        throwsFormatException,
      );
    });

    test('rejects missing or unsupported provider state', () {
      expect(
        () => PaymentProviderAvailability.fromResponse(null),
        throwsFormatException,
      );

      expect(
        () => PaymentProviderAvailability.fromResponse({
          'provider': 'ORANGE_MONEY',
          'configured': true,
          'status': 'CONFIGURED',
        }),
        throwsFormatException,
      );
    });
  });
}
