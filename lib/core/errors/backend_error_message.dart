/// Converts backend failures into messages safe to display to end users.
/// Raw Postgres/PostgREST details must stay in diagnostic logs, not the UI.
String safeBackendErrorMessage(
  Object error, {
  required String fallback,
}) {
  final message = error.toString().toLowerCase();

  if (message.contains('not_authenticated') ||
      message.contains('jwt expired') ||
      message.contains('authentification requise') ||
      message.contains('unauthenticated')) {
    return 'Votre session a expiré. Reconnectez-vous puis réessayez.';
  }

  if (message.contains('42501') ||
      message.contains('permission denied') ||
      message.contains('row-level security') ||
      message.contains('not_member') ||
      message.contains('conversation_not_found')) {
    return 'Vous ne disposez pas des droits nécessaires pour effectuer cette action.';
  }

  if (message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('timed out') ||
      message.contains('network is unreachable') ||
      message.contains('connection reset') ||
      message.contains('clientexception')) {
    return 'Connexion au serveur indisponible. Vérifiez Internet et réessayez.';
  }

  if (message.contains('message_invalid') ||
      message.contains('message_too_long')) {
    return 'Le message est vide ou dépasse la limite autorisée.';
  }

  return fallback;
}
