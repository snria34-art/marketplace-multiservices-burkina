/// XOF payment and refund amounts must be positive whole units.
class XofAmount {
  const XofAmount._();

  /// Parses decimal digits only and rejects values unsafe for JavaScript/JSON
  /// number round-tripping across the Edge Function boundary.
  static int? parsePositiveInteger(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(normalized)) return null;

    final amount = int.tryParse(normalized);
    if (amount == null ||
        amount <= 0 ||
        amount > 9007199254740991) {
      return null;
    }
    return amount;
  }
}
