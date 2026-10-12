/// Everything the reports need, already read from Firestore.
///
/// The reports used to ask SQLite six separate questions and each one ran its own
/// aggregate query. Here they are handed one bundle and every figure is worked
/// out from it in Dart.
///
/// That is not only simpler: Firestore queries cannot be proven against a rule
/// that reads another document, so there is no way to ask the database for
/// "totals grouped by member" at all. Aggregating here is the only shape these
/// rules allow, and doing it in one place means the daily list, the trend and the
/// month forecast cannot disagree with each other about the same day.
library;

import 'collection_cloud_service.dart';
import 'expense_cloud_service.dart';
import 'mess_cloud_service.dart';
import 'other_expense_cloud_service.dart';

/// One row of a "grouped by" report.
class ReportRow {
  final String label;
  final double total;
  final int entries;

  const ReportRow(this.label, this.total, this.entries);
}

/// Spend on one day, split so the reader can see what it went on.
class DayTotals {
  /// Meals — what was cooked.
  final double food;

  /// Other expenses — gas, rent, chai.
  final double other;

  /// Everything.
  double get total => food + other;

  const DayTotals({this.food = 0, this.other = 0});
}

/// Money taken in, and what is still owed.
class CollectionTotals {
  final double collected;
  final double due;

  /// Still outstanding, summed per member.
  ///
  /// Deliberately not [due] minus [collected]: one member paying extra must
  /// never make the app claim the others owe less than they really do.
  final double stillDue;

  /// Paid in beyond each member's own share, summed per member.
  final double credit;

  const CollectionTotals({
    this.collected = 0,
    this.due = 0,
    this.stillDue = 0,
    this.credit = 0,
  });
}

/// Spend on one month, and what the month is expected to come to.
class MonthFigures {
  final String month;
  final double foodSpent;
  final double otherSpent;

  /// Total of the recurring category allowances, whether or not paid out yet.
  final double expectedOther;

  /// Allowances set but not yet spent. Rent that is due but unpaid still has to
  /// be paid, so it counts towards the month even with no expense entered.
  final double committed;

  final double collected;
  final CollectionTotals collections;

  final int daysElapsed;
  final int daysRemaining;
  final int daysInMonth;

  /// Days that have gone by, counting today as one of them, but never more than
  /// the month actually has.
  int get daysElapsedSafe => daysElapsed.clamp(0, daysInMonth);

  double get spent => foodSpent + otherSpent;

  const MonthFigures({
    required this.month,
    required this.foodSpent,
    required this.otherSpent,
    required this.expectedOther,
    required this.committed,
    required this.collected,
    required this.collections,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.daysInMonth,
  });

  /// Where the month lands if spending simply continues at the current rate.
  ///
  /// Averaged over days that have actually happened, so a figure entered late in
  /// the month is not read as though it were a whole month's spending.
  double get projected {
    final gone = daysElapsedSafe;
    if (gone <= 0) return 0;
    return spent / gone * daysInMonth;
  }

  /// Where the month lands if the current daily rate holds for every day left.
  double get projectedAtFixedRate => spent + (spent / daysElapsedSafe * daysRemaining);

  /// True when spending is running ahead of a straight line through the month.
  bool get overPace {
    final gone = daysElapsedSafe;
    if (gone <= 0 || daysInMonth <= 0) return false;
    return spent / gone * daysInMonth > foodSpent + expectedOther;
  }
}

/// All shared data the reports read, with every figure worked out from it.
class ReportBundle {
  final String messId;

  /// Everyone visible in the mess, for turning addresses into names.
  final List<MessMember> roster;

  /// Meals the caller may read.
  final List<CloudExpense> meals;

  /// Other expenses the caller may read, across every month loaded.
  final List<CloudOtherExpense> other;

  /// Monthly shares and payments.
  final List<MemberCollection> collections;

  final List<CloudOtherCategory> categories;

  const ReportBundle({
    required this.messId,
    this.roster = const [],
    this.meals = const [],
    this.other = const [],
    this.collections = const [],
    this.categories = const [],
  });

  /// An empty bundle, used while the mess is still loading so a report shows
  /// zeroes rather than an error.
  const ReportBundle.empty()
      : messId = '',
        roster = const [],
        meals = const [],
        other = const [],
        collections = const [],
        categories = const [];

