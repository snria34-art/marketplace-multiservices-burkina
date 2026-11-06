/// Public, non-sensitive configuration state returned by the payment
/// provider preflight Edge Function.
class PaymentProviderAvailability {
  const PaymentProviderAvailability({
    required this.provider,
    required this.configured,
  });

  final String provider;
  final bool configured;

  factory PaymentProviderAvailability.fromResponse(dynamic response) {
    if (response is! Map) {
      throw const FormatException(
        'Réponse de configuration du paiement invalide.',
      );
    }

    final provider = response['provider']?.toString().trim().toUpperCase();
    final status = response['status']?.toString().trim().toUpperCase();
    final configured = response['configured'];

    if ((provider != 'WAVE' && provider != 'CINETPAY') ||
        configured is! bool ||
        (status != 'CONFIGURED' && status != 'NOT_CONFIGURED') ||
        (status == 'CONFIGURED' && configured != true) ||
        (status == 'NOT_CONFIGURED' && configured != false)) {
      throw const FormatException(
        'État de configuration du paiement incohérent.',
      );
    }

    return PaymentProviderAvailability(
      provider: provider!,
      configured: configured,
    );
  }

  String get unavailableMessage {
    if (provider == 'WAVE') {
      return 'Wave n’est pas encore configuré. Aucune commande ne sera créée. '
          'Choisissez un autre moyen de paiement ou réessayez plus tard.';
    }

    return 'CinetPay n’est pas encore configuré. Aucune commande ne sera créée. '
        'Choisissez un autre moyen de paiement ou réessayez plus tard.';
  }
}
