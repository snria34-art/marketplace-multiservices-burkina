import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/widgets/account_session_action_button.dart';

class AdminPlatformSettingsPage extends ConsumerStatefulWidget {
  const AdminPlatformSettingsPage({super.key});

  @override
  ConsumerState<AdminPlatformSettingsPage> createState() =>
      _AdminPlatformSettingsPageState();
}

class _AdminPlatformSettingsPageState
    extends ConsumerState<AdminPlatformSettingsPage> {
  static const _settingKeys = <String>[
    'platform_profile',
    'support_contacts',
    'public_announcement',
  ];

  final _platformName = TextEditingController(
    text: 'Marketplace Multiservices Burkina',
  );
  final _supportPhone = TextEditingController();
  final _supportWhatsapp = TextEditingController();
  final _supportEmail = TextEditingController();
  final _announcementTitle = TextEditingController();
  final _announcementMessage = TextEditingController();

  late Future<void> _loadFuture;
  bool _announcementEnabled = false;
  String _announcementSeverity = 'info';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _platformName.dispose();
    _supportPhone.dispose();
    _supportWhatsapp.dispose();
    _supportEmail.dispose();
    _announcementTitle.dispose();
    _announcementMessage.dispose();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  Future<void> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }

    final rows = await client
        .from('platform_settings')
        .select('key,value')
        .inFilter('key', _settingKeys);

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final value = _asMap(row['value']);

      switch (row['key']) {
        case 'platform_profile':
          _platformName.text = value['name']?.toString() ??
              'Marketplace Multiservices Burkina';
          break;
        case 'support_contacts':
          _supportPhone.text = value['phone']?.toString() ?? '';
          _supportWhatsapp.text = value['whatsapp']?.toString() ?? '';
          _supportEmail.text = value['email']?.toString() ?? '';
          break;
        case 'public_announcement':
          _announcementEnabled = value['enabled'] == true;
          _announcementTitle.text = value['title']?.toString() ?? '';
          _announcementMessage.text = value['message']?.toString() ?? '';
          final severity = value['severity']?.toString() ?? 'info';
          _announcementSeverity =
              const ['info', 'warning', 'success'].contains(severity)
                  ? severity
                  : 'info';
          break;
      }
    }
  }

  Future<void> _save(String key, Map<String, dynamic> value) async {
    final client = ref.read(supabaseProvider);
    if (client == null || _saving) return;

    setState(() => _saving = true);
    try {
      await client.rpc(
        'admin_upsert_marketplace_setting',
        params: {'p_key': key, 'p_value': value},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètre enregistré.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement refusé : $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres de la plateforme'),
        actions: const [AccountSessionActionButton()],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Chargement impossible : ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _section(
                title: 'Identité de la marketplace',
                description:
                    'Paramètres de référence de la plateforme. Le pays et la devise restent fixés au Burkina Faso et au XOF.',
                children: [
                  TextField(
                    controller: _platformName,
                    maxLength: 80,
                    decoration: _input('Nom public de la plateforme'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Burkina Faso'),
                    subtitle: Text('Pays BF • Devise XOF • Langue française'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule_outlined),
                    title: Text('Africa/Ouagadougou'),
                    subtitle: Text('Fuseau horaire de référence'),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save('platform_profile', {
                                'name': _platformName.text.trim(),
                                'country_code': 'BF',
                                'currency': 'XOF',
                                'locale': 'fr',
                                'timezone': 'Africa/Ouagadougou',
                              }),
                      child: const Text('Enregistrer l’identité'),
                    ),
                  ),
                ],
              ),
              _section(
                title: 'Coordonnées du support',
                description:
                    'Ces coordonnées sont destinées à être affichées dans les points de contact publics.',
                children: [
                  TextField(
                    controller: _supportPhone,
                    keyboardType: TextInputType.phone,
                    decoration: _input('Téléphone', hint: '+226 ...'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _supportWhatsapp,
                    keyboardType: TextInputType.phone,
                    decoration: _input('WhatsApp', hint: '+226 ...'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _supportEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _input('Adresse e-mail'),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save('support_contacts', {
                                'phone': _supportPhone.text.trim(),
                                'whatsapp': _supportWhatsapp.text.trim(),
                                'email': _supportEmail.text.trim(),
                              }),
                      child: const Text('Enregistrer les coordonnées'),
                    ),
                  ),
                ],
              ),
              _section(
                title: 'Annonce publique',
                description:
                    'Prépare un message d’information visible via le point d’accès public des paramètres.',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activer l’annonce'),
                    value: _announcementEnabled,
                    onChanged: _saving
                        ? null
                        : (value) =>
                            setState(() => _announcementEnabled = value),
                  ),
                  TextField(
                    controller: _announcementTitle,
                    maxLength: 120,
                    decoration: _input('Titre'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _announcementMessage,
                    maxLength: 600,
                    minLines: 2,
                    maxLines: 5,
                    decoration: _input('Message'),
                  ),
                  DropdownButtonFormField<String>(
                    value: _announcementSeverity,
                    decoration: _input('Type de message'),
                    items: const [
                      DropdownMenuItem(value: 'info', child: Text('Information')),
                      DropdownMenuItem(value: 'warning', child: Text('Alerte')),
                      DropdownMenuItem(value: 'success', child: Text('Bonne nouvelle')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _announcementSeverity = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save('public_announcement', {
                                'enabled': _announcementEnabled,
                                'title': _announcementTitle.text.trim(),
                                'message': _announcementMessage.text.trim(),
                                'severity': _announcementSeverity,
                              }),
                      child: const Text('Enregistrer l’annonce'),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  'Les commissions, les frais et les règles de paiement ne sont pas modifiables depuis cet écran.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
