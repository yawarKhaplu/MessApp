import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/mess_cloud_service.dart';
import '../services/other_expense_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'widgets/text_input_dialog.dart';

/// Add, rename and remove the main categories used by other expenses.
///
/// Renaming updates every past record too, so history always matches the
/// category list instead of being left behind under an old name.
class OtherCategoriesScreen extends ConsumerStatefulWidget {
  const OtherCategoriesScreen({super.key});

  @override
  ConsumerState<OtherCategoriesScreen> createState() =>
      _OtherCategoriesScreenState();
}

class _OtherCategoriesScreenState extends ConsumerState<OtherCategoriesScreen> {
  List<String> _categories = [];
  Map<String, int> _usage = {};
  List<CloudCategoryBudget> _budgets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final service = ref.read(messCloudServiceProvider);
    final key = monthKey(ref.read(selectedMonthProvider));
    final bounds = monthBounds(key);

    final budgets = await service.otherCategories(mess.id);
    // Read every month that holds records, not just the selected one: a category
    // deleted here has to be found again on the records wherever they were filed.
    final months = await service.otherExpenseMonths(mess.id);

    final records = <CloudOtherExpense>[];
    for (final m in months) {
      records.addAll(await service.otherExpenses(mess.id, m));
    }

    // Usage counted against the selected month, matching the allowance shown
    // beside it. Counting across all months next to a monthly allowance would
    // read as overspend for anything ever filed under the category.
    final inMonth = records
        .where((e) => e.date.compareTo(bounds.from) >= 0 &&
            e.date.compareTo(bounds.to) <= 0)
        .toList();

    final usage = <String, int>{};
    for (final c in budgets) {
      usage[c.name] = inMonth.where((e) => e.category == c.name).length;
    }

    if (!mounted) return;
    setState(() {
      _categories = [for (final c in budgets) c.name];
      _usage = usage;
      _budgets = [
        for (final c in budgets)
          CloudCategoryBudget(
            c,
            spentInCategory(inMonth, c.name, bounds.from, bounds.to),
          ),
      ];
      _loading = false;
    });
  }

  CloudCategoryBudget? _budgetFor(String name) {
    for (final b in _budgets) {
      if (b.name == name) return b;
    }
    return null;
  }

  Future<void> _afterChange() async {
    ref.read(dataVersionProvider.notifier).state++;
    await _load();
  }

  /// Sets (or clears) a category's monthly allowance.
  Future<void> _setBudget(String name) async {
    final current = _budgetFor(name)?.budget ?? 0;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: '$name — monthly budget',
        hint: 'e.g. 3000 (0 to remove)',
        numeric: true,
        initialValue: current > 0 ? current.toStringAsFixed(0) : '',
        confirmLabel: 'Save',
      ),
    );
    if (value == null) return;
    final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
    if (amount < 0) return;

    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref
          .read(messCloudServiceProvider)
          .setCategoryBudget(mess.id, name, amount);
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(amount > 0
            ? '$name budget set to ${amount.toStringAsFixed(0)}'
            : '$name budget removed'),
      ),
    );
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: 'New category',
        hint: 'e.g. Water',
        confirmLabel: 'Add',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final clean = name.trim();

    if (_categories.any((c) => c.toLowerCase() == clean.toLowerCase())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$clean" already exists')),
      );
      return;
    }

    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref
          .read(messCloudServiceProvider)
          .addOtherCategory(mess.id, clean);
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('"$clean" added')));
  }

  Future<void> _rename(String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Rename category',
        hint: 'Category name',
        initialValue: current,
        confirmLabel: 'Rename',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final clean = name.trim();
    if (clean == current) return;

    if (_categories.any((c) =>
        c.toLowerCase() == clean.toLowerCase() && c != current)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$clean" already exists')),
      );
      return;
    }

    final count = _usage[current] ?? 0;
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref.read(messCloudServiceProvider).renameOtherCategory(
            messId: mess.id,
            oldName: current,
            newName: clean,
          );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count == 0
            ? 'Renamed to "$clean"'
            : 'Renamed to "$clean" · $count past '
                '${count == 1 ? 'record' : 'records'} updated'),
      ),
    );
  }

  Future<void> _delete(String category) async {
    final count = _usage[category] ?? 0;

    // Offer to keep the money records by re-filing them, since those are real
    // expenses the mess already paid for.
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$category"?'),
        content: Text(count == 0
            ? 'This category is not used by any record.'
            : '$count past ${count == 1 ? 'record' : 'records'} use this '
                'category.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          if (count > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: const Text('Delete, keep records'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text(count > 0 ? 'Delete all' : 'Delete'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    try {
      await ref.read(messCloudServiceProvider).deleteOtherCategory(
            messId: mess.id,
            name: category,
            keepRecords: choice == 'keep',
          );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
      return;
    }

    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(choice == 'keep'
            ? '"$category" removed · records kept under Other'
            : '"$category" deleted'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Other expense categories')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.secondary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Give a category a monthly budget to track '
                            'recurring costs like gas refill, rent or cups. '
                            'Renaming updates past records.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_budgets.any((b) => b.hasBudget))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _BudgetSummary(budgets: _budgets),
                  ),
                Expanded(
                  child: _categories.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No categories yet. Add one with the button below.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _categories.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final name = _categories[i];
                            final count = _usage[name] ?? 0;
                            final b = _budgetFor(name);
                            final money =
                                NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
                            return AppCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          b != null && b.isOver
                                              ? Icons.error_outline
                                              : Icons.category_outlined,
                                          color: b != null && b.isOver
                                              ? AppTheme.error
                                              : AppTheme.primary,
                                          size: 21,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              count == 0
                                                  ? 'Not used yet'
                                                  : '$count ${count == 1 ? 'record' : 'records'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.textSecondary
                                                        .withOpacity(0.95),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.savings_outlined,
                                          size: 20,
                                          color: (b?.hasBudget ?? false)
                                              ? AppTheme.secondary
                                              : AppTheme.textSecondary,
                                        ),
                                        tooltip: 'Monthly budget',
                                        onPressed: () => _setBudget(name),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 20),
                                        tooltip: 'Rename',
                                        onPressed: () => _rename(name),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: AppTheme.error),
                                        tooltip: 'Delete',
                                        onPressed: () => _delete(name),
                                      ),
                                    ],
                                  ),
                                  if (b != null && b.hasBudget) ...[
                                    const SizedBox(height: 10),
                                    _BudgetRow(b: b, money: money),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
    );
  }
}
/// One category's allowance usage for the month.
class _BudgetRow extends StatelessWidget {
  final CloudCategoryBudget b;
  final NumberFormat money;

