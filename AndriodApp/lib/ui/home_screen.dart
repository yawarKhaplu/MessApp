import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../providers.dart';
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
  Future<Map<String, double>>? _budgetFuture;
  Future<List<Map<String, Object?>>>? _entriesFuture;
  Future<_CookInfo>? _cookFuture;

  @override
  void initState() {
    super.initState();
    _startQueries();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _startQueries() {
    final repo = ref.read(repositoryProvider);
    _budgetFuture = repo.getTodayBudget();
    _entriesFuture = repo.getDayExpenses(DateTime.now());
    _cookFuture = _loadCookInfo();
  }

  Future<void> _refresh() async {
    await refreshTotals(ref);
    _startQueries();
  }

  /// Cooking turn info for today, plus any manual override already saved
  /// on one of today's entries.
  Future<_CookInfo> _loadCookInfo() async {
    final repo = ref.read(repositoryProvider);
    final rotation = await repo.getCookRotation();
    if (!rotation.turnsAreSure) {
      return _CookInfo(rotation, null);
    }
    final entries = await repo.getDayExpenses(DateTime.now());
    Member? assigned;
    for (final e in entries) {
      final id = e['member_id'] as int?;
      if (id == null) continue;
      for (final m in rotation.members) {
        if (m.id == id) {
          assigned = m;
          break;
        }
      }
      if (assigned != null) break;
    }
    return _CookInfo(rotation, assigned);
  }

  /// Let the user decide who has the bari today. Re-anchors the cycle so the
  /// choice sticks instead of snapping back to a date-based schedule.
  Future<void> _changeBari(
      BuildContext context, WidgetRef ref, CookRotation rot) async {
    final picked = await showDialog<Member>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who has the bari today?'),
        children: [
          for (final m in rot.members)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name)),
                    if (m.id == rot.cook?.id)
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
    await ref.read(repositoryProvider).setBari(DateTime.now(), picked);
    await refreshTotals(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${picked.name} has the bari today')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayTotal = ref.watch(todayTotalProvider);
    // Re-query the cooking rotation whenever it changes.
    ref.watch(rotationTickProvider);
    // Re-query today's entries after any edit or delete.
    ref.watch(dataVersionProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final currency = settingsAsync.valueOrNull?.currency ?? 'PKR';
    final money = NumberFormat.currency(symbol: '$currency ', decimalDigits: 0);

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

            // Today's budget hero (budget / spent / remaining)
            FutureBuilder<Map<String, double>>(
              future: _budgetFuture,
              builder: (context, snap) {
                final b = snap.data;
                final spent = b?['spent'] ?? 0;
                // Today's frozen allowance. Spending today cannot move it, so the
                // number on screen is the number being enforced.
                final capToday = b?['capToday'] ?? 0;
                final capLeft = b?['capLeft'] ?? 0;
                final daysLeft = (b?['daysLeft'] ?? 0).round();
                final hasTarget = (b?['hasTarget'] ?? 0) > 0;
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

            // Today's bari (cooking turn) — user-controlled rotation.
            FutureBuilder<_CookInfo>(
              future: _cookFuture,
              builder: (context, snap) {
                final info = snap.data;
                if (info == null || !info.rotation.turnsAreSure) {
                  return const SizedBox.shrink();
                }
                final rot = info.rotation;
                final onTurn = info.assigned ?? rot.cook!;
                final overridden = info.assigned != null &&
                    info.assigned!.id != rot.cook!.id;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppCard(
                      onTap: () => _changeBari(context, ref, rot),
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
                                    Text("Today's bari",
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Turn ${rot.positionInRound} of ${rot.roundLength} · tap to change',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
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
                                  color: AppTheme.secondary.withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.restaurant,
                                    color: AppTheme.secondary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    onTurn.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                if (overridden)
                                  const AppBadge(
                                    label: 'CHANGED',
                                    color: AppTheme.accent,
                                    icon: Icons.edit,
                                  )
                                else if (rot.followsHistory)
                                  const AppBadge(
                                    label: 'AUTO',
                                    color: AppTheme.textSecondary,
                                    icon: Icons.history,
                                  )
                                else
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
                            members: rot.members,
                            currentIndex: rot.positionInRound - 1,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.event_repeat,
                                  size: 14,
                                  color: AppTheme.textSecondary
                                      .withOpacity(0.9)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  rot.roundJustCompleted
                                      ? 'Everyone has cooked — a fresh round starts today'
                                      : rot.followsHistory
                                          ? 'Next up: ${rot.next?.name ?? '—'} · based on who cooked last'
                                          : 'Next up: ${rot.next?.name ?? '—'} · back again in ${rot.daysUntilNextTurn} ${rot.daysUntilNextTurn == 1 ? 'day' : 'days'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary
                                        .withOpacity(0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (rot.upcoming.length > 1) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 66,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: rot.upcoming.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final t = rot.upcoming[i];
                                  final isToday = i == 0;
                                  return Container(
                                    width: 74,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isToday
                                          ? AppTheme.secondary
                                              .withOpacity(0.12)
                                          : AppTheme.primary
                                              .withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isToday
                                            ? AppTheme.secondary
                                                .withOpacity(0.35)
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
                                          t.member.name.split(' ').first,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isToday
                                                ? AppTheme.secondary
                                                : AppTheme.textPrimary,
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
              },
            ),
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

            // Today's entries (visible + editable)
            FutureBuilder<List<Map<String, Object?>>>(
              future: _entriesFuture,
              builder: (context, snap) {
                final entries = snap.data ?? const <Map<String, Object?>>[];
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
                          expense: Expense(
                            id: e['id'] as int?,
                            date: DateTime.parse(e['date'] as String),
                            menuId: e['menu_id'] as int?,
                            memberId: e['member_id'] as int?,
                            total: (e['total'] as num?)?.toDouble() ?? 0,
                          ),
                          menuName:
                              e['menu_name'] as String? ?? 'Menu entry',
                          memberName: e['member_name'] as String?,
                          date: DateTime.parse(e['date'] as String),
                          money: money,
                          onChanged: _refresh,
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                );
              },
            ),

            // The big question
            Text('What did you cook today?',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Add today\'s menu',
              icon: Icons.add_circle_outline,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MenuEntryScreen()),
                );
                _refresh();
              },
            ),
            const SizedBox(height: 12),

            // Other expenses shortcut
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OtherExpenseScreen()),
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

/// Cooking turn for today plus any manual override already saved.
class _CookInfo {
  final CookRotation rotation;
  final Member? assigned;

  const _CookInfo(this.rotation, this.assigned);
}

/// Rotation progress dots: filled = already cooked this round,
/// outlined = still waiting for their turn.
class _TurnDots extends StatelessWidget {
  final List<Member> members;
  final int currentIndex;

  const _TurnDots({required this.members, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < members.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == members.length - 1 ? 0 : 6),
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

/// A single saved entry for today; tap to edit it.
class _TodayEntryTile extends StatelessWidget {
  final Expense expense;
  final String menuName;
  final String? memberName;
  final DateTime date;
  final NumberFormat money;
  final VoidCallback onChanged;

  const _TodayEntryTile({
    required this.expense,
    required this.menuName,
    this.memberName,
    required this.date,
    required this.money,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditExpenseScreen(
              expense: expense,
              menuName: menuName,
              date: date,
            ),
          ),
        );
        onChanged();
      },
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
                Text(menuName,
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
                    if (memberName != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.person,
                          size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(memberName!,
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
              Text(money.format(expense.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
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
