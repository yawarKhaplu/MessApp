import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/expense_cloud_service.dart';
import '../services/mess_cloud_service.dart';
import '../services/other_expense_cloud_service.dart';
import '../services/report_cloud_service.dart';
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

    return ref.watch(reportBundleProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: CircularProgressIndicator()),
      data: (bundle) {
        final collected =
            bundle.collectedBetween(dayKey(range.from), dayKey(range.to)).collected;
        final spent =
            bundle.spentBetween(dayKey(range.from), dayKey(range.to));
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
    final bundle =
        await ref.read(messCloudServiceProvider).reportBundle(ref
            .read(activeMessProvider)
            .valueOrNull
            ?.id ??
            '');

    final t = bundle.collectedBetween(dayKey(from), dayKey(to));

    return {
      'collected': t.collected,
      // Spent from the same bundle, so the two figures on this screen cannot
      // come from different reads of different months.
      'spent': bundle.spentBetween(dayKey(from), dayKey(to)),
    };
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

    return ref.watch(reportBundleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (bundle) {
            final days =
                bundle.dailyTotals(dayKey(range.from), dayKey(range.to));
            if (days.isEmpty) {
              return const Center(child: Text('No expenses in this range.'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final row = days[i];
                final date = DateTime.parse(row.day);
                final total = row.total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => _showDayDetail(context, ref, bundle, date, money),
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
                                      fontSize: 10,
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(DateFormat.EEEE().format(date),
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(DateFormat.yMMMd().format(date),
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
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

  Future<void> _showDayDetail(
      BuildContext context,
      WidgetRef ref,
      ReportBundle bundle,
      DateTime day,
      NumberFormat money) async {
    final key = dayKey(day);
    final entries = bundle.dayEntries(key);
    final expenses = entries.meals;
    final other = entries.other;

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
                    // Owners and the member who recorded (or was assigned as
                    // cook) may edit today's entry. The server enforces the
                    // same shape, so a denied tap only hides a dead button.
                    final mess = ref.read(activeMessProvider).valueOrNull;
                    if (mess != null &&
                        !mayEditExpense(
                          mess: mess,
                          email: ref.read(currentUserProvider).valueOrNull?.email,
                          recordedBy: e.recordedBy ?? '',
                          cookEmail: e.cookEmail,
                        )) {
                      return;
                    }
                    final entry = e;
                    Navigator.pop(ctx);

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditExpenseScreen(entry: entry),
                      ),
                    );
                    if (context.mounted) {
                      await refreshTotals(ref);
                      // The entry may have been moved to another month by the
                      // edit, so both the month it came from and the one it is in
                      // are cleared rather than leaving a stale copy behind.
                      ref.invalidate(sharedExpensesProvider(monthOf(entry.date)));
                      ref.invalidate(
                          sharedExpensesProvider(monthOf(monthKey(day))));
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_menu_outlined,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.menuName,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text(money.format(e.total),
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
                    // Already the shared record, so no lookup is needed.
                    final record = o;
                    Navigator.pop(ctx);

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherExpenseScreen(editing: record),
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

    return ref.watch(reportBundleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (bundle) {
            final rows =
                bundle.byCook(dayKey(range.from), dayKey(range.to));
            if (rows.isEmpty) {
              return const Center(
                  child: Text('No member-tagged entries in this range.'));
            }

            final grand = rows.fold<double>(0, (s, r) => s + r.total);

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final total = r.total;
                final entries = r.entries;
                final share = grand > 0 ? total / grand : 0.0;
                final name = r.label;
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
                            Text(
                                '$entries ${entries == 1 ? 'entry' : 'entries'} · ${(share * 100).toStringAsFixed(0)}% of spend',
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

    return ref.watch(reportBundleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (bundle) {
            final rows = bundle.byMenu(dayKey(range.from), dayKey(range.to));
            if (rows.isEmpty) {
              return const Center(child: Text('No menu expenses in this range.'));
            }

            final grand = rows.fold<double>(0, (s, r) => s + r.total);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final total = r.total;
                final share = grand > 0 ? total / grand : 0.0;
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(r.label,
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

    return ref.watch(reportBundleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (bundle) {
            final rows = bundle.byItem(dayKey(range.from), dayKey(range.to));
            if (rows.isEmpty) {
              return const Center(child: Text('No item expenses in this range.'));
            }

            final grand = rows.fold<double>(0, (s, r) => s + r.total);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final total = r.total;
                final share = grand > 0 ? total / grand : 0.0;
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.label,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: share,
                                minHeight: 6,
                                backgroundColor: AppTheme.divider,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppTheme.secondary),
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

    return ref.watch(reportBundleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (bundle) {
            // A member with no document at all is left out: a share of zero and
            // no share recorded are different things, and showing "PKR 0 due" for
            // somebody the owner never set a share for would be a claim, not a
            // reading.
            final rows = bundle
                .collectionsFor(month)
                .where((c) => c.amountDue > 0 || c.payments.isNotEmpty)
                .toList();

            if (rows.isEmpty) {
              return const Center(
                  child: Text('No collections set for this month yet.'));
            }

            rows.sort((a, b) => a.email.compareTo(b.email));

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = rows[i];
                final due = c.amountDue;
                final paid = c.paid;
                final remaining = due - paid;
                final overpaid = paid - due;

                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bundle.nameOf(c.email) ?? c.email.split('@').first,
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
