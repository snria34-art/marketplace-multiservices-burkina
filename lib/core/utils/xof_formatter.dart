/// Formats all marketplace monetary values in West African CFA francs.
/// XOF is the ISO currency code; the user-facing label is F CFA.
String formatXof(num value) {
  final rounded = value.round().toString();
  final grouped = rounded.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
  return '$grouped F CFA';
}
