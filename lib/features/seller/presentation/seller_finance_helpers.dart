/// Pure helpers for the seller finance form. These do not call any
/// provider, create payout requests, or mutate financial data.
int? parsePositiveXofAmount(String raw) {
  final amount = int.tryParse(raw.trim());
  if (amount == null || amount <= 0) return null;
  return amount;
}

/// Converts backend error identifiers into safe, actionable French text.
/// Never displays raw server/database errors to the seller.
String sellerPayoutErrorMessage(Object error) {
  final message = error.toString().toLowerCase();

  if (message.contains('seller_payout_blocked_by_refund_reconciliation')) {
    return 'Retrait bloqué : un remboursement de commande doit encore être rapproché.';
  }
  if (message.contains('insufficient_seller_balance')) {
    return 'Solde disponible insuffisant pour ce montant.';
  }
  if (message.contains('seller_not_eligible') ||
      message.contains('seller_not_owned')) {
    return 'Le compte vendeur doit être vérifié et associé à votre compte.';
  }
  if (message.contains('amount_invalid')) {
    return 'Le montant demandé est invalide.';
  }
  if (message.contains('provider_invalid')) {
    return 'Le moyen de paiement sélectionné n’est pas pris en charge.';
  }
  if (message.contains('not_authenticated')) {
    return 'Votre session a expiré. Reconnectez-vous puis réessayez.';
  }

  return 'Demande impossible pour le moment. Vérifiez votre solde et réessayez.';
}
