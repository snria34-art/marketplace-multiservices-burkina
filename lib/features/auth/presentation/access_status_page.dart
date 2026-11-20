import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/notifications/push_notification_service.dart';

class AccessStatusPage extends ConsumerWidget {
  const AccessStatusPage({super.key, this.reason});

  final String? reason;

  String get _message {
    switch (reason) {
      case 'account_inactive':
        return 'Votre compte est suspendu ou bloqué. Contactez l’assistance pour demander une vérification.';
      case 'admin_required':
        return 'Cette page est réservée aux administrateurs actifs.';
      case 'moderator_required':
        return 'Cette page est réservée aux modérateurs autorisés du catalogue et des avis.';
      case 'seller_required':
        return 'Cette page est réservée aux comptes vendeurs autorisés.';
      case 'courier_required':
        return 'Cette page est réservée aux livreurs autorisés.';
      default:
        return 'Nous ne pouvons pas vérifier vos autorisations pour le moment. Réessayez plus tard.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(marketplaceAuthenticationClientProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accès restreint')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 52),
                const SizedBox(height: 18),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    if (client == null) {
                      if (context.mounted) context.go('/auth');
                      return;
                    }
                    try {
                      await PushNotificationService.instance
                          .signOutAndDeactivateCurrentDevice(
                            engine: ref.read(marketplaceEngineProvider),
                          );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Déconnexion non effectuée : la désactivation de cet appareil n’a pas été confirmée.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    if (context.mounted) context.go('/auth');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Retour à l’accueil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
