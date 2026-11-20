import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() =>
      _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  static String get _recoveryRedirect => kIsWeb
      ? Uri.base.resolve('/auth/recovery').toString()
      : 'marketplaceburkina://auth/recovery';

  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendRecoveryEmail() async {
    final client = ref.read(marketplaceAuthenticationClientProvider);
    if (client == null) {
      _show('Le service de connexion est indisponible.');
      return;
    }

    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _show('Saisissez une adresse email valide.');
      return;
    }

    setState(() => _loading = true);
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: _recoveryRedirect,
      );

      if (!mounted) return;
      setState(() => _sent = true);
    } catch (_) {
      // Do not reveal whether an email address belongs to an existing account.
      _show(
        'La demande n’a pas pu être envoyée. Vérifiez votre connexion et '
        'réessayez plus tard.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.mark_email_unread_outlined, size: 52),
          const SizedBox(height: 16),
          Text(
            _sent
                ? 'Si un compte est associé à cette adresse, un email de '
                    'récupération a été envoyé. Ouvrez le lien sur le même appareil '
                    'pour créer un nouveau mot de passe.'
                : 'Saisissez l’adresse email de votre compte. Nous vous '
                    'enverrons un lien sécurisé pour réinitialiser votre mot '
                    'de passe.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (!_sent) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Adresse email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _sendRecoveryEmail,
              child: Text(
                _loading ? 'Envoi en cours…' : 'Envoyer le lien',
              ),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: () => setState(() => _sent = false),
              child: const Text('Renvoyer un email'),
            ),
          ],
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Retour à la connexion'),
          ),
        ],
      ),
    );
  }
}
