import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  double? _scalePreview;

  Future<void> _update(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le réglage est appliqué, mais son enregistrement local a échoué.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final scale = _scalePreview ?? settings.textScale;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de l’application')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Affichage', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thème',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AppThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('Auto'),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Clair'),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Sombre'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) =>
                        _update(() => controller.setThemeMode(selection.first)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Couleur principale',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in appThemeColors)
                        Tooltip(
                          message: 'Choisir cette couleur',
                          child: ChoiceChip(
                            selected: settings.seedColorValue == color,
                            avatar: CircleAvatar(
                              backgroundColor: Color(color),
                              radius: 11,
                            ),
                            label: Text(
                              settings.seedColorValue == color
                                  ? 'Sélectionnée'
                                  : 'Choisir',
                            ),
                            onSelected: (_) =>
                                _update(() => controller.setSeedColor(color)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Taille du texte',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Aperçu : ${scale.toStringAsFixed(1)} ×'),
                  Slider(
                    min: 0.9,
                    max: 1.4,
                    divisions: 5,
                    value: scale.clamp(0.9, 1.4),
                    label: '${scale.toStringAsFixed(1)} ×',
                    onChanged: (value) {
                      setState(() => _scalePreview = value);
                    },
                    onChangeEnd: (value) async {
                      await _update(() => controller.setTextScale(value));
                      if (mounted) {
                        setState(() => _scalePreview = null);
                      }
                    },
                  ),
                  const Text(
                    'Le réglage s’ajoute à la taille de texte définie sur le téléphone.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Accessibilité', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.contrast_outlined),
              title: const Text('Contraste renforcé'),
              subtitle: const Text(
                'Renforce le contraste des couleurs de l’interface.',
              ),
              value: settings.highContrast,
              onChanged: (value) =>
                  _update(() => controller.setHighContrast(value)),
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.animation_outlined),
              title: const Text('Réduire les animations'),
              subtitle: const Text(
                'Réduit les animations prises en charge par l’interface.',
              ),
              value: settings.reduceAnimations,
              onChanged: (value) =>
                  _update(() => controller.setReduceAnimations(value)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Langue et région',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.translate_outlined),
                  title: Text('Langue'),
                  subtitle: Text('Français — choix de langues à compléter'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.currency_exchange_outlined),
                  title: Text('Devise'),
                  subtitle: Text('Franc CFA BCEAO (XOF)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              await _update(controller.reset);
              if (mounted) setState(() => _scalePreview = null);
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Réinitialiser les paramètres d’affichage'),
          ),
          const SizedBox(height: 12),
          Text(
            'Ces préférences sont enregistrées localement sur cet appareil. '
            'Elles ne modifient ni les paramètres de la boutique, ni les '
            'préférences de notifications du compte.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
