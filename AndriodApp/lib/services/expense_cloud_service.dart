/// Shared expense data: what the mess cooked, what it cost and who cooked it.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// One day's entry: a menu, the items bought for it and who cooked.
class CloudExpense {
  final String id;

  /// Day as `yyyy-MM-dd`.
  final String date;

  /// The shared menu this was entered from, by name. Kept as text so the entry
  /// still reads sensibly after the menu is renamed or removed.
  final String menuName;

  final double total;

  /// Who cooked, by email. This is the person whose turn it was, and the only
  /// person allowed to enter the meal themselves.
  final String cookEmail;

  /// Who actually typed it in. May be the owner recording on someone's behalf.
  final String? recordedBy;

  final List<CloudExpenseItem> items;

  /// When it was recorded, so two entries in the same moment can be told apart.
  final DateTime? createdAt;

  const CloudExpense({
    required this.id,
    required this.date,
    required this.menuName,
    required this.total,
    required this.cookEmail,
    this.recordedBy,
    this.items = const [],
    this.createdAt,
  });

  factory CloudExpense.fromDoc(
      String id, Map<String, dynamic> data) {
    final rawItems =
        Map<dynamic, dynamic>.from((data['items'] as Map?) ?? const {});
    final items = <CloudExpenseItem>[];
    for (final entry in rawItems.entries) {
      final value = entry.value;
      if (value is Map) {
        items.add(CloudExpenseItem.fromEntry(
          '${entry.key}',
          Map<dynamic, dynamic>.from(value),
        ));
      }
    }

    return CloudExpense(
      id: id,
      date: '${data['date'] ?? ''}',
      menuName: '${data['menuName'] ?? ''}',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      cookEmail: '${data['cookEmail'] ?? ''}'.toLowerCase(),
      recordedBy: data['recordedBy'] as String?,
      items: items,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, Object?> toDoc() => {
        'date': date,
        'menuName': menuName,
        'total': total,
        'cookEmail': cookEmail.toLowerCase(),
        'recordedBy': recordedBy,
        'createdAt': createdAt,
        'items': {for (final i in items) i.id: i.toDoc()},
      };
}

/// One thing bought for a meal.
class CloudExpenseItem {
  final String id;
  final String name;
  final double quantity;
  final double price;

  const CloudExpenseItem({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.price = 0,
  });

  double get lineTotal => quantity * price;

  factory CloudExpenseItem.fromEntry(String id, Map<dynamic, dynamic> data) =>
      CloudExpenseItem(
        id: id,
        name: '${data['name'] ?? ''}',
        quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
        price: (data['price'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object?> toDoc() => {
        'name': name,
        'quantity': quantity,
        'price': price,
      };
}

/// Expense ids are generated rather than auto-incremented, because Firestore has
/// no autoincrement and the id has to be stable across devices.
///
/// A counter is mixed into the timestamp so two ids created in the same
/// microsecond still differ; a collision would silently drop one meal.
int _idCounter = 0;

String newExpenseId() => 'e${DateTime.now().microsecondsSinceEpoch}'
    '${(_idCounter++).toString().padLeft(3, '0')}';

String newExpenseItemId() => 'i${DateTime.now().microsecondsSinceEpoch}'
    '${(_idCounter++).toString().padLeft(3, '0')}';

/// The month a day belongs to, as `yyyy-MM`.
String monthOf(String day) => day.length >= 7 ? day.substring(0, 7) : day;

/// Totals for a day, used by Home and the reports.
class ExpenseTotals {
  final double total;
  final int entries;

  const ExpenseTotals({this.total = 0, this.entries = 0});

  ExpenseTotals operator +(ExpenseTotals other) => ExpenseTotals(
        total: total + other.total,
        entries: entries + other.entries,
      );
}

/// Sums a set of entries.
///
/// Kept as a plain function over a list rather than a database query, so the
/// same figures can be produced from a day, a month or a whole report range
/// without three different implementations disagreeing with each other.
ExpenseTotals totalOf(Iterable<CloudExpense> expenses) {
  var total = 0.0;
  var count = 0;
  for (final e in expenses) {
    total += e.total;
    count++;
  }
  return ExpenseTotals(total: total, entries: count);
}

/// Sums only the entries inside [from] and [to], both inclusive.
ExpenseTotals totalBetween(Iterable<CloudExpense> expenses,
    String from, String to) {
  return totalOf(expenses.where((e) =>
      e.date.compareTo(from) >= 0 && e.date.compareTo(to) <= 0));
}

/// Splits a day's cost across items in proportion to what each one cost.
///
/// Used for the "split the total" shortcut when entering a meal. Returns
/// fractions of the whole keyed by the lowercased item name, so they can be
/// matched back case-insensitively against the menu's items.
Map<String, double> splitByItem(List<CloudExpenseItem> items) {
  final amounts = <String, double>{};
  var sum = 0.0;
  for (final i in items) {
    final line = i.lineTotal;
    if (line <= 0) continue;
    final key = i.name.trim().toLowerCase();
    amounts[key] = (amounts[key] ?? 0) + line;
    sum += line;
  }
  if (sum <= 0) return const {};
  return amounts.map((k, v) => MapEntry(k, v / sum));
}