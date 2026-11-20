import 'package:flutter/material.dart';

class RestaurantCustomizationDialog extends StatefulWidget {
  const RestaurantCustomizationDialog({
    super.key,
    required this.productName,
    required this.basePrice,
    required this.groups,
  });

  final String productName;
  final num basePrice;
  final List<Map<String, dynamic>> groups;

  @override
  State<RestaurantCustomizationDialog> createState() =>
      _RestaurantCustomizationDialogState();
}

class _RestaurantCustomizationDialogState
    extends State<RestaurantCustomizationDialog> {
  final Map<String, String> _selectedLevelByOption = {};
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    for (final group in widget.groups) {
      final options = _options(group);
      for (final option in options) {
        final optionId = option['id']?.toString();
        if (optionId == null) continue;
        final defaults = _levels(option)
            .where((level) => level['is_default'] == true)
            .toList();
        if (defaults.length == 1) {
          _selectedLevelByOption[optionId] =
              defaults.first['id'].toString();
        }
      }
    }
  }

  List<Map<String, dynamic>> _options(Map<String, dynamic> group) {
    final raw = group['product_options'];
    if (raw is! List) return const [];
    return raw.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['active'] != false)
        .toList();
  }

  List<Map<String, dynamic>> _levels(Map<String, dynamic> option) {
    final raw = option['product_option_levels'];
    if (raw is! List) return const [];
    return raw.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['active'] != false)
        .toList();
  }

  num _unitPrice() {
    var amount = widget.basePrice;
    for (final group in widget.groups) {
      for (final option in _options(group)) {
        final optionId = option['id']?.toString();
        final selectedId = optionId == null
            ? null
            : _selectedLevelByOption[optionId];
        if (selectedId == null) continue;
        for (final level in _levels(option)) {
          if (level['id']?.toString() == selectedId) {
            amount += num.tryParse(
                  level['price_delta']?.toString() ?? '',
                ) ??
                0;
            break;
          }
        }
      }
    }
    return amount;
  }

  int _selectedCount(Map<String, dynamic> group) {
    return _options(group).where((option) {
      final optionId = option['id']?.toString();
      return optionId != null &&
          (_selectedLevelByOption[optionId]?.isNotEmpty ?? false);
    }).length;
  }

  void _chooseLevel(
    Map<String, dynamic> group,
    Map<String, dynamic> option,
    String? levelId,
  ) {
    final optionId = option['id']?.toString();
    if (optionId == null) return;

    setState(() {
      if (levelId == null || levelId.isEmpty) {
        _selectedLevelByOption.remove(optionId);
        return;
      }

      if (group['selection_mode']?.toString() == 'SINGLE') {
        for (final other in _options(group)) {
          final otherId = other['id']?.toString();
          if (otherId != null && otherId != optionId) {
            _selectedLevelByOption.remove(otherId);
          }
        }
      }
      _selectedLevelByOption[optionId] = levelId;
    });
  }

  void _submit() {
    for (final group in widget.groups) {
      final minimum = int.tryParse(
            group['min_select']?.toString() ?? '',
          ) ??
          0;
      final selected = _selectedCount(group);
      if (selected < minimum) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Choisissez au moins $minimum option(s) dans « ${group['name'] ?? 'Options'} ».',
            ),
          ),
        );
        return;
      }
    }

    Navigator.pop<Map<String, dynamic>>(
      context,
      {
        'quantity': _quantity,
        'selected_level_ids': _selectedLevelByOption.values.toList(),
      },
    );
  }

  String _money(num value) => value.toStringAsFixed(
        value == value.roundToDouble() ? 0 : 2,
      );

  @override
  Widget build(BuildContext context) {
    final unitPrice = _unitPrice();
    final total = unitPrice * _quantity;

    return AlertDialog(
      title: Text(widget.productName),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Personnalisez votre plat',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              for (final group in widget.groups) ...[
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group['name']?.toString() ?? 'Options',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (group['required'] == true)
                      Text(
                        'Obligatoire',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                if ((group['selection_mode']?.toString() ?? '') == 'SINGLE')
                  Text(
                    'Un seul choix',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  Text(
                    'Plusieurs choix possibles',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final option in _options(group))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _OptionLevelPicker(
                      option: option,
                      levels: _levels(option),
                      selectedLevelId:
                          _selectedLevelByOption[option['id']?.toString()],
                      onChanged: (value) => _chooseLevel(group, option, value),
                    ),
                  ),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(child: Text('Quantité')),
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    onPressed: _quantity < 100
                        ? () => setState(() => _quantity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Prix du plat')),
                  Text('${_money(widget.basePrice)} XOF'),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('Suppléments choisis')),
                  Text('+ ${_money(unitPrice - widget.basePrice)} XOF'),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(
                    '${_money(total)} XOF',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Le prix est calculé par le restaurant et vérifié par le serveur. Vous ne pouvez pas le modifier.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_shopping_cart),
          label: Text('Ajouter • ${_money(total)} XOF'),
        ),
      ],
    );
  }
}

class _OptionLevelPicker extends StatelessWidget {
  const _OptionLevelPicker({
    required this.option,
    required this.levels,
    required this.selectedLevelId,
    required this.onChanged,
  });

  final Map<String, dynamic> option;
  final List<Map<String, dynamic>> levels;
  final String? selectedLevelId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option['label']?.toString() ?? 'Ingrédient',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: selectedLevelId,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          hint: const Text('Ne pas modifier'),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Ne pas modifier'),
            ),
            for (final level in levels)
              DropdownMenuItem<String>(
                value: level['id'].toString(),
                child: Text(
                  (level['label']?.toString() ?? 'Choix') +
                      '  (+ ' +
                      (level['price_delta']?.toString() ?? '0') +
                      ' XOF)',
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
