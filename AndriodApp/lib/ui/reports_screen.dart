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
import 'edit_expense_screen.dart';
import 'other_expense_screen.dart';
import 'widgets/month_outlook_card.dart';
import 'widgets/pick_date.dart';

/// Reports (PRD 5.6): wallet, daily (with drill-down), menu-wise,
/// item-wise, member collection. Filters: month / custom range.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await pickClampedDate(
      context,
      initialDate: ref.read(reportRangeProvider).from,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Pick a month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      final from = DateTime(picked.year, picked.month, 1);
      final to = DateTime(picked.year, picked.month + 1, 0);
      ref.read(reportRangeProvider.notifier).state = (from: from, to: to);
    }
  }

  Future<void> _pickCustomRange() async {
    final range = ref.read(reportRangeProvider);
    final from = await pickClampedDate(
      context,
      initialDate: range.from,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (from == null || !mounted) return;
    final to = await pickClampedDate(
      context,
      // The stored range can end on the last day of a month that has not
      // finished, which is after "today" and would otherwise crash the picker.
      initialDate: range.to.isAfter(from) ? range.to : from,
      firstDate: from,
      lastDate: DateTime.now(),
    );
    if (to != null) {
      ref.read(reportRangeProvider.notifier).state = (from: from, to: to);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(reportRangeProvider);
    final rangeLabel =
        '${DateFormat('d MMM').format(range.from)} – ${DateFormat('d MMM yyyy').format(range.to)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'month') _pickMonth();
              if (v == 'range') _pickCustomRange();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'month', child: Text('Filter by month')),
              PopupMenuItem(
                  value: 'range', child: Text('Custom date range')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.date_range, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(rangeLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Wallet'),
              Tab(text: 'Daily'),
              Tab(text: 'By member'),
              Tab(text: 'Menu-wise'),
              Tab(text: 'Item-wise'),
              Tab(text: 'Members'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
                _WalletTab(),
                _DailyTab(),
                _ByMemberTab(),
                _MenuWiseTab(),
                _ItemWiseTab(),
                _MembersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wallet: remaining = collected - expenses (PRD 5.6).
class _WalletTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    ref.watch(dataVersionProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<Map<String, double>>(
      future: _walletTotals(ref, range.from, range.to),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final collected = snap.data!['collected']!;
        final spent = snap.data!['spent']!;
        final balance = collected - spent;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: balance >= 0
                    ? const LinearGradient(
                        colors: [AppTheme.success, Color(0xFF1B5E20)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [AppTheme.error, Color(0xFFB71C1C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (balance >= 0 ? AppTheme.success : AppTheme.error)
                        .withOpacity(0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text('MESS WALLET',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      )),
                  const SizedBox(height: 12),
                  Text(
                    money.format(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    balance >= 0 ? 'Available balance' : 'Overdrawn',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  _row(context, 'Total collected', money.format(collected),
                      AppTheme.success, Icons.payments_outlined),
                  const Divider(),
                  _row(context, 'Total spent', money.format(spent),
                      AppTheme.error, Icons.shopping_cart_outlined),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Month forecast last: the plain balances come first, the
            // projection is the thing you read once you have those.
            MonthOutlookCard(month: range.from),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, String label, String value,
          Color color, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: color)),
          ],
        ),
      );

  Future<Map<String, double>> _walletTotals(
      WidgetRef ref, DateTime from, DateTime to) async {
    final repo = ref.read(repositoryProvider);
    final collected = await repo.getTotalCollected(from: from, to: to);
    final expenses = await repo.getExpenses(from: from, to: to);
    final other = await repo.getOtherExpenses(from: from, to: to);
    final spent = expenses.fold<double>(0, (s, e) => s + e.total) +
        other.fold<double>(0, (s, e) => s + e.amount);
    return {'collected': collected, 'spent': spent};
  }
}

/// Daily report with drill-down (PRD 5.6).
class _DailyTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    // Re-query after any edit, add or delete.
    ref.watch(dataVersionProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(repositoryProvider).getDailyTotals(range.from, range.to),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final days = snap.data!;
        if (days.isEmpty) {
          return const Center(child: Text('No expenses in this range.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final d = days[i];
            final date = DateTime.parse(d['date'] as String);
            final total = (d['total'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _showDayDetail(context, ref, date, money),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${date.day}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: AppTheme.primary)),
                          Text(DateFormat('MMM').format(date),
                              style: const TextStyle(
                                  fontSize: 10, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat.EEEE().format(date),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(DateFormat.yMMMd().format(date),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(money.format(total),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDayDetail(BuildContext context, WidgetRef ref,
      DateTime day, NumberFormat money) async {
    final repo = ref.read(repositoryProvider);
    final expenses = await repo.getDayExpenses(day);
    final other = await repo.getOtherExpenses(from: day, to: day);

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(DateFormat.yMMMEd().format(day),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final e in expenses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () async {
                    // Open the editor for the shared entry this row refers to.
                    // The report itself still reads local rows, so the entry is
                    // looked up in Firestore by date; an entry not found there is
                    // one saved before the move, and is left alone rather than
                    // opened for editing against the wrong record.
                    final date = '${e['date']}';
                    final shared = await ref.read(messCloudServiceProvider)
                        .expenses(
                          ref.read(activeMessProvider).valueOrNull?.id ?? '',
                          monthOf(date),
                        );

                    CloudExpense? found;
                    for (final candidate in shared) {
                      if (candidate.date == date &&
                          candidate.menuName ==
                              (e['menu_name'] as String? ?? 'Menu entry') &&
                          candidate.total ==
                              (e['total'] as num?)?.toDouble()) {
                        found = candidate;
                        break;
                      }
                    }

                    Navigator.pop(ctx);
                    if (found == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'This entry was saved on this device only and '
                                'is not in the mess yet.'),
                          ),
                        );
                      }
                      return;
                    }

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditExpenseScreen(entry: found!),
                      ),
                    );
                    if (context.mounted) {
                      await refreshTotals(ref);
                      ref.invalidate(sharedExpensesProvider(monthOf(date)));
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_menu_outlined,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e['menu_name'] as String? ?? 'Menu entry',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text(money.format((e['total'] as num?)?.toDouble() ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            for (final o in other)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () async {
                    // The report still reads local rows while other expenses
                    // have moved to Firestore, so the shared entry this row
                    // refers to is looked up by date, category and amount. A row
                    // with no match is one saved before the move, and is left
                    // alone rather than opened for editing against a different
                    // record. This disappears once reports read Firestore too.
                    final messId =
                        ref.read(activeMessProvider).valueOrNull?.id ?? '';
                    final day = dayKey(o.date);
                    final shared = await ref
                        .read(messCloudServiceProvider)
                        .otherExpenses(messId, monthOf(day));

                    CloudOtherExpense? found;
                    for (final c in shared) {
                      if (c.date == day &&
                          c.category == o.category &&
                          c.amount == o.amount) {
                        found = c;
                        break;
                      }
                    }

                    Navigator.pop(ctx);
                    if (found == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'This record was saved on this device only and '
                                'is not in the mess yet.'),
                          ),
                        );
                      }
                      return;
                    }

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherExpenseScreen(editing: found),
                      ),
                    );
                    if (context.mounted) {
                      await refreshTotals(ref);
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_outlined,
                          color: AppTheme.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(o.category,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text(money.format(o.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 16, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-member spend on menu entries (who cooked / who paid).
class _ByMemberTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    ref.watch(dataVersionProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref
          .read(repositoryProvider)
          .getMemberWiseTotals(range.from, range.to),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
              child: Text('No member-tagged entries in this range.'));
        }
        final grand = rows.fold<double>(
            0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = rows[i];
            final total = (r['total'] as num?)?.toDouble() ?? 0;
            final entries = (r['entries'] as num?)?.toInt() ?? 0;
            final share = grand > 0 ? total / grand : 0.0;
            final name = r['name'] as String? ?? 'Unassigned';
            final unassigned = name == 'Unassigned';

            return AppCard(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: (unassigned
                              ? AppTheme.textSecondary
                              : AppTheme.primary)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                        unassigned ? Icons.person_off : Icons.person,
                        color: unassigned
                            ? AppTheme.textSecondary
                            : AppTheme.primary,
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text('$entries ${entries == 1 ? 'entry' : 'entries'} · ${(share * 100).toStringAsFixed(0)}% of spend',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 6,
                            backgroundColor: AppTheme.divider,
                            valueColor: AlwaysStoppedAnimation(unassigned
                                ? AppTheme.textSecondary
                                : AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(money.format(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Menu-wise report (PRD 5.6).
class _MenuWiseTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    ref.watch(dataVersionProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(repositoryProvider).getMenuWiseTotals(range.from, range.to),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No menu expenses in this range.'));
        }
        final grand = rows.fold<double>(
            0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = rows[i];
            final total = (r['total'] as num?)?.toDouble() ?? 0;
            final share = grand > 0 ? total / grand : 0.0;
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r['name'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(money.format(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 8,
                      backgroundColor: AppTheme.divider,
                      valueColor:
                          const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${(share * 100).toStringAsFixed(1)}% of spending',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Item-wise report (PRD 5.6).
class _ItemWiseTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    ref.watch(dataVersionProvider);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(repositoryProvider).getItemWiseTotals(range.from, range.to),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No item expenses in this range.'));
        }
        final grand = rows.fold<double>(
            0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = rows[i];
            final total = (r['total'] as num?)?.toDouble() ?? 0;
            final share = grand > 0 ? total / grand : 0.0;
            return AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['name'] as String,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 6,
                            backgroundColor: AppTheme.divider,
                            valueColor:
                                const AlwaysStoppedAnimation(AppTheme.secondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(money.format(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondary)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Member collection report (PRD 5.6): paid vs remaining per member.
class _MembersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    ref.watch(dataVersionProvider);
    final month = monthKey(range.from);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(repositoryProvider).getMonthCollections(month),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
              child: Text('No collections set for this month yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = rows[i];
            final due = (r['amount_due'] as num?)?.toDouble() ?? 0;
            final paid = (r['paid'] as num?)?.toDouble() ?? 0;
            final remaining = due - paid;
            final overpaid = paid - due;
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['member_name'] as String,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Paid ${money.format(paid)}',
                          style: Theme.of(context).textTheme.bodyMedium),
                      if (due > 0 && overpaid > 0)
                        Text(
                          '${money.format(overpaid)} extra',
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else if (remaining > 0)
                        Text(
                          '${money.format(remaining)} remaining',
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else if (due > 0)
                        const Text(
                          'Fully paid',
                          style: TextStyle(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        const Text(
                          'No share set',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
