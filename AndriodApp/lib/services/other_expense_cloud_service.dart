/// Shared "other expenses": spending that is not a meal — gas, rent, repairs.
///
/// Kept separate from meals because the accounting differs. A meal is shared by
/// the people who ate it; an other expense is a mess-wide bill, split evenly
/// whether or not everybody was involved.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// One other expense, filed against a category.
class CloudOtherExpense {
  final String id;

  /// Day as `yyyy-MM-dd`.
  final String date;
  final String category;
  final double amount;
  final String? note;

  /// Who entered it. Other expenses are the owner's business, so this is
  /// normally the owner, but it is kept for the audit trail.
  final String? recordedBy;

  /// What the money went for, kept as free text so an entry stays readable even
  /// after its category is renamed or removed.
  final String? title;

  final DateTime? createdAt;

  const CloudOtherExpense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note,
    this.recordedBy,
    this.title,
    this.createdAt,
  });

  factory CloudOtherExpense.fromDoc(String id, Map<String, dynamic> data) =>
      CloudOtherExpense(
        id: id,
        date: '${data['date'] ?? ''}',
        category: '${data['category'] ?? 'Other'}',
        amount: _amountOf(data['amount']),
        note: data['note'] as String?,
        recordedBy: data['recordedBy'] as String?,
        title: data['title'] as String?,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, Object?> toDoc() => {
        'date': date,
        'category': category,
        'amount': amount,
        'note': note,
        'recordedBy': recordedBy,
        'title': title,
        'createdAt': createdAt,
      };
}

/// Reads an amount that may have been stored as a number, a numeric string or
/// nothing at all.
///
/// A plain `as num?` cast throws when the field holds a string, which would take
/// down the whole list over one bad row. Reading it defensively means a single
/// malformed entry shows as zero instead of hiding every other expense with it.
double _amountOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0;
  return 0;
}

/// Reads a budget that may have been stored as a number, a numeric string or
/// nothing at all. Same reasoning as [_amountOf].
double _budgetOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0;
  return 0;
}

/// A category of other expense, with its monthly allowance.
///
/// The allowance lives on the category rather than in settings so it is shared:
/// one person setting the gas budget should not be a private number only they
/// can see.
class CloudOtherCategory {
  final String name;
  final double budget;
  final DateTime? createdAt;

  const CloudOtherCategory({
    required this.name,
    this.budget = 0,
    this.createdAt,
  });

  factory CloudOtherCategory.fromEntry(String key, Object? raw) {
    // A non-map row is treated as an empty one rather than cast blindly: the key
    // still names the category, so the row stays visible and usable.
    final data = raw is Map
        ? Map<dynamic, dynamic>.from(raw)
        : const <dynamic, dynamic>{};
    return CloudOtherCategory(
      name: '${data['name'] ?? key}',
      budget: _budgetOf(data['budget']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, Object?> toDoc() => {
        'name': name,
        'budget': budget,
        'createdAt': createdAt,
      };
}

/// A category with what has been spent against it in a given month.
///
/// [spent] is worked out in the app rather than read from a document, so the
/// figure always comes from the same expenses the list screen shows. A stored
/// running total could drift away from the entries it was derived from.
class CloudCategoryBudget {
  final CloudOtherCategory category;
  final double spent;

  const CloudCategoryBudget(this.category, this.spent);

  String get name => category.name;
  double get budget => category.budget;

  /// Money still available. Never negative — a category that is overspent is
  /// reported as zero remaining plus an [over] amount, rather than a negative
  /// figure that reads like a credit.
  double get remaining {
    final v = budget - spent;
    return v > 0 ? v : 0;
  }

  double get over {
    final v = spent - budget;
    return v > 0 ? v : 0;
  }

  bool get hasBudget => budget > 0;
  bool get isOver => hasBudget && spent > budget;

  /// Share of the allowance used, 0..1, or null when there is no allowance.
  double? get usedFraction =>
      hasBudget ? (spent / budget).clamp(0.0, 1.0).toDouble() : null;
}

/// Sum of one category's spending inside [from] and [to], both inclusive.
///
/// A separate function from the general totals because a category has to be
/// matched case-insensitively: two people typing "Gas" and "gas" should not be
/// charged to two different allowances.
double spentInCategory(
  Iterable<CloudOtherExpense> expenses,
  String category,
  String from,
  String to,
) {
  final key = category.trim().toLowerCase();
  var sum = 0.0;
  for (final e in expenses) {
    if (e.category.trim().toLowerCase() != key) continue;
    if (e.date.compareTo(from) < 0 || e.date.compareTo(to) > 0) continue;
    sum += e.amount;
  }
  return sum;
}

/// Total spending across every category inside a range.
double otherTotalBetween(
  Iterable<CloudOtherExpense> expenses,
  String from,
  String to,
) {
  var sum = 0.0;
  for (final e in expenses) {
    if (e.date.compareTo(from) < 0 || e.date.compareTo(to) > 0) continue;
    sum += e.amount;
  }
  return sum;
}

/// Every category name that has ever been used, so a mistyped one still shows
/// up in the list rather than vanishing out of the totals.
///
/// Taken from the expenses themselves rather than from the category list: a
/// category can be deleted while entries remain filed under it, and those
/// entries still cost the mess money.
List<String> categoriesInUse(Iterable<CloudOtherExpense> expenses) {
  final seen = <String, String>{};
  for (final e in expenses) {
    final name = e.category.trim();
    if (name.isEmpty) continue;
    seen.putIfAbsent(name.toLowerCase(), () => name);
  }
  return seen.values.toList()..sort();
}

/// The first and last day of a month, as inclusive `yyyy-MM-dd` bounds.
({String from, String to}) monthBounds(String month) {
  final year = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7));
  final lastDay = DateTime(year, m + 1, 0).day;
  return (from: '$month-01', to: '$month-${lastDay.toString().padLeft(2, '0')}');
}
