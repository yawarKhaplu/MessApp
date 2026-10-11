import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers.dart';
import '../theme.dart';
import 'app_widgets.dart';
import 'skeleton.dart';

/// Spending over time, switchable between food only and everything.
///
/// One chart rather than two: a rent spike distorts the food pattern, but a
/// budget line drawn next to a food-only series wrongly implies the budget
/// covers food alone. So the series is chosen, not drawn together — food mode
/// carries no budget line, both mode does.
class SpendingTrendCard extends ConsumerStatefulWidget {
  const SpendingTrendCard({super.key});

  @override
  ConsumerState<SpendingTrendCard> createState() => _SpendingTrendCardState();
}

/// Windows the chart can be viewed over.
enum TrendRange {
  week('7D'),
  month30('30D'),

  /// First of the month through today, matching the monthly budget.
  thisMonth('MTD');

  const TrendRange(this.label);
  final String label;
}

/// Which spending the chart shows.
enum Series {
  /// Everything: menu food plus other expenses such as rent and gas.
  overall('Overall'),

  /// Menu cooking only.
  food('Food only');

  const Series(this.label);
  final String label;
}

class _SpendingTrendCardState extends ConsumerState<SpendingTrendCard> {
  TrendRange _range = TrendRange.thisMonth;

  /// Overall is the default: it is what the monthly budget actually covers,
  /// menu food plus rent, gas and everything else.
  Series _series = Series.overall;

  Future<_TrendData>? _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  void _reload() {
    if (!mounted) return;
    // Must be a block: the arrow form would return the Future from setState.
    setState(() {
      _data = _load();
    });
  }

