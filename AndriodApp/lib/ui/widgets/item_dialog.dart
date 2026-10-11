import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// An item the user has used elsewhere, offered as a one-tap shortcut.
class ItemSuggestion {
  /// The item name.
  final String name;

  /// Where it came from, e.g. "Pulao, Karahi" or "used before".
  final String where;

  /// The last price seen, used to prefill the price field.
  final double lastPrice;

  const ItemSuggestion(this.name, this.where, this.lastPrice);
}

/// Add / edit an item with one-tap suggestions drawn from the other menus
/// and from items already used in past expenses.
class ItemDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initialName;
  final double initialPrice;

  /// Suggestions shown under the fields; filtered as the user types.
  final List<ItemSuggestion> suggestions;

  /// Names already present, so they are not offered again.
  final Set<String> existingNames;

  /// Label above the suggestion list.
  final String suggestionsLabel;

  const ItemDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.suggestions,
    required this.existingNames,
    this.initialName = '',
    this.initialPrice = 0,
    this.suggestionsLabel = 'Used in other menus',
  });

  @override
  State<ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _price = TextEditingController(
      text: widget.initialPrice > 0
          ? widget.initialPrice.toStringAsFixed(0)
          : '');
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  List<ItemSuggestion> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.suggestions.where((s) {
      if (widget.existingNames.contains(s.name.toLowerCase())) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q);
    }).toList();
  }

  void _use(ItemSuggestion s) {
    _name.text = s.name;
    _query = s.name;
    if (s.lastPrice > 0) _price.text = s.lastPrice.toStringAsFixed(0);
    setState(() => _error = null);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter an item name');
      return;
    }
    Navigator.pop(
      context,
      (
        name: name,
        price: double.tryParse(_price.text.replaceAll(',', '')) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final list = _filtered;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => setState(() {
                _query = v;
                _error = null;
              }),
              decoration: InputDecoration(
                labelText: 'Item name',
                isDense: true,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Usual price (0 if it changes)',
                isDense: true,
              ),
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 15, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    widget.suggestionsLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent.withOpacity(0.95),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _use(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppTheme.secondary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add_circle_outline,
                                size: 17, color: AppTheme.secondary),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                  if (s.where.isNotEmpty)
                                    Text(
                                      s.where,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary
                                            .withOpacity(0.95),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (s.lastPrice > 0)
                              Text(
                                money.format(s.lastPrice),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.secondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}