  bool get isEmpty => meals.isEmpty && other.isEmpty;

  // ---- Filtering ----

  Iterable<CloudExpense> mealsIn(String from, String to) =>
      meals.where((e) => e.date.compareTo(from) >= 0 && e.date.compareTo(to) <= 0);

  Iterable<CloudOtherExpense> otherIn(String from, String to) => other
      .where((e) => e.date.compareTo(from) >= 0 && e.date.compareTo(to) <= 0);

  /// Collections belonging to one month.
  Iterable<MemberCollection> collectionsFor(String month) =>
      collections.where((c) => c.month == month);

  // ---- Day and month totals ----

  /// What was spent on one day, split into meals and other expenses.
  DayTotals dayTotals(String day) => DayTotals(
        food: totalBetween(meals, day, day).total,
        other: otherTotalBetween(other, day, day),
      );

  /// Everything spent on one day.
  double dayTotal(String day) => dayTotals(day).total;

  /// Food spent on one day.
  double dayFoodTotal(String day) => totalBetween(meals, day, day).total;

  /// Everything spent between [from] and [to], both inclusive.
  double spentBetween(String from, String to) =>
      foodBetween(from, to) + otherBetween(from, to);

  double foodBetween(String from, String to) =>
      totalBetween(meals, from, to).total;

  double otherBetween(String from, String to) =>
      otherTotalBetween(other, from, to);

  /// Average spend per day across the range.
  ///
  /// Counts every day in the range, not only the days something was recorded
  /// on. Dividing by the number of days with entries would report a quiet week
  /// as expensive as a busy one.
  double averagePerDay(String from, String to) {
    final days = _daysInclusive(from, to);
    if (days <= 0) return 0;
    return spentBetween(from, to) / days;
  }

  /// Money taken in between [from] and [to], and what is still owed.
  ///
  /// Counts payments by the day they were made, not by which month's share they
  /// settle: paying last month's bill in this one is collected this month.
  CollectionTotals collectedBetween(String from, String to) {
    var collected = 0.0;
    var stillDue = 0.0;
    var credit = 0.0;
    var due = 0.0;

    for (final c in collections) {
      due += c.amountDue;

      // A payment with no readable date is still money in; leaving it out would
      // understate what has been collected.
      for (final p in c.payments) {
        final d = p.date;
        if (d != null) {
          final key = _dayOf(d);
          if (key.compareTo(from) < 0 || key.compareTo(to) > 0) continue;
        }
        collected += p.amount;
      }

      final outstanding = c.amountDue - c.paid;
      if (outstanding > 0) {
        stillDue += outstanding;
      } else {
        credit += -outstanding;
      }
    }

    return CollectionTotals(
      collected: collected,
      due: due,
      stillDue: stillDue,
      credit: credit,
    );
  }

  // ---- Grouped reports ----