  const _BudgetRow({required this.b, required this.money});

  @override
  Widget build(BuildContext context) {
    final over = b.isOver;
    final color = over ? AppTheme.error : AppTheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${money.format(b.spent)} of ${money.format(b.budget)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const Spacer(),
            Text(
              over
                  ? '${money.format(b.over)} over'
                  : '${money.format(b.remaining)} left',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: b.usedFraction,
            minHeight: 6,
            backgroundColor: AppTheme.divider,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// Totals across every category that has an allowance.
class _BudgetSummary extends StatelessWidget {
  final List<CloudCategoryBudget> budgets;

  const _BudgetSummary({required this.budgets});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final withBudget = budgets.where((b) => b.hasBudget).toList();
    final total = withBudget.fold<double>(0, (s, b) => s + b.budget);
    final spent = withBudget.fold<double>(0, (s, b) => s + b.spent);
    final left = total - spent;
    final overCount = withBudget.where((b) => b.isOver).length;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: AppTheme.secondary),
              const SizedBox(width: 8),
              Text('Recurring budget',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (overCount > 0)
                AppBadge(
                  label: '$overCount over',
                  color: AppTheme.error,
                  icon: Icons.error_outline,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Budgeted',
                  value: money.format(total),
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(width: 1, height: 32, color: AppTheme.divider),
              Expanded(
                child: _Stat(
                  label: 'Used',
                  value: money.format(spent),
                  color: AppTheme.accent,
                ),
              ),
              Container(width: 1, height: 32, color: AppTheme.divider),
              Expanded(
                child: _Stat(
                  label: 'Still available',
                  value: money.format(left < 0 ? 0 : left),
                  color: left < 0 ? AppTheme.error : AppTheme.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textSecondary.withOpacity(0.95),
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
