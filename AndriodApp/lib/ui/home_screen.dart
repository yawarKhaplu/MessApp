import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
import '../services/mess_cloud_service.dart';
import '../services/expense_cloud_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_widgets.dart';
import 'edit_expense_screen.dart';
import 'menu_entry_screen.dart';
import 'other_expense_screen.dart';
import 'widgets/trend_card.dart';

/// Home screen (PRD 5.1): today's budget, today's bari, today's entries.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Held as fields so each query runs once instead of on every rebuild.
  // The budget and today's entries both come from the shared bundle now, so
  // there is nothing held here to fetch or refresh by hand.

  @override
  void initState() {
    super.initState();
    _startQueries();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _startQueries() {
    // The budget and today's entries both come from the shared bundle now, so
    // there is nothing to fetch here beyond asking the providers to re-read.
    ref.invalidate(todayBudgetProvider);
    ref.invalidate(sharedExpensesProvider(monthKey(DateTime.now())));
  }

  Future<void> _refresh() async {
    await refreshTotals(ref);
    _startQueries();
  }

  /// Let the owner decide who has the bari today.
  ///
  /// Writes the anchor to the mess document, so the whole mess sees the change
  /// rather than just this device. Members get no such action.
  Future<void> _changeBari(
      BuildContext context, WidgetRef ref, MessTurn turn) async {
    final mess = ref.read(activeMessProvider).valueOrNull;
    if (mess == null) return;

    final picked = await showDialog<MessMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who has the bari today?'),
        children: [
          for (final m in turn.order)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name ?? m.email)),
                    if (m.email.toLowerCase() ==
                        turn.today?.email.toLowerCase())
                      const AppBadge(
                        label: 'ON TURN',
                        color: AppTheme.secondary,
                        icon: Icons.bolt,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await ref.read(messCloudServiceProvider).setTurn(
            messId: mess.id,
            anchorDate: DateTime.now(),
            anchorEmail: picked.email,
            order: turn.order.map((m) => m.email).toList(),
          );
      // The anchor lives on the mess document, so re-read it.
      ref.invalidate(activeMessProvider);
      await refreshTotals(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${picked.name ?? picked.email} has the bari today')),
      );
    } on CloudMessage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.text)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayTotal = ref.watch(todaySpendProvider);
    // Re-query the cooking rotation whenever it changes.
    ref.watch(rotationTickProvider);
    // Re-query today's entries after any edit or delete.
    ref.watch(dataVersionProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final currency = settingsAsync.valueOrNull?.currency ?? 'PKR';
    final money = NumberFormat.currency(symbol: '$currency ', decimalDigits: 0);

    // What this account may do on Home. The owner can always record; anyone
    // else only on their own turn.
    final mess = ref.watch(activeMessProvider).valueOrNull;
    final isOwner = mess?.isOwner ?? false;
    final canRecordCook = ref.watch(canRecordTodaysCookProvider);
    final turn = ref.watch(messTurnProvider);

    // Needed to decide who recorded each entry, which is what separates the
    // owner's edit from the turn member's.
    final myEmail = ref.watch(currentUserProvider).valueOrNull?.email;

    return Scaffold(
      body: SafeArea(
        // No AppBar on this tab, and Android 15 draws edge-to-edge, so the
        // content would otherwise sit underneath the status bar.
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // Greeting
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MessAppDev',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Today's budget hero (budget / spent / remaining), read from the
            // shared bundle so it cannot disagree with the daily report.
            ref.watch(todayBudgetProvider).when(
              loading: () => const SizedBox(height: 180),
              error: (e, _) => const SizedBox(height: 180),
              data: (t) {
                // Today's frozen allowance. Spending today cannot move it, so the
                // number on screen is the number being enforced.
                final capToday = t.capToday;
                final capLeft = t.capLeft;
                final daysLeft = t.daysLeft;
                final hasTarget = t.hasTarget;
                final spent = t.spent;
                // Inside today's allowance or past it.
                final onTrack = spent < capToday;
                final remaining = capLeft;
                final hasBudget = capToday > 0;
                final progress =
                    hasBudget ? (spent / capToday).clamp(0.0, 1.0) : 0.0;
                final over = remaining < 0;

                return Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: over
                          ? [AppTheme.error, const Color(0xFFB71C1C)]
                          : hasBudget
                              ? [AppTheme.primary, AppTheme.primaryDark]
                              : [AppTheme.secondary, const Color(0xFF00695C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: (over
                                ? AppTheme.error
                                : hasBudget
                                    ? AppTheme.primary
                                    : AppTheme.secondary)
                            .withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pie_chart_outline,
                              color: Colors.white70, size: 20),
                          const SizedBox(width: 8),
                          Text('TODAY',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                letterSpacing: 1.2,
                              )),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _budgetCol(
                                context, 'Safe to spend',
                                hasBudget ? money.format(capToday) : 'Not set'),
                          ),
                          Container(
                              width: 1,
                              height: 44,
                              color: Colors.white24),
                          Expanded(
                            child: _budgetCol(
                                context, 'Spent', money.format(spent)),
                          ),
                          Container(
                              width: 1,
                              height: 44,
                              color: Colors.white24),
                          Expanded(
                            child: _budgetCol(
                              context,
                              'Remaining',
                              hasBudget ? money.format(remaining) : '—',
                              valueColor: over ? const Color(0xFFFFCDD2) : null,
                            ),
                          ),
                        ],
                      ),
                      if (hasBudget) ...[
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(
                                over ? const Color(0xFFFFCDD2) : Colors.white),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          over
                              ? 'Over today\'s allowance by ${money.format(remaining.abs())}'
                              : '${(progress * 100).toStringAsFixed(0)}% of today\'s allowance used',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                        if (hasTarget) ...[
                          const SizedBox(height: 14),
                          Container(height: 1, color: Colors.white24),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Green while today's spending is still inside
                              // the day's allowance, amber once it has passed.
                              Icon(
                                onTrack
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                color: onTrack
                                    ? const Color(0xFFB4EFB4)
                                    : const Color(0xFFFFE082),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  over
                                      ? 'Past today\'s allowance'
                                      : daysLeft > 0
                                          ? 'On track · $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left this month'
                                          : 'On track · last day of the month',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 14),
                        Text(
                          'Set a monthly share in Collection, or set a fixed '
                          'daily budget in Settings',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Spending trend against the daily budget
            const SpendingTrendCard(),
            const SizedBox(height: 16),

            // Today's bari (cooking turn) — read live from the mess document so the whole
            // mess sees the same person. Owner-only action; members read it on
            // their own screen.
            Builder(builder: (context) {
              final mess = ref.watch(activeMessProvider).valueOrNull;
              final turn = ref.watch(messTurnProvider);
              if (mess == null || !turn.hasMembers || turn.today == null) {
                return const SizedBox.shrink();
              }
              final onTurn = turn.today!;
              final name = onTurn.name ?? onTurn.email;

              // Is it this person's turn? Matched on email, lowercased on both
              // sides because Google returns the address as the account stores
              // it. This is the difference between "Ali has the bari" and
              // "the bari is yours today", which is what someone actually wants
              // to know when they open the app.
              final myEmail = ref
                  .watch(currentUserProvider)
                  .valueOrNull
                  ?.email
                  ?.trim()
                  .toLowerCase();
              final isMyTurn = myEmail != null &&
                  myEmail.isNotEmpty &&
                  myEmail == onTurn.email.trim().toLowerCase();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Only when it is actually your turn. A quiet banner rather
                  // than a whole card change, so the rest of the home screen
                  // keeps its normal shape.
                  if (isMyTurn) ...[
                    _YourTurnBanner(name: name),
                    const SizedBox(height: 12),
                  ],
                  AppCard(
                    // Tapping to change is an owner action. A member sees the
                    // same card but cannot alter the mess schedule.
                    onTap: mess.isOwner
                        ? () => _changeBari(context, ref, turn)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.secondary,
                                    Color(0xFF00695C)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.rotate_right,
                                  color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMyTurn ? "Today's bari is you" : "Today's bari",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Turn ${turn.positionInRound} of '
                                    '${turn.roundLength}'
                                    '${mess.isOwner ? ' · tap to change' : ''}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    AppTheme.secondary.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.restaurant,
                                  color: AppTheme.secondary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const AppBadge(
                                label: 'ON TURN',
                                color: AppTheme.secondary,
                                icon: Icons.bolt,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _TurnDots(
                          count: turn.order.length,
                          currentIndex: turn.positionInRound - 1,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.event_repeat,
                                size: 14,
                                color:
                                    AppTheme.textSecondary.withOpacity(0.9)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                turn.roundLength == 1
                                    ? 'Next up: ${turn.next?.name ?? turn.next?.email ?? '—'}'
                                    : 'Next up: ${turn.next?.name ?? turn.next?.email ?? '—'}'
                                        ' · back again in ${turn.roundLength - 1} '
                                        '${turn.roundLength - 1 == 1 ? 'day' : 'days'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary
                                      .withOpacity(0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (turn.upcoming.length > 1) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 66,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: turn.upcoming.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final t = turn.upcoming[i];
                                final isToday = i == 0;
                                final who = t.member.name ?? t.member.email;
                                // A future day that is this person's turn, so
                                // they can see when it next comes round to them.
                                final isMe = myEmail != null &&
                                    myEmail.isNotEmpty &&
                                    myEmail ==
                                        t.member.email.trim().toLowerCase();
                                return Container(
                                  width: 74,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? AppTheme.secondary.withOpacity(0.12)
                                        : isMe
                                            ? AppTheme.accent.withOpacity(0.10)
                                            : AppTheme.primary.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isToday
                                          ? AppTheme.secondary
                                              .withOpacity(0.35)
                                          : isMe
                                              ? AppTheme.accent
                                                  .withOpacity(0.45)
                                              : AppTheme.divider,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        isToday
                                            ? 'Today'
                                            : DateFormat('EEE')
                                                .format(t.date)
                                                .toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isToday
                                              ? AppTheme.secondary
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        who.trim().split(' ').first,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isToday
                                              ? AppTheme.secondary
                                              : isMe
                                                  ? AppTheme.accent
                                                  : AppTheme.textPrimary,
                                        ),
                                      ),
                                      // Marks which chip is this person, so
                                      // they need not recognise their own name
                                      // in a short list.
                                      if (isMe && !isToday)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Text(
                                            'YOU',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                              color: AppTheme.accent,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }),
            // A second route into the same screen, so the same rule has to apply here or
            // it becomes a way around the button below.
            if (canRecordCook)
              AppCard(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MenuEntryScreen()),
                  );
                  _refresh();
                },
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.today,
                        color: AppTheme.secondary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Today's total so far",
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(DateFormat.yMMMEd().format(DateTime.now()),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    money.format(todayTotal),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Today's entries, read from Firestore so the whole mess sees the same list.
            Builder(builder: (context) {
              // Two different keys on purpose: the provider is queried by month
              // because that is how expenses are partitioned, while the entries
              // kept from it are filtered by day because that is what "today"
              // means. Using one for both silently returns the wrong set.
              //
              // Named apart from the callback's own parameter below, because a
              // shadowed name here silently becomes the list rather than the
              // key, and the wrong one is a compile error that only a build
              // catches.
              final monthOfToday = monthKey(DateTime.now());
              final today = dayKey(DateTime.now());
              final all = ref.watch(sharedExpensesProvider(monthOfToday));
              return all.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load entries: $e',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                data: (entriesInMonth) {
                  final entries =
                      entriesInMonth.where((e) => e.date == today).toList();
                  if (entries.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: "Today's entries",
                        icon: Icons.checklist,
                        action: AppBadge(
                          label: '${entries.length} saved',
                          color: AppTheme.success,
                          icon: Icons.check,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final e in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TodayEntryTile(
                            entry: e,
                            money: money,

                            // Decided per entry, not once for the list: the
                            // owner may change any of them, but the turn member
                            // may change only the ones they recorded. One flag
                            // for the whole list would have to be the stricter of
                            // the two, which would hide the owner's edit.
                            canEdit: mess != null &&
                                mayEditExpense(
                                  mess: mess,
                                  email: myEmail,
                                  recordedBy: e.recordedBy ?? '',
                                ),

                            // Name from the shared roster, so the row reads
                            // "Akbar" rather than the front of his address.
                            cookName: mess == null
                                ? null
                                : _nameOf(mess.members, e.cookEmail),
                            onChanged: () {
                              ref.invalidate(
                                  sharedExpensesProvider(monthOfToday));
                              _refresh();
                            },
                          ),
                        ),
                      const SizedBox(height: 14),
                    ],
                  );
                },
              );
            }),

            // The big question
            Text('What did you cook today?',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),

            // Only the person whose turn it is can record what they cooked, plus
            // the owner who keeps the books. Everyone else is told when their turn
            // comes rather than being shown a button that would be refused.
            if (canRecordCook)
              GradientButton(
                label: 'Add today\'s menu',
                icon: Icons.add_circle_outline,
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MenuEntryScreen()),
                  );
                  _refresh();
                },
              )
            else
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 20, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _nextTurnHint(
                            turn,
                            ref.watch(currentUserProvider)
                                .valueOrNull
                                ?.email,
                          ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Other expenses are the owner's paperwork: rent, gas and the like
            // are recorded once for the mess, so only they may add them.
            if (isOwner)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const OtherExpenseScreen()),
                    );
                    _refresh();
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Add other expense (gas, rent, chai…)'),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Small label + value column used inside the budget hero card.
Widget _budgetCol(BuildContext context, String label, String value,
    {Color? valueColor}) {
  return Column(
    children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.75), fontSize: 11)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

/// Shown only when today is the signed-in person's turn.
///
/// Answered in plain words rather than left for the person to work out from a
/// name on a card, because "is it me?" is the question someone opens the app
/// with.
class _YourTurnBanner extends StatelessWidget {
  const _YourTurnBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.secondary, Color(0xFF00695C)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'It is your bari today',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
        ],
      ),
    );
  }
}