  /// Spend grouped by whoever cooked.
  ///
  /// Matched on the address rather than the stored name, then turned into a name
  /// here, so the same person cannot appear twice under two spellings.
  List<ReportRow> byCook(String from, String to) {
    final totals = <String, List<double>>{};

    for (final e in mealsIn(from, to)) {
      final key = e.cookEmail.trim().toLowerCase();
      if (key.isEmpty) continue;
      final t = totals.putIfAbsent(key, () => [0, 0]);
      t[0] += e.total;
      t[1] += 1;
    }

    final rows = [
      for (final e in totals.entries)
        ReportRow(nameOf(e.key) ?? 'Unassigned', e.value[0], e.value[1].round()),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return rows;
  }

  /// Spend grouped by menu.
  List<ReportRow> byMenu(String from, String to) {
    final totals = <String, List<double>>{};

    for (final e in mealsIn(from, to)) {
      final key = e.menuName.trim();
      if (key.isEmpty) continue;
      final t = totals.putIfAbsent(key, () => [0, 0]);
      t[0] += e.total;
      t[1] += 1;
    }

    final rows = [
      for (final e in totals.entries)
        ReportRow(e.key, e.value[0], e.value[1].round()),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return rows;
  }

  /// Spend grouped by what was bought.
  ///
  /// An item bought on three days is one row, not three: the question is what
  /// the mess spends on, not how many times.
  List<ReportRow> byItem(String from, String to) {
    final totals = <String, List<double>>{};

    for (final e in mealsIn(from, to)) {
      for (final i in e.items) {
        final key = i.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        final t = totals.putIfAbsent(key, () => [0, 0]);
        t[0] += i.lineTotal;
        t[1] += 1;
      }
    }

    final rows = [
      for (final e in totals.entries) ReportRow(e.key, e.value[0], e.value[1].round()),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return rows;
  }

  /// Spend grouped by whoever recorded it.
  List<ReportRow> byRecorder(String from, String to) {
    final totals = <String, List<double>>{};

    for (final e in mealsIn(from, to)) {
      final key = (e.recordedBy ?? '').trim().toLowerCase();
      if (key.isEmpty) continue;
      final t = totals.putIfAbsent(key, () => [0, 0]);
      t[0] += e.total;
      t[1] += 1;
    }

    final rows = [
      for (final e in totals.entries)
        ReportRow(nameOf(e.key) ?? 'Unassigned', e.value[0], e.value[1].round()),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return rows;
  }

  /// Categories with their allowances and what has been spent this month.
  List<CloudCategoryBudget> categoryBudgets(String month) {
    final bounds = monthBounds(month);
    return [
      for (final c in categories)
        CloudCategoryBudget(
          c,
          spentInCategory(other, c.name, bounds.from, bounds.to),
        ),
    ];
  }

  // ---- The month, and where it is heading ----

  /// Spend and collections for one month.
  ///
  /// [today] is passed in rather than read from the clock, so the figures are the
  /// same in a test as on the phone.
  MonthFigures monthFigures(String month, DateTime today) {
    final bounds = monthBounds(month);
    final first = DateTime.parse(bounds.from);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;

    // Comparing by month text rather than by date arithmetic, so a month in the
    // past reports itself as finished instead of running its counters backwards.
    final thisMonth = monthKeyOf(today) == month;
    final isPast = month.compareTo(monthKeyOf(today)) < 0;

    final elapsed = isPast
        ? daysInMonth
        : thisMonth
            ? today.day
            : 0;
    final remaining = isPast || !thisMonth ? 0 : daysInMonth - today.day;

    final otherMonth = otherIn(bounds.from, bounds.to).toList();
    final expectedOther = categories.fold<double>(
      0,
      (sum, c) => sum + (c.budget > 0 ? c.budget : 0),
    );
    final otherSpent = otherMonth.fold<double>(0, (s, e) => s + e.amount);
    final committed = expectedOther - otherSpent;

    final collections = collectedBetween(bounds.from, bounds.to);

    return MonthFigures(
      month: month,
      foodSpent: foodBetween(bounds.from, bounds.to),
      otherSpent: otherSpent,
      expectedOther: expectedOther,
      // Never negative: an allowance that is over-spent is fully committed, not
      // committed backwards.
      committed: committed > 0 ? committed : 0,
      collected: collections.collected,
      collections: collections,
      daysElapsed: elapsed,
      daysRemaining: remaining,
      daysInMonth: daysInMonth,
    );
  }

  // ---- Names ----

  /// A member's display name, matched on address.
  ///
  /// Returns null when the address is not in the roster — somebody who has left,
  /// or an entry typed with a different address — so the caller can fall back
  /// rather than showing a blank row.
  String? nameOf(String email) {
    final lower = email.trim().toLowerCase();
    if (lower.isEmpty) return null;

    for (final m in roster) {
      if (m.email.trim().toLowerCase() != lower) continue;
      final name = (m.name ?? '').trim();
      // A name that is really just the address again is not a name.
      if (name.isEmpty || name.contains('@') || name.toLowerCase() == lower) {
        return null;
      }
      return name;
    }
    return null;
  }
}

/// A month as `yyyy-MM`.
///
/// Written out here rather than imported from the data models: the shared layer
/// must not depend on the local models it is replacing, or moving a feature out
/// of SQLite would never actually remove it.
String monthKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}';

/// Days between [from] and [to], counting both ends.
int _daysInclusive(String from, String to) {
  final a = DateTime.tryParse(from);
  final b = DateTime.tryParse(to);
  if (a == null || b == null) return 0;
  return b.difference(a).inDays + 1;
}

String _dayOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
