import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/expense_cloud_service.dart';
import '../services/mess_cloud_service.dart';
import '../services/other_expense_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'other_categories_screen.dart';
import 'widgets/pick_date.dart';
import 'widgets/text_input_dialog.dart';

/// Other (non-menu) expenses (PRD 5.7): gas, electricity, rent, custom.
///
/// Pass [editing] to correct an existing record instead of adding a new one —
/// the same form is used, so amount, category and date can all be fixed.
class OtherExpenseScreen extends ConsumerStatefulWidget {
  final CloudOtherExpense? editing;

  const OtherExpenseScreen({super.key, this.editing});

  @override
  ConsumerState<OtherExpenseScreen> createState() =>
      _OtherExpenseScreenState();
}

class _OtherExpenseScreenState extends ConsumerState<OtherExpenseScreen> {
  late DateTime _date;
  String? _category;
  late final TextEditingController _amountCtrl;
  List<String> _categories = [];
  List<CloudOtherExpense> _recent = [];
  CloudCategoryBudget? _selectedBudget;
  late bool _editing;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _editing = e != null;
    // Stored as a yyyy-MM-dd string, so read the parsed day rather than the
    // raw field: _date is a DateTime for the date picker.
    _date = e?.day ?? DateTime.now();
    _category = e?.category;
    _amountCtrl = TextEditingController(
        text: e != null && e.amount > 0 ? e.amount.toStringAsFixed(0) : '');
    _load();
  }

  Future<void> _load() async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    final service = ref.read(messCloudServiceProvider);
    final month = ref.read(selectedMonthProvider);
    final key = monthKey(month);
    final bounds = monthBounds(key);

    final cats = [
      for (final c in await service.otherCategories(mess.id)) c.name,
    ];
    final recent = await service.otherExpenses(mess.id, key);
    final budgets = await service.otherCategories(mess.id);

    if (mounted) {
      setState(() {
        _categories = cats;
        // Keep whatever was being edited even if it is a custom category.
        if (_editing && _category != null) {
          if (!cats.contains(_category)) cats.insert(0, _category!);
        } else if (_category != null && !cats.contains(_category)) {
          // Only drop a selection that no longer exists; otherwise leave the
          // user's choice alone. Nothing is pre-selected by default.
          _category = null;
        }
        _selectedBudget = null;
        for (final c in budgets) {
          if (c.name == _category) {
            _selectedBudget = CloudCategoryBudget(
              c,
              spentInCategory(recent, c.name, bounds.from, bounds.to),
            );
          }
        }
        _recent = recent.where((e) => e.id != widget.editing?.id).take(20).toList();
      });
    }
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

  /// Category chooser as a bottom sheet, with usage and budget progress.
  Future<void> _pickCategory() async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    final service = ref.read(messCloudServiceProvider);
    final key = monthKey(ref.read(selectedMonthProvider));
    final bounds = monthBounds(key);

    // Usage counted against the selected month, matching the allowance shown
    // next to it. Counting every month beside a monthly allowance would read as
    // overspend for anything ever filed under the category.
    final inMonth = await service.otherExpenses(mess.id, key);
    final budgets = await service.otherCategories(mess.id);

    CloudCategoryBudget? budgetFor(String name) {
      for (final c in budgets) {
        if (c.name != name) continue;
        return CloudCategoryBudget(
          c,
          spentInCategory(inMonth, c.name, bounds.from, bounds.to),
        );
      }
      return null;
    }

    final usage = <String, int>{};
    for (final c in _categories) {
      usage[c] = inMonth.where((e) => e.category == c).length;
    }
    if (!mounted) return;

    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondary, Color(0xFF00695C)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.category_outlined,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose a category',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Gas, rent, chai patti…',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final c in _categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CategoryChoiceTile(
                  name: c,
                  records: usage[c] ?? 0,
                  budget: budgetFor(c),
                  selected: c == _category,
                  money: money,
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, '__new__'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New category'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openCategoryManager();
              },
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Manage categories and budgets'),
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    if (picked == '__new__') {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => const TextInputDialog(
          title: 'New category',
          hint: 'Category name',
          confirmLabel: 'Save',
        ),
      );
      if (name != null && name.trim().isNotEmpty) {
        final mess = ref.read(activeMessProvider).valueOrNull;
        if (mess == null) return;

        try {
          await ref
              .read(messCloudServiceProvider)
              .addOtherCategory(mess.id, name.trim());
        } on CloudMessage catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.text)));
          return;
        }

        await _load();
        if (mounted) setState(() => _category = name.trim());
      }
    } else {
      setState(() => _category = picked);
    }
  }

  /// Describes the state of the selected category, so the card never shows
  /// placeholder text that contradicts what is actually selected.
