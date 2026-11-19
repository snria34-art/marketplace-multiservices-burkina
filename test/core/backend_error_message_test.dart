import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/errors/backend_error_message.dart';

void main() {
  const fallback = 'Action impossible pour le moment.';

  test('detects backend exception diagnostics but not ordinary user text', () {
    expect(
      containsRawBackendErrorDetails(
        'Chargement impossible : PostgrestException: permission denied',
      ),
      isTrue,
    );
    expect(
      containsRawBackendErrorDetails('Code SQLSTATE 42501'),
      isTrue,
    );
    expect(
      containsRawBackendErrorDetails('Connectez-vous pour continuer.'),
      isFalse,
    );
    expect(
      containsRawBackendErrorDetails('Aucune chambre disponible.'),
      isFalse,
    );
  });

  test('maps expired sessions without exposing backend details', () {
    expect(
      safeBackendErrorMessage(Exception('JWT expired'), fallback: fallback),
      contains('session a expiré'),
    );
  });

  test('maps authorization and membership failures', () {
    expect(
      safeBackendErrorMessage(
        Exception('42501 permission denied'),
        fallback: fallback,
      ),
      contains('droits nécessaires'),
    );
    expect(
      safeBackendErrorMessage(
        Exception('conversation_not_found'),
        fallback: fallback,
      ),
      contains('droits nécessaires'),
    );
  });

  test('maps network failures', () {
    expect(
      safeBackendErrorMessage(
        Exception('SocketException: failed host lookup'),
        fallback: fallback,
      ),
      contains('Connexion au serveur indisponible'),
    );
  });

  test('maps message validation failures', () {
    expect(
      safeBackendErrorMessage(
        Exception('message_too_long'),
        fallback: fallback,
      ),
      contains('dépasse la limite'),
    );
  });

  test('uses a generic fallback for unknown database errors', () {
    expect(
      safeBackendErrorMessage(
        Exception('relation private.secret does not exist'),
        fallback: fallback,
      ),
      fallback,
    );
  });
}
