/**
 * The browser redirect is not proof of payment. Only the signed provider
 * webhook and persisted payment state can confirm or reject a transaction.
 */
export function paymentReturnMessage(status: unknown): string {
  const normalized = typeof status === "string"
    ? status.trim().toLowerCase()
    : "";

  if (normalized === "success") {
    return "Le guichet a terminé sa redirection. Ce retour ne confirme pas à lui seul le paiement. La confirmation est vérifiée côté serveur ; revenez dans l’application pour consulter le statut de votre commande.";
  }
  if (normalized === "error") {
    return "Le guichet a renvoyé un état d’erreur. Ce retour ne modifie pas le statut enregistré ; revenez dans l’application pour vérifier votre commande.";
  }
  return "Retour du guichet de paiement reçu. Revenez dans l’application pour consulter le statut confirmé côté serveur.";
}
