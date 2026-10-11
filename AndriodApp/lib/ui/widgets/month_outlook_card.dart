import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../theme.dart';
import 'app_widgets.dart';
import 'skeleton.dart';

/// Where the month is heading, and exactly what still needs collecting.
///
/// The two headline numbers are total spent and the projected month end, with
/// a budget bar showing how much of the month's shares has been used.
/// Everything secondary lives behind a collapsible so the card stays scannable.
class MonthOutlookCard extends ConsumerStatefulWidget {
  final DateTime month;

  const MonthOutlookCard({super.key, required this.month});

  @override
  ConsumerState<MonthOutlookCard> createState() => _MonthOutlookCardState();
}

class _MonthOutlookCardState extends ConsumerState<MonthOutlookCard> {
  Future<MonthOutlook>? _future;
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MonthOutlook> _load() => ref
      .read(repositoryProvider)
      .getMonthOutlook(widget.month);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataVersionProvider, (_, __) => _reload());

    final currency =
        ref.watch(settingsProvider).valueOrNull?.currency ?? 'PKR';
    final money =
        NumberFormat.currency(symbol: '$currency ', decimalDigits: 0);

    // Day counts need no query, so the header renders immediately.
    final now = DateTime.now();
    final m = widget.month;
    final lastDay = DateTime(m.year, m.month + 1, 0).day;
    final isCurrent = now.year == m.year && now.month == m.month;
    final isPast = !isCurrent &&
        (now.year > m.year || (now.year == m.year && now.month > m.month));
    final daysElapsed = isCurrent ? now.day : (isPast ? lastDay : 0);
    final daysLeft = lastDay - daysElapsed;
    final dayLine = daysElapsed > 0
        ? 'Day $daysElapsed of $lastDay · $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left'
        : 'Not started yet';

    return FutureBuilder<MonthOutlook>(
      future: _future,
      builder: (context, snap) {
        // Only the numbers wait on the query; the header is already correct.
        final o = snap.data;

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (o == null)
                _headerLoading(dayLine)
              else
                _header(o),
              const SizedBox(height: 18),

              if (o == null)
                const OutlookBodySkeleton()
              else ...[
                // ---- The two numbers that matter ----
                _figures(o, money),
                const SizedBox(height: 14),
                _verdict(o, money),
                const SizedBox(height: 4),
                _detailsToggle(),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeInOut,
                  crossFadeState: _detailsOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: _details(o, money),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Header while loading: date maths only, no figures.
  Widget _headerLoading(String dayLine) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.secondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.insights, color: AppTheme.secondary, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat.MMMM().format(widget.month)} outlook',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(dayLine,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _figures(MonthOutlook o, NumberFormat money) {
    final projectedColor = (o.hasTarget && o.projected > o.target)
        ? AppTheme.error
        : AppTheme.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Hero(
                label: 'Total spent',
                value: money.format(o.spent),
                sub: 'this month',
                color: AppTheme.textPrimary,
              ),
            ),
            Container(width: 1, height: 52, color: AppTheme.divider),
            Expanded(
              child: _Hero(
                label: 'Projected month end',
                value: money.format(o.projected),
                sub: o.committed > 0
                    ? 'incl. ${money.format(o.committed)} due'
                    : '${money.format(o.avgPerDay)}/day now',
                color: projectedColor,
              ),
            ),
          ],
        ),
        if (o.hasTarget) ...[
          const SizedBox(height: 16),
          _BudgetBar(o: o, money: money),
        ],
      ],
    );
  }

  Widget _header(MonthOutlook o) {
    final over = o.overPace && o.hasTarget;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: o.projectedShort
                  ? [AppTheme.error, const Color(0xFFB71C1C)]
                  : [AppTheme.secondary, const Color(0xFF00695C)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            o.projectedShort ? Icons.warning_amber_rounded : Icons.insights,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat.MMMM().format(o.month)} outlook',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                o.daysElapsed > 0
                    ? 'Day ${o.daysElapsed} of ${o.daysInMonth} · ${o.daysRemaining} ${o.daysRemaining == 1 ? 'day' : 'days'} left'
                    : 'Not started yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (over)
          const AppBadge(
            label: 'OVER PACE',
            color: AppTheme.error,
            icon: Icons.trending_up,
          ),
      ],
    );
  }

  /// Visual progress of the month's shares against what has been spent.
  Widget _BudgetBar({required MonthOutlook o, required NumberFormat money}) {
    final over = o.overPace;
    final color = over ? AppTheme.error : AppTheme.success;
    final fraction =
        (o.spent / (o.target <= 0 ? 1 : o.target)).clamp(0.0, 1.0).toDouble();
    final pct = o.target <= 0 ? 0.0 : (o.spent / o.target) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                'of ${money.format(o.target)} in shares',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.95),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                over
                    ? '${money.format(o.paceDelta.abs())} over pace'
                    : '${money.format(o.paceDelta.abs())} under pace',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              Container(height: 12, color: AppTheme.divider),
              FractionallySizedBox(
                widthFactor: fraction == 0 ? 0.01 : fraction,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: over
                          ? [AppTheme.error, const Color(0xFFB71C1C)]
                          : [AppTheme.success, const Color(0xFF2E7D32)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Plain-language answer: what happens, and what to do about it.
  Widget _verdict(MonthOutlook o, NumberFormat money) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;

    if (!o.hasTarget) {
      bg = AppTheme.textSecondary.withOpacity(0.08);
      fg = AppTheme.textSecondary;
      icon = Icons.info_outline;
      text = 'Set a monthly share per member in Collection to see how the '
          'month is tracking.';
    } else if (o.projectedShort) {
      bg = AppTheme.error.withOpacity(0.08);
      fg = AppTheme.error;
      icon = Icons.warning_amber_rounded;
      text = 'At ${money.format(o.avgPerDay)} a day the month ends around '
          '${money.format(o.projected)}'
          '${o.committed > 0 ? ' (including ${money.format(o.committed)} of other expenses not yet paid)' : ''}, '
          'but the shares only cover '
          '${money.format(o.availableIfAllPay)}.';
    } else if (o.toCollect > 0) {
      bg = AppTheme.accent.withOpacity(0.1);
      fg = AppTheme.accent;
      icon = Icons.schedule;
      text = 'On track to finish under budget. '
          '${money.format(o.toCollect)} of shares is still unpaid.';
    } else {
      bg = AppTheme.success.withOpacity(0.08);
      fg = AppTheme.success;
      icon = Icons.check_circle_outline;
      final spare = o.surplus > 0
          ? ' with about ${money.format(o.surplus)} to spare'
          : '';
      text = 'Every share is paid and it still covers the projected '
          'cost$spare.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsToggle() {
    return InkWell(
      onTap: () => setState(() => _detailsOpen = !_detailsOpen),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _detailsOpen ? 'Hide details' : 'Show details',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _detailsOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down,
                  size: 20, color: AppTheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  /// Everything that does not need to be on screen all the time.
  Widget _details(MonthOutlook o, NumberFormat money) {
    final ask = o.shortfall > 0 && o.memberCount > 0
        ? '${money.format(o.perMemberShortfall)} each from '
            '${o.memberCount} ${o.memberCount == 1 ? 'member' : 'members'}'
        : null;

    final rows = <_Detail>[
      _Detail(
        'Still to collect',
        o.toCollect > 0 ? money.format(o.toCollect) : 'Nothing',
        note: o.hasTarget
            ? '${money.format(o.collected)} of ${money.format(o.target)} in'
            : null,
        color: o.toCollect > 0 ? AppTheme.accent : AppTheme.success,
        icon: Icons.receipt_long_outlined,
      ),
      _Detail(
        'Balance in hand',
        money.format(o.balance),
        note: 'collected minus spent',
        color: o.balance >= 0 ? AppTheme.textPrimary : AppTheme.error,
        icon: Icons.account_balance_wallet_outlined,
      ),
      if (o.daysRemaining > 0)
        _Detail(
          'Safe to spend / day',
          money.format(o.allowedPerDay),
          note: '${o.daysRemaining} days left',
          color: AppTheme.textPrimary,
          icon: Icons.speed_outlined,
        ),
      if (o.hasTarget && o.daysRemaining > 0)
        _Detail(
          o.savingAtFixedRate >= 0
              ? 'Saving at your usual rate'
              : 'Overrun at your usual rate',
          money.format(o.savingAtFixedRate.abs()),
          note: 'keep ${money.format(o.fixedPerDay)}/day for the remaining '
              '${o.daysRemaining} ${o.daysRemaining == 1 ? 'day' : 'days'}'
              ' → ${money.format(o.spent + o.fixedPerDay * o.daysRemaining)}',
          color: o.savingAtFixedRate >= 0
              ? AppTheme.success
              : AppTheme.error,
          icon: Icons.savings_outlined,
        ),
      if (ask != null)
        _Detail(
          'Ask each member',
          money.format(o.shortfall),
          note: ask,
          color: AppTheme.error,
          icon: Icons.groups_outlined,
        ),
      if (o.committed > 0)
        _Detail(
          'Still committed',
          money.format(o.committed),
          note: 'budgeted other expenses not paid out yet',
          color: AppTheme.accent,
          icon: Icons.event_busy_outlined,
        ),
      if (o.credit > 0)
        _Detail(
          'Paid in extra',
          money.format(o.credit),
          note: 'counts towards the fund, not against others dues',
          color: AppTheme.secondary,
          icon: Icons.savings_outlined,
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            _detailRow(rows[i], money),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(_Detail d, NumberFormat money) {
    return Row(
      children: [
        Icon(d.icon, size: 17, color: d.color),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (d.note != null) ...[
                const SizedBox(height: 1),
                Text(
                  d.note!,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary.withOpacity(0.95),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          d.value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: d.color,
          ),
        ),
      ],
    );
  }
}

class _Detail {
  final String label;
  final String value;
  final String? note;
  final Color color;
  final IconData icon;

  const _Detail(
    this.label,
    this.value, {
    this.note,
    required this.color,
    required this.icon,
  });
}

/// A big number with a caption above it.
class _Hero extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _Hero({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary.withOpacity(0.95),
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}