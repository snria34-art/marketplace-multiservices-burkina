/// Validates a seller-defined formula-choice surcharge in XOF.
///
/// The database applies the same upper bound. The customer never supplies this
/// value: it is stored in the seller-managed menu option and used by the
/// server-side quote RPC.
num? parseRestaurantFormulaPriceDelta(String value) {
  final parsed = num.tryParse(value.trim());
  if (parsed == null ||
      !parsed.isFinite ||
      parsed < 0 ||
      parsed > 100000000) {
    return null;
  }
  return parsed;
}