  /// The window for the selected range. Computed synchronously so the header
/// and date label can render before the query returns.
({DateTime from, DateTime to}) _window() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final DateTime from;
  switch (_range) {
    case TrendRange.week:
      from = today.subtract(const Duration(days: 6));
    case TrendRange.month30:
      from = today.subtract(const Duration(days: 29));
    case TrendRange.thisMonth:
      from = DateTime(today.year, today.month, 1);
  }
  return (from: from, to: today);
}

  Future<_TrendData> _load() async {
    final repo = ref.read(repositoryProvider);
    final w = _window();
    final days = w.to.difference(w.from).inDays + 1;

    final results = await Future.wait([
      repo.getDailySplit(w.from, w.to),
      repo.getTodayBudget(),
    ]);
    final rows = results[0] as List<Map<String, Object?>>;
    final budget = (results[1] as Map<String, double>)['budget'] ?? 0;

    // Only days with spending come back, so gaps are filled with zeroes —
    // otherwise the line would lie about quiet days.
    final food = <String, double>{};
    final other = <String, double>{};
    for (final r in rows) {
      final key = r['date'] as String;
      food[key] = (r['food'] as num?)?.toDouble() ?? 0;
      other[key] = (r['other'] as num?)?.toDouble() ?? 0;
    }

    final dates = <DateTime>[];
    final foods = <double>[];
    final totals = <double>[];
    for (int i = 0; i < days; i++) {
      final d = w.from.add(Duration(days: i));
      final k = _dayKey(d);
      final f = food[k] ?? 0;
      dates.add(d);
      foods.add(f);
      totals.add(f + (other[k] ?? 0));
    }

    return _TrendData(dates, foods, totals, budget, w.from, w.to);
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataVersionProvider, (_, __) => _reload());

    final currency =
        ref.watch(settingsProvider).valueOrNull?.currency ?? 'PKR';
    final money =
        NumberFormat.currency(symbol: '$currency ', decimalDigits: 0);

    final foodOnly = _series == Series.food;

    return FutureBuilder<_TrendData>(
      future: _data,
      builder: (context, snap) {
        // The header needs no query, so it renders straight away and only the
        // chart area below waits for the data.
        final data = snap.data;
        final w = _window();
        final rangeLabel = '${DateFormat('d MMM').format(w.from)}'
            ' – ${DateFormat('d MMM').format(w.to)}';

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: title + range
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (foodOnly ? AppTheme.secondary : AppTheme.primary)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      foodOnly ? Icons.restaurant : Icons.account_balance_wallet_outlined,
                      color: foodOnly ? AppTheme.secondary : AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spending trend',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rangeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Segmented<TrendRange>(
                    values: TrendRange.values,
                    selected: _range,
                    labelOf: (v) => v.label,
                    onChanged: (r) {
                      setState(() {
                        _range = r;
                        _data = _load();
                      });
                    },
                    color: AppTheme.primary,
                  ),
                ],
              ),

              // Row 2: which spending to show
              const SizedBox(height: 12),
              _Segmented<Series>(
                values: Series.values,
                selected: _series,
                labelOf: (v) => v.label,
                onChanged: (s) => setState(() => _series = s),
                color: foodOnly ? AppTheme.secondary : AppTheme.primary,
              ),

              const SizedBox(height: 16),
              // Only the chart and metrics wait on the query.
              if (data == null)
                const ChartAreaSkeleton()
              else if (data.grandTotal <= 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No spending recorded in $rangeLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else ...[
                SizedBox(height: 140, child: _chart(data, foodOnly)),
                const SizedBox(height: 14),
                if (foodOnly)
                  _FoodSummary(data: data, money: money)
                else
                  _TotalSummary(data: data, money: money),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chart(_TrendData data, bool foodOnly) {
    final budget = data.budget;
    if (foodOnly) {
      return _ChartBase(
        data: data,
        values: data.foods,
        color: AppTheme.secondary,
        showBudget: false,
        seriesName: 'Food',
      );
    }
    final over = budget > 0 && data.avgTotal > budget;
    return _ChartBase(
      data: data,
      values: data.totals,
      color: over ? AppTheme.error : AppTheme.primary,
      showBudget: true,
      seriesName: 'Total',
    );
  }
}

/// Compact two-or-three way switch.
class _Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final Color color;

  const _Segmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: v == selected ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  labelOf(v),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        v == selected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartBase extends StatelessWidget {
  final _TrendData data;
  final List<double> values;
  final Color color;
  final bool showBudget;
  final String seriesName;

  const _ChartBase({
    required this.data,
    required this.values,
    required this.color,
    required this.seriesName,
    this.showBudget = false,
  });

  @override
  Widget build(BuildContext context) {
    final budget = data.budget;
    final peak = values.fold<double>(0, (m, v) => v > m ? v : m);
    var maxY = peak;
    if (showBudget && budget > maxY) maxY = budget;
    maxY = maxY <= 0 ? 100 : maxY * 1.25;

    final count = values.length;
    // Label every day when the window is short, thin out as it grows.
    final labelEvery = count <= 10 ? 1 : (count <= 16 ? 2 : 5);
    final money = NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (count - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= count) return const SizedBox.shrink();
                if (i % labelEvery != 0 && i != count - 1) {
                  return const SizedBox.shrink();
                }
                final isToday = i == count - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    i == 0
                        ? '1 ${DateFormat('MMM').format(data.dates[i])}'
                        : '${data.dates[i].day}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color:
                          isToday ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: showBudget && budget > 0
            ? ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: budget,
                    color: AppTheme.accent,
                    strokeWidth: 1.6,
                    dashArray: const [6, 4],
                  ),
                ],
              )
            : const ExtraLinesData(),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.textPrimary,
            getTooltipItems: (touched) => touched.map((spot) {
              final i = spot.x.round();
              final date = (i >= 0 && i < count) ? data.dates[i] : null;
              return LineTooltipItem(
                '${date == null ? '' : '${DateFormat('EEE d MMM').format(date)} · $seriesName'}\n',
                const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text: money.format(spot.y),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < count; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.22,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: count <= 16,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withOpacity(0.26), color.withOpacity(0.0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalSummary extends StatelessWidget {
  final _TrendData data;
  final NumberFormat money;

  const _TotalSummary({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    final budget = data.budget;
    final hasBudget = budget > 0;
    final overDays =
        hasBudget ? data.totals.where((t) => t > budget).length : 0;
    final over = hasBudget && data.avgTotal > budget;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Avg / day',
                value: money.format(data.avgTotal),
                color: AppTheme.textPrimary,
              ),
            ),
            Container(width: 1, height: 34, color: AppTheme.divider),
            Expanded(
              child: _Metric(
                label: 'Budget / day',
                value: hasBudget ? money.format(budget) : 'Not set',
                color: hasBudget ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
            Container(width: 1, height: 34, color: AppTheme.divider),
            Expanded(
              child: _Metric(
                label: 'Spent',
                value: money.format(data.grandTotal),
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        if (hasBudget) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (over ? AppTheme.error : AppTheme.success)
                  .withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  over ? Icons.trending_up : Icons.check_circle_outline,
                  size: 16,
                  color: over ? AppTheme.error : AppTheme.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    over
                        ? 'Averaging ${money.format(data.avgTotal - budget)} over budget · '
                            '$overDays of ${data.dates.length} days over'
                        : '$overDays of ${data.dates.length} days over budget · staying within it',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: over ? AppTheme.error : AppTheme.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FoodSummary extends StatelessWidget {
  final _TrendData data;
  final NumberFormat money;

  const _FoodSummary({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(
            label: 'Avg food / day',
            value: money.format(data.avgFood),
            color: AppTheme.secondary,
          ),
        ),
        Container(width: 1, height: 34, color: AppTheme.divider),
        Expanded(
          child: _Metric(
            label: 'Food total',
            value: money.format(data.foodTotal),
            color: AppTheme.textPrimary,
          ),
        ),
        Container(width: 1, height: 34, color: AppTheme.divider),
        Expanded(
          child: _Metric(
            label: 'Other expenses',
            value: money.format(data.otherTotal),
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
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
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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

class _TrendData {
  final List<DateTime> dates;
  final List<double> foods;
  final List<double> totals;
  final double budget;
  final DateTime from;
  final DateTime to;

  const _TrendData(
      this.dates, this.foods, this.totals, this.budget, this.from, this.to);

  double get foodTotal => foods.fold<double>(0, (s, v) => s + v);

  double get otherTotal {
    var t = 0.0;
    for (int i = 0; i < totals.length; i++) {
      t += totals[i] - foods[i];
    }
    return t;
  }

  double get grandTotal => totals.fold<double>(0, (s, v) => s + v);
  double get avgFood => foods.isEmpty ? 0 : foodTotal / foods.length;
  double get avgTotal => totals.isEmpty ? 0 : grandTotal / totals.length;

  /// "1 — 10 Oct" so the window is never ambiguous.
  String get rangeLabel =>
      '${DateFormat('d MMM').format(from)} — ${DateFormat('d MMM').format(to)}';
}
