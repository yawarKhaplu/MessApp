import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/member_picker_sheet.dart';
import 'widgets/pick_date.dart';
import 'widgets/text_input_dialog.dart';

/// Edit an existing expense entry (view items, fix prices, add/remove items).
class EditExpenseScreen extends ConsumerStatefulWidget {
  final Expense expense;
  final String menuName;
  final DateTime date;

  const EditExpenseScreen({
    super.key,
    required this.expense,
    required this.menuName,
    required this.date,
  });

  @override
  ConsumerState<EditExpenseScreen> createState() =>
      _EditExpenseScreenState();
}

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  late DateTime _date = widget.date;
  Member? _member;
  List<ExpenseItem> _items = [];
  final Map<int, TextEditingController> _priceControllers = {};
  final Map<int, TextEditingController> _qtyControllers = {};

  /// Bumped whenever any price/qty field changes, so the total card and the
  /// per-item line totals rebuild live while typing.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _notifyTotal() {
    if (mounted) _tick.value++;
  }

  void _bind(ExpenseItem item) {
    _priceControllers[item.id]?.addListener(_notifyTotal);
    _qtyControllers[item.id]?.addListener(_notifyTotal);
  }

  void _unbind(ExpenseItem item) {
    _priceControllers[item.id]?.removeListener(_notifyTotal);
    _qtyControllers[item.id]?.removeListener(_notifyTotal);
  }

  Future<void> _load() async {
    final items = await ref
        .read(repositoryProvider)
        .getExpenseItems(widget.expense.id!);
    // Resolve the currently assigned member. Falls back to reading it from the
    // entry itself, so the editor always shows the real cook.
    Member? member = await ref
        .read(repositoryProvider)
        .getExpenseMember(widget.expense.id!);
    if (!mounted) return;
    setState(() {
      _member = member;
      _items = items;
      for (final item in items) {
        _priceControllers[item.id!] =
            TextEditingController(text: _fmt(item.price));
        _qtyControllers[item.id!] =
            TextEditingController(text: _fmtQty(item.quantity));
        _bind(item);
      }
      _loading = false;
    });
  }

  /// Change who cooked / paid for this entry.
  Future<void> _pickMember() async {
    final repo = ref.read(repositoryProvider);
    final rotation = await repo.getCookRotation();
    final members = rotation.hasMembers
        ? rotation.members
        : await ref.read(membersProvider.future);
    if (!mounted) return;
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add members first in the Collection tab')),
      );
      return;
    }

    final result = await showMemberPickerSheet(
      context,
      members: members,
      current: _member,
      turnIndex:
          rotation.hasMembers ? rotation.positionInRound - 1 : null,
      subtitle: 'Change who cooked for this entry',
    );
    // null means the sheet was dismissed — keep whatever was set.
    if (result == null || !mounted) return;
    setState(() {
      _member =
          identical(result, kUnassignedMember) ? null : result as Member;
    });
  }

  /// Clear the assignment without opening the picker.
  void _clearMember() {
    setState(() => _member = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bari set to unassigned')),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  String _fmtQty(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  void _clearControllers() {
    for (final c in _priceControllers.values) {
      c.removeListener(_notifyTotal);
      c.dispose();
    }
    for (final c in _qtyControllers.values) {
      c.removeListener(_notifyTotal);
      c.dispose();
    }
    _priceControllers.clear();
    _qtyControllers.clear();
  }

  Future<void> _pickDate() async {
    final picked = await pickClampedDate(
      context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  double get _total => _items.fold(0, (s, i) {
        final pc = _priceControllers[i.id];
        final qc = _qtyControllers[i.id];
        if (pc == null || qc == null) return s;
        return s + _parse(pc) * _parse(qc);
      });

  Future<void> _addItem() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const TextInputDialog(
        title: 'Add item',
        hint: 'Item name',
        confirmLabel: 'Add',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final newItem = ExpenseItem(
      id: -DateTime.now().millisecondsSinceEpoch,
      expenseId: widget.expense.id!,
      itemName: name.trim(),
      quantity: 1,
      price: 0,
    );
    setState(() {
      _items.add(newItem);
      _priceControllers[newItem.id!] = TextEditingController();
      _qtyControllers[newItem.id!] = TextEditingController(text: '1');
      _bind(newItem);
    });
  }

  void _removeItem(ExpenseItem item) {
    setState(() {
      _items.removeWhere((i) => i.id == item.id);
      _unbind(item);
      _priceControllers.remove(item.id)?.dispose();
      _qtyControllers.remove(item.id)?.dispose();
    });
    _notifyTotal();
  }

  Future<void> _save() async {
    final entries = <ExpenseItem>[];
    for (final item in _items) {
      final pc = _priceControllers[item.id];
      final qc = _qtyControllers[item.id];
      if (pc == null || qc == null) continue;
      entries.add(ExpenseItem(
        expenseId: widget.expense.id!,
        itemName: item.itemName,
        quantity: _parse(qc),
        price: _parse(pc),
      ));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }

    final repo = ref.read(repositoryProvider);
    await repo.updateExpense(
      id: widget.expense.id!,
      items: entries,
      memberId: _member?.id,
    );
    // Also allow moving the entry to a different date.
    if (!DateUtils.isSameDay(_date, widget.date)) {
      await repo.updateExpenseDate(widget.expense.id!, _date);
    }
    await refreshTotals(ref);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense updated')));
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This will remove the expense and its items.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteExpense(widget.expense.id!);
    await refreshTotals(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Entry deleted')));
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _clearControllers();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit entry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete entry',
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Menu + date
                AppCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.restaurant_menu,
                              color: AppTheme.primary, size: 22),
                        ),
                        title: Text(widget.menuName,
                            style: Theme.of(context).textTheme.titleMedium),
                        subtitle: const Text('Menu'),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_outline,
                              color: AppTheme.accent, size: 22),
                        ),
                        title: Text(_member?.name ?? 'Who is cooking / paying?',
                            style: Theme.of(context).textTheme.titleMedium),
                        subtitle: Text(_member == null
                            ? 'Optional · tap to assign'
                            : 'Tap to change'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_member != null)
                              IconButton(
                                icon: const Icon(Icons.person_off_outlined,
                                    size: 20, color: AppTheme.textSecondary),
                                tooltip: 'Set to unassigned',
                                onPressed: _clearMember,
                              ),
                            const Icon(Icons.expand_more, size: 20),
                          ],
                        ),
                        onTap: _pickMember,
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.calendar_today_outlined,
                              color: AppTheme.secondary, size: 22),
                        ),
                        title: Text(DateFormat.yMMMEd().format(_date),
                            style: Theme.of(context).textTheme.titleMedium),
                        subtitle: const Text('Tap to change date'),
                        onTap: _pickDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SectionHeader(
                  title: 'Items',
                  icon: Icons.list_alt,
                  action: TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.playlist_add,
                            size: 44, color: AppTheme.textSecondary),
                        const SizedBox(height: 10),
                        Text('No items left in this entry',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Add at least one item before saving.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ItemEditorRow(
                        item: item,
                        priceCtrl: _priceControllers[item.id]!,
                        qtyCtrl: _qtyControllers[item.id]!,
                        tick: _tick,
                        onRemove: () => _removeItem(item),
                      ),
                    ),

                const SizedBox(height: 4),
                if (_items.isNotEmpty) ...[
                  AddItemButton(
                    onPressed: _addItem,
                    hint: 'Added to this entry when you save',
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 8),

                // Info card so users know what Save will do.
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Changes apply to this entry only. Moving it to '
                          'another date updates daily totals and reports.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _BottomTotalBar(
        tick: _tick,
        total: _total,
        money: money,
        itemCount: _items.length,
        onSave: _save,
      ),
    );
  }
}

