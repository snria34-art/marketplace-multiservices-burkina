/// Detects exception and database diagnostics embedded in UI messages.
bool containsRawBackendErrorDetails(String message) {
  return RegExp(
    r'(?:[A-Za-z]+Exception|Exception:|Error:|PGRST\\d*|SQLSTATE|Postgrest|'
    r'row-level security|permission denied|JWT expired|failed host lookup|'
    r'timed out|not_authenticated|bad state:|duplicate key|violates .* constraint|'
    r'unauthorized|forbidden|connection reset|connection refused|'
    r'network is unreachable|invalid credentials)',
    caseSensitive: false,
  ).hasMatch(message);
}

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
