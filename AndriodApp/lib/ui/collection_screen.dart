import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'member_detail_screen.dart';
import 'widgets/text_input_dialog.dart';

/// Monthly collection (PRD 5.4): members, monthly share, paid /
/// remaining, status.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() =>
      _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  double? _share;

  Future<void> _addMember() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: 'Add member',
        hint: 'Member name',
        confirmLabel: 'Add',
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(membersProvider.notifier).add(name.trim());
      await refreshTotals(ref);
    }
  }

  Future<void> _renameMember(Member member) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Rename member',
        hint: 'Member name',
        initialValue: member.name,
        confirmLabel: 'Save',
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(membersProvider.notifier).rename(member.id!, name.trim());
    }
  }

  Future<void> _deleteMember(Member member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${member.name}"?'),
        content: const Text('Member and their payment history will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(membersProvider.notifier).delete(member.id!);
    }
  }

  Future<void> _setShare() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Monthly share per member',
        hint: 'e.g. 2000',
        initialValue: _share?.toStringAsFixed(0) ?? '',
        numeric: true,
      ),
    );
    if (value != null) {
      final amount =
          double.tryParse(value.replaceAll(',', '')) ?? 0;
      if (amount > 0) {
        setState(() => _share = amount);
        final month = monthKey(ref.read(selectedMonthProvider));
        final members =
            await ref.read(membersProvider.future);
        for (final m in members) {
          await ref
              .read(repositoryProvider)
              .setMonthlyShare(m.id!, month, amount);
        }
        ref.invalidate(monthCollectionsProvider);
      }
    }
  }

  void _prevMonth() {
    final m = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state =
        DateTime(m.year, m.month - 1);
  }

  void _nextMonth() {
    final m = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state =
        DateTime(m.year, m.month + 1);
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final collections = ref.watch(monthCollectionsProvider);
    final month = ref.watch(selectedMonthProvider);

    final money =
        NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add member',
              onPressed: _addMember),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(monthCollectionsProvider);
          ref.invalidate(membersProvider);
        },
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Month selector + share
            AppCard(
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _prevMonth),
                  Expanded(
                    child: InkWell(
                      onTap: _setShare,
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('MMMM yyyy').format(month),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Share: ',
                                  style: TextStyle(color: AppTheme.textSecondary)),
                              Text(
                                _share == null
                                    ? 'set monthly share'
                                    : money.format(_share!),
                                style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Summary
            collections.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child:
                    Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (rows) {
                // Worked out per member and floored at zero, so someone
                // paying extra never cancels what the others still owe.
                double totalDue = 0;
                double totalPaid = 0;
                double stillDue = 0;
                double credit = 0;
                for (final r in rows) {
                  final due = (r['amount_due'] as num?)?.toDouble() ?? 0;
                  final paid = (r['paid'] as num?)?.toDouble() ?? 0;
                  totalDue += due;
                  totalPaid += paid;
                  if (due > paid) {
                    stillDue += due - paid;
                  } else {
                    credit += paid - due;
                  }
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.secondary, Color(0xFF00695C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondary.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryCol(
                              'Collected', money.format(totalPaid), Colors.white),
                          _summaryCol('Still to collect',
                              money.format(stillDue), Colors.white70),
                          _summaryCol(
                              'Target', money.format(totalDue), Colors.white70),
                        ],
                      ),
                    ),
                    if (credit > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.savings_outlined,
                                size: 17, color: AppTheme.accent),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '${money.format(credit)} paid in extra. It '
                                'counts towards the mess fund but does not '
                                'reduce anyone else\'s dues.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Members
            membersAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (members) {
                if (members.isEmpty) {
                  return const Center(
                    child: Text(
                        'No members yet. Tap + to add roommates.'),
                  );
                }
                return FutureBuilder<List<Map<String, Object?>>>(
                  future: ref
                      .read(repositoryProvider)
                      .getMonthCollections(monthKey(month)),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final rows = snap.data!;
                    return Column(
                      children: [
                        for (final member in members)
                          _memberCard(member, rows, money, month),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCol(String label, String value, Color color) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      );

  Widget _memberCard(Member member,
      List<Map<String, Object?>> rows, NumberFormat money, DateTime month) {
    Map<String, Object?>? row;
    for (final r in rows) {
      if (r['member_id'] == member.id) {
        row = r;
        break;
      }
    }
    final due = (row?['amount_due'] as num?)?.toDouble() ?? 0;
    final paid = (row?['paid'] as num?)?.toDouble() ?? 0;
    final remaining = due - paid;
    final overpaid = paid - due;

    String status;
    Color color;
    if (due <= 0) {
      status = 'no share set';
      color = AppTheme.textSecondary;
    } else if (overpaid > 0) {
      status = 'EXTRA';
      color = AppTheme.success;
    } else if (remaining <= 0) {
      status = 'PAID';
      color = AppTheme.success;
    } else if (paid > 0) {
      status = 'PARTIAL';
      color = AppTheme.warning;
    } else {
      status = 'PENDING';
      color = AppTheme.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MemberDetailScreen(
                member: member, month: month),
          ));
        },
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.8), color],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    overpaid > 0
                        ? 'Paid ${money.format(paid)} of ${money.format(due)} · ${money.format(overpaid)} extra'
                        : 'Paid ${money.format(paid)} of ${money.format(due)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppBadge(label: status, color: color),
                if (remaining > 0) ...[
                  const SizedBox(height: 4),
                  Text('${money.format(remaining)} left',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ],
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rename') _renameMember(member);
                if (v == 'delete') _deleteMember(member);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Remove')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
