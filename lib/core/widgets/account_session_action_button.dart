import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/push_notification_service.dart';
import '../providers/repository_providers.dart';

/// Provides one consistent account action on the main role dashboards.
///
/// Logout always runs the push-device deactivation workflow before Supabase
/// clears the session. A failed server deactivation leaves the session open
/// so the user can retry rather than silently retaining an active token.
class AccountSessionActionButton extends ConsumerStatefulWidget {
  const AccountSessionActionButton({super.key});

  @override
  ConsumerState<AccountSessionActionButton> createState() =>
      _AccountSessionActionButtonState();
}

class _AccountSessionActionButtonState
    extends ConsumerState<AccountSessionActionButton> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref
        .read(marketplaceEngineProvider).backendClient
        ?.auth
        .onAuthStateChange
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    final client = ref.read(marketplaceAuthenticationClientProvider);

    if (client == null) {
      _showMessage('Le service de connexion est indisponible.');
      return;
    }

    if (client.auth.currentUser == null) {
      context.push('/auth');
      return;
    }

    setState(() => _busy = true);
    try {
      await PushNotificationService.instance
          .signOutAndDeactivateCurrentDevice(
            engine: ref.read(marketplaceEngineProvider),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous êtes déconnecté.')),
      );
      context.go('/');
    } catch (_) {
      _showMessage(
        'Déconnexion non effectuée : impossible de confirmer la désactivation '
        'de cet appareil. Vérifiez votre connexion et réessayez.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(marketplaceAuthenticationClientProvider);
    final isSignedIn = client?.auth.currentUser != null;

    return IconButton(
      tooltip: _busy
          ? 'Déconnexion en cours'
          : (isSignedIn ? 'Se déconnecter' : 'Se connecter'),
      onPressed: _busy ? null : _handlePressed,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isSignedIn
                  ? Icons.logout
                  : Icons.account_circle_outlined,
            ),
    );
  }
}
