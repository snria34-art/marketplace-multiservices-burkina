import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CustomerWalletPage extends StatelessWidget {
  const CustomerWalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portefeuille client')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Portefeuille client non activé',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aucun solde client n’est actuellement disponible dans '
                    'l’application. Cette page ne crée pas d’argent, ne reçoit '
                    'pas de dépôt et ne déclenche aucun retrait ou transfert.',
                  ),
                  const SizedBox(height: 12),
                  const Chip(
                    avatar: Icon(Icons.lock_outline),
                    label: Text('Opérations financières désactivées'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Espace réservé aux futures fonctions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _WalletPlannedItem(
            icon: Icons.add_card_outlined,
            title: 'Alimenter le portefeuille',
            description:
                'Dépôt via un prestataire de paiement, avec confirmation '
                'serveur et référence unique.',
          ),
          const _WalletPlannedItem(
            icon: Icons.shopping_bag_outlined,
            title: 'Payer une commande',
            description:
                'Utiliser un solde disponible uniquement après validation '
                'du portefeuille et du paiement.',
          ),
          const _WalletPlannedItem(
            icon: Icons.receipt_long_outlined,
            title: 'Historique et justificatifs',
            description:
                'Afficher les mouvements confirmés, les statuts et les '
                'références de transaction.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Important : le solde vendeur visible dans « Finance vendeur » '
            'est calculé à partir du ledger vendeur. Il est distinct d’un '
            'portefeuille prépayé appartenant au client. Aucun montant vendeur '
            'n’est présenté comme un solde client.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/orders'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Consulter mes commandes'),
          ),
        ],
      ),
    );
  }
}

class _WalletPlannedItem extends StatelessWidget {
  const _WalletPlannedItem({
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
        trailing: const Icon(Icons.lock_outline),
      ),
    );
  }
}
