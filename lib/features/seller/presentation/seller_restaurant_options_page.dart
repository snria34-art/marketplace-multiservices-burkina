import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';

class SellerRestaurantOptionsPage extends ConsumerStatefulWidget {
  const SellerRestaurantOptionsPage({
    super.key,
    required this.productId,
  });

  final String productId;

  @override
  ConsumerState<SellerRestaurantOptionsPage> createState() =>
      _SellerRestaurantOptionsPageState();
}

class _SellerRestaurantOptionsPageState
    extends ConsumerState<SellerRestaurantOptionsPage> {
  late Future<List<Map<String, dynamic>>> _groupsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return const [];
    final rows = await client
        .from('product_option_groups')
        .select(
          'id,name,selection_mode,min_select,max_select,required,active,sort_order,product_options(id,label,option_kind,active,sort_order,product_option_levels(id,label,price_delta,quantity_value,is_default,active,sort_order))',
        )
        .eq('product_id', widget.productId)
        .order('sort_order');
    return (rows as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _groupsFuture = _load());
    await _groupsFuture;
  }

  Future<Map<String, dynamic>?> _askGroup() async {
    final name = TextEditingController();
    final min = TextEditingController(text: '0');
    final max = TextEditingController(text: '20');
    var selectionMode = 'MULTIPLE';
    var required = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un groupe d’options'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nom du groupe',
                    hintText: 'Ex. Ingrédients, sauces, accompagnements…',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectionMode,
                  decoration: const InputDecoration(
                    labelText: 'Type de sélection',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'MULTIPLE',
                      child: Text('Plusieurs choix'),
                    ),
                    DropdownMenuItem(
                      value: 'SINGLE',
                      child: Text('Un seul choix'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectionMode = value);
                    }
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: min,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minimum',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: max,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Maximum',
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Choix obligatoire'),
                  value: required,
                  onChanged: (value) {
                    setDialogState(() {
                      required = value;
                      if (value && (int.tryParse(min.text) ?? 0) < 1) {
                        min.text = '1';
                      }
                    });
                  },
                ),
                const Text(
                  'Créez librement les groupes qui correspondent à ce plat. Vous n’êtes pas limité à une liste d’ingrédients prédéfinie.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final groupName = name.text.trim();
                final minValue = int.tryParse(min.text.trim());
                final maxValue = int.tryParse(max.text.trim());
                if (groupName.isEmpty ||
                    minValue == null ||
                    maxValue == null ||
                    minValue < 0 ||
                    maxValue < 1 ||
                    minValue > maxValue) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  {
                    'name': groupName,
                    'selection_mode': selectionMode,
                    'min_select': minValue,
                    'max_select': maxValue,
                    'required': required,
                  },
                );
              },
              child: const Text('Créer le groupe'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    min.dispose();
    max.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _askOption() async {
    final label = TextEditingController();
    var kind = 'ADD';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un ingrédient ou un choix'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: 'Ex. Piment, steak, sauce soja…',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'ADD',
                    child: Text('Ajouter un ingrédient'),
                  ),
                  DropdownMenuItem(
                    value: 'REMOVE',
                    child: Text('Retirer un ingrédient inclus'),
                  ),
                  DropdownMenuItem(
                    value: 'CHOICE',
                    child: Text('Choix / remplacement'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => kind = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (label.text.trim().isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  {'label': label.text.trim(), 'option_kind': kind},
                );
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _askLevel({
    Map<String, dynamic>? existing,
  }) async {
    final label = TextEditingController(
      text: existing?['label']?.toString() ?? '',
    );
    final price = TextEditingController(
      text: existing?['price_delta']?.toString() ?? '0',
    );
    final quantity = TextEditingController(
      text: existing?['quantity_value']?.toString() ?? '1',
    );
    var isDefault = existing?['is_default'] == true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null
              ? 'Ajouter un niveau et son supplément'
              : 'Modifier le niveau et son supplément'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Libellé du niveau',
                    hintText: 'Ex. Normal, beaucoup, 2 steaks…',
                  ),
                ),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Supplément de prix',
                    suffixText: 'XOF',
                  ),
                ),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantité correspondante',
                    hintText: '1, 2, 3…',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Niveau par défaut'),
                  value: isDefault,
                  onChanged: (value) {
                    setDialogState(() => isDefault = value);
                  },
                ),
                const Text(
                  'Exemple : le restaurateur peut régler « Beaucoup de piment » à +25 XOF. Le client voit uniquement le choix et le supplément calculé.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final levelLabel = label.text.trim();
                final parsedPrice = num.tryParse(price.text.trim());
                final parsedQuantity = num.tryParse(quantity.text.trim());
                if (levelLabel.isEmpty ||
                    parsedPrice == null ||
                    parsedPrice < 0 ||
                    parsedQuantity == null ||
                    parsedQuantity < 0) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  {
                    'label': levelLabel,
                    'price_delta': parsedPrice,
                    'quantity_value': parsedQuantity,
                    'is_default': isDefault,
                  },
                );
              },
              child: const Text('Enregistrer le niveau'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    price.dispose();
    quantity.dispose();
    return result;
  }

  Future<void> _saveGroup() async {
    final result = await _askGroup();
    if (!mounted || result == null) return;
    await _runSave(
      'save_product_option_group',
      {
        'p_product_id': widget.productId,
        'p_group_id': null,
        'p_name': result['name'],
        'p_selection_mode': result['selection_mode'],
        'p_min_select': result['min_select'],
        'p_max_select': result['max_select'],
        'p_required': result['required'],
        'p_sort_order': 0,
      },
      'Groupe d’options créé.',
    );
  }

  Future<void> _saveOption(String groupId) async {
    final result = await _askOption();
    if (!mounted || result == null) return;
    await _runSave(
      'save_product_option',
      {
        'p_group_id': groupId,
        'p_option_id': null,
        'p_label': result['label'],
        'p_option_kind': result['option_kind'],
        'p_sort_order': 0,
      },
      'Ingrédient ou choix ajouté.',
    );
  }

  Future<void> _saveLevel(
    String optionId, {
    Map<String, dynamic>? existing,
  }) async {
    final result = await _askLevel(existing: existing);
    if (!mounted || result == null) return;
    await _runSave(
      'save_product_option_level',
      {
        'p_option_id': optionId,
        'p_level_id': existing?['id'],
        'p_label': result['label'],
        'p_price_delta': result['price_delta'],
        'p_quantity_value': result['quantity_value'],
        'p_is_default': result['is_default'],
        'p_sort_order': 0,
      },
      existing == null
          ? 'Niveau et supplément enregistrés.'
          : 'Niveau et supplément modifiés.',
    );
  }

  Future<void> _runSave(
    String rpc,
    Map<String, dynamic> params,
    String successMessage,
  ) async {
    final client = ref.read(supabaseProvider);
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      await client.rpc(rpc, params: params);
      if (!mounted) return;
      setState(() => _groupsFuture = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
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

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingrédients et suppléments'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _saveGroup,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un groupe'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Impossible de charger les options du produit.'),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          final groups = snapshot.data ?? const [];
          if (groups.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
              children: const [
                Icon(Icons.tune_outlined, size: 48),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'Aucun groupe d’options pour ce produit.',
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 6),
                Center(
                  child: Text(
                    'Ajoutez librement vos groupes, ingrédients, sauces ou accompagnements, puis définissez le supplément de chaque niveau.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final group = groups[index];
              final options = _maps(group['product_options']);
              return Card(
                child: ExpansionTile(
                  title: Text(
                    group['name']?.toString() ?? 'Groupe',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    (group['selection_mode'] == 'SINGLE'
                            ? 'Un seul choix'
                            : 'Plusieurs choix') +
                        ' • minimum ' +
                        (group['min_select']?.toString() ?? '0') +
                        ' • maximum ' +
                        (group['max_select']?.toString() ?? '100'),
                  ),
                  children: [
                    for (final option in options)
                      _OptionEditor(
                        option: option,
                        levels: _maps(option['product_option_levels']),
                        onAddLevel: () => _saveLevel(option['id'].toString()),
                        onEditLevel: (level) => _saveLevel(
                          option['id'].toString(),
                          existing: level,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _saveOption(group['id'].toString()),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter un ingrédient ou choix'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.option,
    required this.levels,
    required this.onAddLevel,
    required this.onEditLevel,
  });

  final Map<String, dynamic> option;
  final List<Map<String, dynamic>> levels;
  final VoidCallback onAddLevel;
  final ValueChanged<Map<String, dynamic>> onEditLevel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option['label']?.toString() ?? 'Option',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: onAddLevel,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Niveau'),
              ),
            ],
          ),
          for (final level in levels)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(level['label']?.toString() ?? 'Niveau'),
              subtitle: Text(
                'Quantité : ' +
                    (level['quantity_value']?.toString() ?? '1') +
                    (level['is_default'] == true ? ' • Par défaut' : ''),
              ),
              trailing: Wrap(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '+ ' + (level['price_delta']?.toString() ?? '0') + ' XOF',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: 'Modifier le niveau',
                    onPressed: () => onEditLevel(level),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
            ),
          if (levels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Ajoutez au moins un niveau tarifé.'),
            ),
          const Divider(),
        ],
      ),
    );
  }
}
