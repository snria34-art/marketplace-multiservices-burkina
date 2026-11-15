import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WhatsAppAssistantPage extends StatelessWidget {
  const WhatsAppAssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Business')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Canal préparé, non connecté',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cette page réserve l’espace de l’intégration WhatsApp Business '
                    'et de l’assistant conversationnel. Aucun compte WhatsApp, '
                    'numéro professionnel, webhook ou message externe n’est '
                    'actuellement connecté par cette page.',
                  ),
                  const SizedBox(height: 12),
                  const Chip(
                    avatar: Icon(Icons.pause_circle_outline),
                    label: Text('Intégration à venir'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Fonctions prévues',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _PlannedCapability(
            icon: Icons.storefront_outlined,
            title: 'WhatsApp Business officiel',
            description:
                'Relier un numéro professionnel via la plateforme officielle '
                'et garder les identifiants uniquement côté serveur.',
          ),
          const _PlannedCapability(
            icon: Icons.smart_toy_outlined,
            title: 'Assistant conversationnel',
            description:
                'Rechercher des produits, suivre une commande et orienter '
                'une demande vers le bon service, avec transfert vers un agent.',
          ),
          const _PlannedCapability(
            icon: Icons.verified_user_outlined,
            title: 'Consentement et sécurité',
            description:
                'Gérer les opt-in, les modèles de messages, la signature des '
                'webhooks, l’anti-rejeu et la protection des données personnelles.',
          ),
          const _PlannedCapability(
            icon: Icons.sync_alt_outlined,
            title: 'Synchronisation des commandes',
            description:
                'Relier les conversations aux commandes sans exposer les '
                'secrets de paiement ou les données d’autres clients.',
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => context.push('/messages'),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Utiliser la messagerie intégrée actuelle'),
          ),
          const SizedBox(height: 8),
          Text(
            'L’activation future nécessitera un compte WhatsApp Business '
            'autorisé, un numéro vérifié, des secrets stockés côté serveur '
            'et des tests de webhook. Aucun de ces prérequis n’est simulé ici.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlannedCapability extends StatelessWidget {
  const _PlannedCapability({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
      ),
    );
  }
}