/// Why the "Add today's menu" button is not showing, and when it will.
///
/// Says the actual next day rather than just "not your turn", so somebody
/// waiting does not have to check the schedule separately.
///
/// Takes the signed-in address rather than reading a provider, so it is a pure
/// function of the turn and the account and can be reasoned about on its own.
String _nextTurnHint(MessTurn turn, String? email) {
  final today = turn.today;
  if (today == null) {
    return 'Nobody is in the mess yet, so there is no cooking turn.';
  }

  final lower = (email ?? '').trim().toLowerCase();

  if (lower.isNotEmpty && turn.upcoming.isNotEmpty) {
    final startOfToday = turn.upcoming.first.date;

    for (final entry in turn.upcoming) {
      if (entry.member.email.trim().toLowerCase() != lower) continue;

      // Days measured from today rather than from the list, so the wording does
      // not depend on where in the preview the day happens to fall.
      final days = entry.date.difference(startOfToday).inDays;

      // Only a day still ahead is somebody else's problem. Zero days is today,
      // which is the one case where the button *is* showing, so it must not be
      // described as "not your turn".
      if (days <= 0) continue;

      if (days == 1) return 'Your turn is tomorrow.';
      return 'Your turn is in $days days.';
    }
  }

  // Either it is somebody else's turn today, or their turn has fallen outside
  // the preview. Both read the same to the person waiting: it is not today.
  return 'Today is ${_who(today)}. '
      'You can record what was cooked on your turn.';
}