String _categoryStatus(NumberFormat money) {
    if (_category == null) return 'Tap to choose one';
    final b = _selectedBudget;
    if (b != null && b.hasBudget) {
      if (b.isOver) {
        return '${money.format(b.over)} over budget · tap to change';
      }
      return '${money.format(b.remaining)} left of ${money.format(b.budget)}';
    }
    return 'No budget set · tap to change';
  }

  Future<void> _openCategoryManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OtherCategoriesScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    if (_category == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }

    try {
      // Editing passes the existing id so the same row is overwritten. Saving
      // without it would leave the original in place and add a second entry for
      // the same day, so the total would count it twice.
      await saveOtherExpense(
        ref: ref,
        date: dayKey(_date),
        category: _category!,
        amount: amount,
        id: widget.editing?.id,
      );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    if (_editing && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$_category updated')));
      Navigator.pop(context, true);
      return;
    }

    _amountCtrl.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Saved $_category ${DateFormat.yMMMEd().format(_date)}')),
      );
    }
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${e.category}?'),
        content: Text(
            'Remove ${NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(e.amount)} '
            'recorded on ${DateFormat.yMMMEd().format(e.day)}?'),
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

    try {
      await deleteOtherExpense(
        ref: ref,
        month: monthOf(e.date),
        id: e.id,
      );
    } on CloudMessage catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err.text)));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Expense deleted')));
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit expense' : 'Other expenses'),
        actions: [
          if (_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _delete,
            )
          else
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Manage categories',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OtherCategoriesScreen(),
                ));
                if (context.mounted) await _load();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    child: const Icon(Icons.calendar_today_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  title: Text(DateFormat.yMMMEd().format(_date),
                      style: Theme.of(context).textTheme.titleMedium),
                  subtitle: const Text('Tap to change date'),
                  onTap: _pickDate,
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
                    child: const Icon(Icons.category_outlined,
                        color: AppTheme.secondary, size: 22),
                  ),
                  title: Text(_category ?? 'Select a category',
                      style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(
                    _categoryStatus(money),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.expand_more, size: 20),
                  onTap: _pickCategory,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: '0',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: Icon(_editing ? Icons.check : Icons.save),
                  label:
                      Text(_editing ? 'Update expense' : 'Save expense'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_recent.isNotEmpty) ...[
            const SectionHeader(title: 'Recent', icon: Icons.history),
            const SizedBox(height: 8),
            for (final e in _recent)
              Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.delete, color: AppTheme.error),
                ),
                onDismissed: (_) async {
                  // Swiping the row away removes it for everyone, so a failure
                  // has to be reported rather than leaving the row gone from the
                  // screen while it is still in Firestore.
                  try {
                    await deleteOtherExpense(
                      ref: ref,
                      month: monthOf(e.date),
                      id: e.id,
                    );
                  } on CloudMessage catch (err) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(err.text)));
                  }
                  await _load();
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OtherExpenseScreen(editing: e),
                        ),
                      );
                      if (context.mounted) await _load();
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.receipt_outlined,
                              color: AppTheme.accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.category,
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(DateFormat.yMMMEd().format(e.day),
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Text(
                          money.format(e.amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined,
                            size: 16, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One category row in the chooser: usage, and budget progress if set.
class _CategoryChoiceTile extends StatelessWidget {
  final String name;
  final int records;
  final CloudCategoryBudget? budget;
  final bool selected;
  final NumberFormat money;
  final VoidCallback onTap;

  const _CategoryChoiceTile({
    required this.name,
    required this.records,
    required this.budget,
    required this.selected,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = budget;
    final hasBudget = b != null && b.hasBudget;
    final over = b != null && b.isOver;
    final accent = over ? AppTheme.error : AppTheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.09)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent.withOpacity(0.45) : AppTheme.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(over ? Icons.error_outline : Icons.category_outlined,
                    color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (hasBudget) ...[
                          const SizedBox(width: 8),
                          AppBadge(
                            label: over
                                ? '${money.format(b.over)} over'
                                : '${money.format(b.remaining)} left',
                            color: over ? AppTheme.error : AppTheme.success,
                            icon: hasBudget
                                ? Icons.savings_outlined
                                : null,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      records == 0
                          ? 'No records yet'
                          : '$records ${records == 1 ? 'record' : 'records'} this month',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withOpacity(0.95),
                      ),
                    ),
                    if (hasBudget) ...[
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: b.usedFraction,
                          minHeight: 5,
                          backgroundColor: AppTheme.divider,
                          valueColor: AlwaysStoppedAnimation(
                              over ? AppTheme.error : AppTheme.success),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
