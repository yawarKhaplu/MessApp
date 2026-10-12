import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/other_expense_cloud_service.dart';

/// Other expenses are the mess's non-meal spending — gas, rent, repairs. These
/// tests cover the arithmetic and the stored shape, because an allowance that
/// drifts from the entries it came from would tell the owner the wrong thing
/// about how much is left.
void main() {
  CloudOtherExpense expense(
    String date,
    String category,
    double amount, {
    String? title,
  }) =>
      CloudOtherExpense(
        id: 'o1',
        date: date,
        category: category,
        amount: amount,
        title: title,
      );

  group('spending within one category', () {
    final entries = [
      expense('2026-10-01', 'Gas', 2000),
      expense('2026-10-15', 'Gas', 500),
      expense('2026-10-20', 'Rent', 25000),
    ];

    test('adds up only that category', () {
      expect(spentInCategory(entries, 'Gas', '2026-10-01', '2026-10-31'), 2500);
    });

    test('leaves other categories out', () {
      expect(
          spentInCategory(entries, 'Rent', '2026-10-01', '2026-10-31'), 25000);
    });

    test('a category with no spending is zero', () {
      expect(spentInCategory(entries, 'Wifi', '2026-10-01', '2026-10-31'), 0);
    });

    test('the bounds are included on both ends', () {
      // An off-by-one here would silently drop the first or last day of a
      // month, which is exactly the day a bill lands on.
      final g = spentInCategory(entries, 'Gas', '2026-10-01', '2026-10-15');
      expect(g, 2500);
    });

    test('a range that excludes everything is zero', () {
      expect(spentInCategory(entries, 'Gas', '2026-09-01', '2026-09-30'), 0);
    });

    test('the category name is matched regardless of case', () {
      // Two people typing "Gas" and "gas" must not be charged to two separate
      // allowances, which would understate both.
      final mixed = [
        expense('2026-10-01', 'Gas', 300),
        expense('2026-10-02', 'gas', 100),
      ];

      expect(spentInCategory(mixed, 'GAS', '2026-10-01', '2026-10-31'), 400);
      expect(spentInCategory(mixed, 'Gas', '2026-10-01', '2026-10-31'), 400);
    });

    test('surrounding whitespace does not create a second category', () {
      final spaced = [
        expense('2026-10-01', 'Gas', 300),
        expense('2026-10-02', ' Gas ', 100),
      ];

      expect(spentInCategory(spaced, 'gas', '2026-10-01', '2026-10-31'), 400);
    });
  });

  group('spending across all categories', () {
    test('sums everything in the range', () {
      final entries = [
        expense('2026-10-01', 'Gas', 2000),
        expense('2026-10-15', 'Rent', 25000),
        expense('2026-09-30', 'Gas', 999),
      ];

      expect(otherTotalBetween(entries, '2026-10-01', '2026-10-31'), 27000);
    });

    test('an empty list is zero', () {
      expect(otherTotalBetween(const [], '2026-10-01', '2026-10-31'), 0);
    });
  });

  group('allowances', () {
    CloudCategoryBudget budget(double allowance, double spent) =>
        CloudCategoryBudget(
            CloudOtherCategory(name: 'Gas', budget: allowance), spent);

    test('remaining is what is left of the allowance', () {
      expect(budget(5000, 2000).remaining, 3000);
    });

    test('remaining never goes negative', () {
      // A negative figure here would read like the mess is owed money.
      expect(budget(5000, 8000).remaining, 0);
      expect(budget(5000, 8000).over, 3000);
    });

    test('nothing is over when the allowance holds', () {
      expect(budget(5000, 2000).over, 0);
      expect(budget(5000, 2000).isOver, isFalse);
    });

    test('exactly on the allowance is not over', () {
      expect(budget(5000, 5000).isOver, isFalse);
      expect(budget(5000, 5000).remaining, 0);
    });

    test('no allowance means no over-spend', () {
      final b = budget(0, 9000);
      expect(b.hasBudget, isFalse);
      expect(b.isOver, isFalse);
      expect(b.usedFraction, isNull);
    });

    test('the used fraction is clamped to one', () {
      // A progress bar must not overflow its track when a category blows past
      // its allowance.
      expect(budget(5000, 10000).usedFraction, 1.0);
      expect(budget(5000, 2500).usedFraction, 0.5);
    });
  });

  group('categories in use', () {
    test('are listed once each, ignoring case', () {
      final entries = [
        expense('2026-10-01', 'Gas', 100),
        expense('2026-10-02', 'gas', 100),
        expense('2026-10-03', 'Rent', 100),
      ];

      final names = categoriesInUse(entries);
      expect(names, hasLength(2));
      expect(names, containsAll(['Gas', 'Rent']));
    });

    test('a blank category is ignored', () {
      final entries = [
        expense('2026-10-01', '', 100),
        expense('2026-10-02', '   ', 100),
      ];

      expect(categoriesInUse(entries), isEmpty);
    });

    test('a category still in use shows up after being deleted', () {
      // Deleting the category must not hide money the mess still spent.
      final entries = [expense('2026-10-01', 'Wifi', 3000)];
      expect(categoriesInUse(entries), contains('Wifi'));
    });

    test('an empty list gives an empty result', () {
      expect(categoriesInUse(const []), isEmpty);
    });
  });

  group('month bounds', () {
    test('runs from the first to the last day', () {
      final b = monthBounds('2026-10');
      expect(b.from, '2026-10-01');
      expect(b.to, '2026-10-31');
    });

    test('handles a shorter month', () {
      expect(monthBounds('2026-02').to, '2026-02-28');
    });

    test('handles February in a leap year', () {
      expect(monthBounds('2028-02').to, '2028-02-29');
    });

    test('handles December without rolling into January', () {
      final b = monthBounds('2026-12');
      expect(b.from, '2026-12-01');
      expect(b.to, '2026-12-31');
    });

    test('every day in the month falls inside the bounds', () {
      // The real failure mode: a short month silently excludes a late entry.
      final b = monthBounds('2026-02');
      final entries = [expense('2026-02-28', 'Rent', 1000)];

      expect(spentInCategory(entries, 'Rent', b.from, b.to), 1000);
      expect(otherTotalBetween(entries, b.from, b.to), 1000);
    });
  });

  group('stored shape', () {
    test('an entry survives being written and read back', () {
      final original = expense('2026-10-05', 'Gas', 2500, title: 'Rickshaw');

      final restored = CloudOtherExpense.fromDoc('o1', {
        ...original.toDoc(),
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5)),
      });

      expect(restored.date, '2026-10-05');
      expect(restored.category, 'Gas');
      expect(restored.amount, 2500);
      expect(restored.title, 'Rickshaw');
    });

    test('a missing category falls back to Other rather than blank', () {
      // A blank category would be invisible in the category list while still
      // counting toward totals.
      final restored = CloudOtherExpense.fromDoc('o1', {
        'date': '2026-10-05',
        'amount': 100,
      });

      expect(restored.category, 'Other');
    });

    test('a malformed amount reads as zero, not a crash', () {
      final restored = CloudOtherExpense.fromDoc('o1', {
        'date': '2026-10-05',
        'category': 'Gas',
        'amount': 'not a number',
      });

      expect(restored.amount, 0);
    });

    test('a category round-trips through its stored shape', () {
      final original = CloudOtherCategory(
        name: 'Gas',
        budget: 5000,
        createdAt: DateTime(2026, 10, 1),
      );

      final restored = CloudOtherCategory.fromEntry('Gas', {
        ...original.toDoc(),
        'createdAt': Timestamp.fromDate(original.createdAt!),
      });

      expect(restored.name, 'Gas');
      expect(restored.budget, 5000);
    });

    test('a malformed category entry still yields a usable category', () {
      final restored = CloudOtherCategory.fromEntry('Gas', 'not a map');

      expect(restored.name, 'Gas',
          reason: 'the key is the name, so the row is not blank');
      expect(restored.budget, 0);
    });
  });
}
