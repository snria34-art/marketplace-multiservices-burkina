const Set<String> allowedSellerPayoutProviders = {
  'ORANGE_MONEY',
  'WAVE',
  'MOOV_MONEY',
};

final RegExp _canonicalUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isCanonicalUuid(String value) =>
    _canonicalUuidPattern.hasMatch(value.trim());

/// Validates a seller payout request locally before the secure RPC is called.
/// The server still performs the authoritative ownership, eligibility and
/// ledger checks under a row lock.
String? validateSellerPayoutRequest({
  required String sellerId,
  required num amount,
  required String provider,
}) {
  if (!isCanonicalUuid(sellerId)) return 'seller_id_invalid';
  if (amount is! int || amount <= 0) return 'amount_invalid';
  if (!allowedSellerPayoutProviders.contains(provider.trim().toUpperCase())) {
    return 'provider_invalid';
  }
  return null;
}

bool isValidSellerPayoutResponse(String value) =>
    isCanonicalUuid(value);
