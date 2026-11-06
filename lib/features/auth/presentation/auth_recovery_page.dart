import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_recovery_state.dart';
import '../../../core/providers/repository_providers.dart';

class AuthRecoveryPage extends ConsumerStatefulWidget {
  const AuthRecoveryPage({super.key});

  @override
  ConsumerState<AuthRecoveryPage> createState() => _AuthRecoveryPageState();
}

class _AuthRecoveryPageState extends ConsumerState<AuthRecoveryPage> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _saveNewPassword() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      _show('Le service de connexion est indisponible.');
      return;
    }

    if (!AuthRecoveryState.pending.value) {
      _show(
        'Ouvrez d’abord le lien de récupération reçu par email sur ce téléphone.',
      );
      return;
    }

    final password = _password.text;
    if (password.length < 8) {
      _show('Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (password != _confirmPassword.text) {
      _show('Les deux mots de passe ne correspondent pas.');
      return;
    }

    if (client.auth.currentSession == null) {
      _show(
        'Le lien de récupération a expiré. Demandez un nouvel email.',
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await client.auth.updateUser(
        UserAttributes(password: password),
      );

      AuthRecoveryState.clear();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre mot de passe a été modifié.'),
        ),
      );
      context.go('/');
    } catch (_) {
      _show(
        'Impossible de modifier le mot de passe. Le lien a peut-être expiré ; '
        'demandez-en un nouveau.',
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
      appBar: AppBar(title: const Text('Créer un nouveau mot de passe')),
      body: ValueListenableBuilder<bool>(
        valueListenable: AuthRecoveryState.pending,
        builder: (context, recoveryPending, _) {
          if (!recoveryPending) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.lock_reset_outlined, size: 52),
                const SizedBox(height: 16),
                const Text(
                  'Cette page est réservée aux liens de récupération valides. '
                  'Ouvrez le lien envoyé par email sur ce téléphone. '
                  'Si le lien a expiré, demandez-en un nouveau.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/auth/forgot-password'),
                  child: const Text('Demander un nouveau lien'),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.password_outlined, size: 52),
              const SizedBox(height: 16),
              const Text(
                'Choisissez un mot de passe d’au moins 8 caractères. '
                'Vous devrez le saisir deux fois pour confirmer.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                enabled: !_loading,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: _obscureConfirmation,
                enabled: !_loading,
                decoration: InputDecoration(
                  labelText: 'Confirmer le nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirmation
                        ? 'Afficher la confirmation'
                        : 'Masquer la confirmation',
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _loading ? null : _saveNewPassword,
                child: Text(
                  _loading ? 'Enregistrement…' : 'Enregistrer le mot de passe',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