/// One editable item row: name, live line total, qty, price, remove.
class _ItemEditorRow extends StatelessWidget {
  final ExpenseItem item;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  final ValueNotifier<int> tick;
  final VoidCallback onRemove;

  const _ItemEditorRow({
    required this.item,
    required this.priceCtrl,
    required this.qtyCtrl,
    required this.tick,
    required this.onRemove,
  });

  double get _qty => double.tryParse(qtyCtrl.text) ?? 0;
  double get _price =>
      double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: ValueListenableBuilder<int>(
              valueListenable: tick,
              builder: (context, _, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_qty.toStringAsFixed(_qty % 1 == 0 ? 0 : 1)} × ${money.format(_price)} = ${money.format(_qty * _price)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary.withOpacity(0.95),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: TextField(
              controller: qtyCtrl,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Qty',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Remove item',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom bar: live total + Save button (never overlaps content).
class _BottomTotalBar extends StatelessWidget {
  final ValueNotifier<int> tick;
  final double total;
  final NumberFormat money;
  final int itemCount;
  final VoidCallback onSave;

  const _BottomTotalBar({
    required this.tick,
    required this.total,
    required this.money,
    required this.itemCount,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, _, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total ($itemCount ${itemCount == 1 ? 'item' : 'items'})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withOpacity(0.95),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money.format(total),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            GradientButton(
              label: 'Save changes',
              icon: Icons.check,
              expanded: false,
              onPressed: onSave,
            ),
          ],
        ),
      ),
    );
  }
}
