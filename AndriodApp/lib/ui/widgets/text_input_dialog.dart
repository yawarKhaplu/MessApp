import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// A dialog with a text field that owns its controller and disposes it
/// correctly (avoids "TextEditingController used after being disposed"
/// during the dialog's exit animation).
class TextInputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String initialValue;
  final bool numeric;
  final String confirmLabel;

  /// Small explanation above the field, e.g. what the prefilled value is.
  final String? subtitle;

  /// Tappable amounts that fill the field for one-tap entry.
  final List<double> quickAmounts;

  const TextInputDialog({
    super.key,
    required this.title,
    this.hint = '',
    this.initialValue = '',
    this.numeric = false,
    this.confirmLabel = 'Save',
    this.subtitle,
    this.quickAmounts = const [],
  });

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useQuick(double amount) {
    final text = amount.toStringAsFixed(0);
    _controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.95),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: widget.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              decoration: InputDecoration(hintText: widget.hint),
            ),
            if (widget.quickAmounts.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in widget.quickAmounts)
                    ActionChip(
                      label: Text(money.format(amount)),
                      onPressed: () => _useQuick(amount),
                      backgroundColor: AppTheme.primary.withOpacity(0.08),
                      side: BorderSide(
                          color: AppTheme.primary.withOpacity(0.25)),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppTheme.primary,
                      ),
                    ),
                  ActionChip(
                    label: const Text('Clear'),
                    onPressed: () => _useQuick(0),
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: AppTheme.divider),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}