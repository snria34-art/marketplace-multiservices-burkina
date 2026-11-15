import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FutureCapabilitiesSliver extends StatelessWidget {
  const FutureCapabilitiesSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nouveaux services en préparation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: width,
                      child: _FutureCapabilityCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'WhatsApp Business',
                        subtitle: 'Assistant conversationnel à venir',
                        onTap: () => context.push('/whatsapp'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _FutureCapabilityCard(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Portefeuille client',
                        subtitle: 'Dépôts et paiements à venir',
                        onTap: () => context.push('/wallet'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FutureCapabilityCard extends StatelessWidget {
  const _FutureCapabilityCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