/// Best available name for someone in the roster.
String _who(MessMember member) => member.name ?? member.email;

/// Looks a person up in the shared roster by address.
///
/// Matched on the lowercased address because that is how the roster and an
/// entry's cookEmail are both stored.
///
/// A member added without a real name has their address stored in the name
/// field, which would otherwise put "yawarsdocument@gmail.com" on a card meant
/// for "Yawar". Those cases fall back to the part before the @, which is short
/// enough to read and is what the turn chips already show.
///
/// Returns null only when the address is not in the roster at all — somebody
/// removed since cooking — so the caller can decide on its own fallback rather
/// than being handed a blank.
String? _nameOf(List<MessMember> roster, String email) {
  final lower = email.trim().toLowerCase();
  if (lower.isEmpty) return null;

  for (final m in roster) {
    if (m.email.trim().toLowerCase() != lower) continue;

    final name = (m.name ?? '').trim();
    if (name.isEmpty) return null;

    // The name is really just the address again, so it is not a name.
    if (name.contains('@') || name.toLowerCase() == lower) return null;

    return name;
  }
  return null;
}

/// Rotation progress dots: filled = already had their turn this round,
/// outlined = still waiting.
class _TurnDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _TurnDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < count; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: i <= currentIndex
                    ? AppTheme.secondary
                    : AppTheme.secondary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single shared entry for today.
///
/// Visible to everyone in the mess. Editable by the admin on any entry, and by
/// the turn member only on an entry they recorded themselves.
class _TodayEntryTile extends StatelessWidget {
  final CloudExpense entry;
  final NumberFormat money;
  final bool canEdit;
  final VoidCallback onChanged;

  /// Name to show for whoever cooked, taken from the shared roster.
  final String? cookName;

  const _TodayEntryTile({
    required this.entry,
    required this.money,
    required this.canEdit,
    required this.onChanged,
    this.cookName,
  });

  @override
  Widget build(BuildContext context) {
    // Falls back to the address's local part so the row is never blank, but the
    // roster's name is preferred: "Akbar" rather than "akbar.baltim".
    final cook = (cookName ?? entry.cookEmail.split('@').first).trim();
    final showCook = cook.isNotEmpty;

    return AppCard(
      onTap: canEdit
          ? () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditExpenseScreen(entry: entry),
                ),
              );
              onChanged();
            }
          : null,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.menuName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 13, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('Saved',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.success)),
                    if (showCook) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.person,
                          size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(cook,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money.format(entry.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              if (canEdit)
                Row(
                  children: [
                    Text('Edit',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right,
                        size: 15, color: AppTheme.primary),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
