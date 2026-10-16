import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/collection_cloud_service.dart';
import '../services/mess_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'member_detail_screen.dart';
import 'mess/members_screen.dart';
import 'widgets/text_input_dialog.dart';

/// Monthly collection (PRD 5.4): members, monthly share, paid /
/// remaining, status.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  Widget _loadError(Object error, String month) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Could not load: $error', textAlign: TextAlign.center),
        TextButton(
          onPressed: () => ref.invalidate(sharedCollectionsProvider(month)),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  /// Opens the mess roster, which is the live list in Firestore.
  ///
  /// Adding somebody here used to write a name into this device's own database,
  /// which meant they were invisible to the rest of the mess and could not sign
  /// in. Members are now real mess members with an email, so this goes to the
  /// screen that manages them.
  Future<void> _manageMembers() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MembersScreen()));
    // The roster is shared, so anything changed there has to be reflected back
    // into this screen's own data.
    ref.invalidate(activeMessProvider);
    ref.invalidate(membersProvider);
    ref.invalidate(monthCollectionsProvider);
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
        content: const Text(
          'Member and their payment history will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(membersProvider.notifier).delete(member.id!);
    }
  }

  Future<void> _setShare() async {
    final month = monthKey(ref.read(selectedMonthProvider));
    final shares = ref
        .read(sharedCollectionsProvider(month))
        .valueOrNull
        ?.values
        .map((c) => c.amountDue)
        .toSet();
    final share = shares?.length == 1 ? shares!.first : null;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Monthly share per member',
        hint: 'e.g. 2000',
        initialValue: share != null && share > 0
            ? share.toStringAsFixed(0)
            : '',
        numeric: true,
      ),
    );
    if (value == null || !mounted) return;

    final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
    if (amount <= 0) return;

    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    // Written to Firestore, so the share is the same for everyone in the mess
    // rather than only on this device.
    try {
      await ref
          .read(messCloudServiceProvider)
          .setMonthlyShareForAll(
            messId: mess.id,
            month: month,
            amount: amount,
            roster: mess.members,
          );
      ref.invalidate(sharedCollectionsProvider(month));
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.text)));
    }
  }

  void _prevMonth() {
    final m = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state = DateTime(
      m.year,
      m.month - 1,
    );
  }

  void _nextMonth() {
    final m = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state = DateTime(
      m.year,
      m.month + 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final month = ref.watch(selectedMonthProvider);
    final monthKeyValue = monthKey(month);

    // Collections are shared: read from Firestore, keyed by member email, so
    // whoever records a payment and whoever is shown the figure are looking at
    // the same numbers.
    final shared = ref.watch(sharedCollectionsProvider(monthKeyValue));

    // Collections belong to the owner. Members may browse every month and open
    // any member to read the figures, but nothing on this tab writes.
    final isOwner = ref.watch(activeMessProvider).valueOrNull?.isOwner ?? false;

    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final shareLabel = shared.when(
      loading: () => 'loading…',
      error: (_, __) => 'unavailable',
      data: (collections) {
        final shares = collections.values.map((c) => c.amountDue).toSet();
        if (shares.isEmpty || shares.every((amount) => amount <= 0)) {
          return 'not set';
        }
        return shares.length == 1
            ? money.format(shares.first)
            : 'varies by member';
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          // Adding and removing people is the owner's call, and it happens on
          // the shared roster rather than in this device's own table.
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add member to the mess',
              onPressed: _manageMembers,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activeMessProvider);
          ref.invalidate(sharedCollectionsProvider(monthKeyValue));
          await ref.read(sharedCollectionsProvider(monthKeyValue).future);
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
                    onPressed: _prevMonth,
                  ),
                  Expanded(
                    // Tapping the month sets the shared monthly share, which is
                    // an owner action. Members can still move between months to
                    // read past figures.
                    child: InkWell(
                      onTap: isOwner ? _setShare : null,
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
                              const Text(
                                'Share: ',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              Text(
                                shareLabel,
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _nextMonth,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Summary
            shared.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _loadError(e, monthKeyValue),
              data: (byEmail) {
                // Worked out per member and floored at zero, so someone
                // paying extra never cancels what the others still owe.
                double totalDue = 0;
                double totalPaid = 0;
                double stillDue = 0;
                double credit = 0;
                for (final c in byEmail.values) {
                  totalDue += c.amountDue;
                  totalPaid += c.paid;
                  if (c.amountDue > c.paid) {
                    stillDue += c.amountDue - c.paid;
                  } else {
                    credit += c.paid - c.amountDue;
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
                            'Collected',
                            money.format(totalPaid),
                            Colors.white,
                          ),
                          _summaryCol(
                            'Still to collect',
                            money.format(stillDue),
                            Colors.white70,
                          ),
                          _summaryCol(
                            'Target',
                            money.format(totalDue),
                            Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    if (credit > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.savings_outlined,
                              size: 17,
                              color: AppTheme.accent,
                            ),
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
            // Members, straight from the shared roster so the list cannot drift from who
            // is actually in the mess.
            if (mess == null)
              const Center(child: CircularProgressIndicator())
            else if (mess.members.isEmpty)
              Center(
                child: Text(
                  'No members yet. Tap the person icon to add roommates to the '
                  'mess.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              shared.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _loadError(e, monthKeyValue),
                data: (byEmail) => Column(
                  children: [
                    for (final member in mess.members)
                      _memberCard(
                        member,
                        byEmail[member.email.trim().toLowerCase()] ??
                            MemberCollection(
                              email: member.email,
                              month: monthKeyValue,
                              amountDue: 0,
                            ),
                        money,
                        month,
                        isOwner: isOwner,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCol(String label, String value, Color color) => Column(
    children: [
      Text(
        label,
        style: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: color,
        ),
      ),
    ],
  );

  Widget _memberCard(
    MessMember member,
    MemberCollection collection,
    NumberFormat money,
    DateTime month, {
    required bool isOwner,
  }) {
    final due = collection.amountDue;
    final paid = collection.paid;
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

    final label = member.displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MemberDetailScreen(
                name: member.displayName,
                email: member.email,
                month: month,
              ),
            ),
          );
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
                  label.isNotEmpty ? label[0].toUpperCase() : '?',
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
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
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
                  Text(
                    '${money.format(remaining)} left',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            // No per-member rename or remove here. Those used to edit this device's own
            // members table, which no longer backs this list — the roster comes
            // from Firestore. Renaming or removing someone happens on the mess
            // roster, reached from the app bar.
          ],
        ),
      ),
    );
  }
}
