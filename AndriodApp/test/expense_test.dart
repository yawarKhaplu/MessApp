import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/expense_cloud_service.dart';

/// Expenses are the mess's record of what it spent. These tests cover the
/// arithmetic and the stored shape, because a wrong total would show one person
/// a figure the rest of the mess disagrees with — and that is the whole point
/// of moving them to shared storage.
void main() {
  CloudExpenseItem item(String name, double qty, double price) =>
      CloudExpenseItem(id: name, name: name, quantity: qty, price: price);

  CloudExpense expense(
    String date,
    String menu, {
    String cook = 'ali@x.com',
    List<CloudExpenseItem> items = const [],
    double? total,
    DateTime? createdAt,
  }) =>
      CloudExpense(
        id: 'e1',
        date: date,
        menuName: menu,
        cookEmail: cook,
        recordedBy: 'owner@x.com',
        createdAt: createdAt,
        items: items,
        total: total ??
            items.fold<double>(0, (s, i) => s + i.lineTotal),
      );

  group('expense items', () {
    test('line total is quantity times price', () {
      expect(item('Rice', 2, 50).lineTotal, 100);
      expect(item('Salt', 0.5, 20).lineTotal, 10);
    });

    test('a missing quantity still counts as one, not zero', () {
      // A mis-typed quantity must not silently make the whole meal free.
      const i = CloudExpenseItem(id: 'x', name: 'Rice');
      expect(i.quantity, 1);
    });
  });

  group('expense totals', () {
    test('sums a set of entries', () {
      final t = totalOf([
        expense('2026-10-01', 'Pulao', items: [item('Rice', 1, 100)]),
        expense('2026-10-02', 'Karahi', items: [item('Mutton', 1, 450)]),
      ]);

      expect(t.total, 550);
      expect(t.entries, 2);
    });

    test('an empty list is zero, not an error', () {
      final t = totalOf(const []);

      expect(t.total, 0);
      expect(t.entries, 0);
    });

    test('totals add together', () {
      final a = ExpenseTotals(total: 100, entries: 2);
      final b = ExpenseTotals(total: 50, entries: 1);

      expect((a + b).total, 150);
      expect((a + b).entries, 3);
    });
  });

  group('date ranges', () {
    final entries = [
      expense('2026-10-01', 'Pulao', items: [item('Rice', 1, 100)]),
      expense('2026-10-15', 'Karahi', items: [item('Mutton', 1, 300)]),
      expense('2026-11-01', 'Pulao', items: [item('Rice', 1, 200)]),
    ];

    test('counts only what falls inside the range', () {
      final t = totalBetween(entries, '2026-10-01', '2026-10-31');

      expect(t.total, 400);
      expect(t.entries, 2);
    });

    test('the bounds are included on both ends', () {
      // An off-by-one here would silently drop the first or last day of a month.
      final t = totalBetween(entries, '2026-10-01', '2026-10-15');

      expect(t.entries, 2);
      expect(t.total, 400);
    });

    test('a single day range picks up only that day', () {
      final t = totalBetween(entries, '2026-10-15', '2026-10-15');

      expect(t.entries, 1);
      expect(t.total, 300);
    });

    test('an empty range is zero', () {
      final t = totalBetween(entries, '2026-01-01', '2026-01-31');

      expect(t.total, 0);
      expect(t.entries, 0);
    });
  });

  group('splitting a total across items', () {
    test('gives fractions of the whole', () {
      final split = splitByItem([
        item('Rice', 1, 300),
        item('Meat', 1, 100),
      ]);

      expect(split['rice'], closeTo(0.75, 0.0001));
      expect(split['meat'], closeTo(0.25, 0.0001));
    });

    test('fractions add up to one', () {
      final split = splitByItem([
        item('Rice', 1, 300),
        item('Meat', 1, 100),
        item('Oil', 2, 50),
      ]);

      final sum = split.values.fold<double>(0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 0.0001));
    });

    test('repeats of one item are combined', () {
      final split = splitByItem([
        item('Salt', 1, 25),
        item('salt', 1, 75),
      ]);

      expect(split.length, 1, reason: 'same item twice must not split twice');
      expect(split['salt'], closeTo(1.0, 0.0001));
    });

    test('zero-priced items are ignored rather than dividing by them', () {
      final split = splitByItem([
        item('Rice', 1, 100),
        item('Free', 1, 0),
      ]);

      expect(split.containsKey('free'), isFalse);
      expect(split['rice'], closeTo(1.0, 0.0001));
    });

    test('nothing to split from returns nothing', () {
      expect(splitByItem(const []), isEmpty);
      expect(splitByItem([item('Free', 1, 0)]), isEmpty);
    });
  });

  group('stored shape', () {
    test('an entry survives being written and read back', () {
      // What is saved must be what is read, or a meal quietly loses its items.
      final original = expense(
        '2026-10-05',
        'Pulao',
        items: [item('Rice', 2, 40), item('Masala', 1, 20)],
        createdAt: DateTime(2026, 10, 5, 19),
      );

      final doc = {
        ...original.toDoc(),
        'createdAt': Timestamp.fromDate(original.createdAt!),
      };

      final restored = CloudExpense.fromDoc(original.id, doc);

      expect(restored.date, '2026-10-05');
      expect(restored.menuName, 'Pulao');
      expect(restored.total, 100);
      expect(restored.cookEmail, 'ali@x.com');
      expect(restored.recordedBy, 'owner@x.com');
      expect(restored.items, hasLength(2));
      expect(restored.items.first.name, 'Rice');
      expect(restored.items.first.quantity, 2);
      expect(restored.items.first.price, 40);
    });

    test('the cook is stored lowercased for matching', () {
      final saved = expense('2026-10-05', 'Pulao', cook: 'Ali@X.com').toDoc();

      expect(saved['cookEmail'], 'ali@x.com',
          reason: 'the rules compare against the lowercased token email');
    });

    test('a malformed entry does not lose the rest', () {
      final restored = CloudExpense.fromDoc('e1', {
        'date': '2026-10-05',
        'menuName': 'Pulao',
        'total': 100,
        'cookEmail': 'ali@x.com',
        'items': {
          'a': {'name': 'Rice', 'quantity': 1, 'price': 60},
          'b': 'not a map',
        },
      });

      expect(restored.items, hasLength(1));
      expect(restored.items.first.name, 'Rice');
    });

    test('an entry with no items still reads back', () {
      final restored = CloudExpense.fromDoc('e1', {
        'date': '2026-10-05',
        'menuName': 'Pulao',
        'total': 0,
        'cookEmail': 'ali@x.com',
      });

      expect(restored.items, isEmpty);
      expect(restored.total, 0);
    });
  });

  group('month keys', () {
    test('takes the year and month from a day', () {
      expect(monthOf('2026-10-05'), '2026-10');
      expect(monthOf('2026-01-31'), '2026-01');
    });

    test('crossing a year boundary stays in the right month', () {
      expect(monthOf('2026-12-31'), '2026-12');
      expect(monthOf('2027-01-01'), '2027-01');
    });
  });

  group('generated ids', () {
    test('are unique even within the same microsecond', () {
      // A collision would silently drop a meal, which is the worst kind of bug
      // to notice weeks later.
      final ids = List.generate(200, (_) => newExpenseId());

      expect(ids.toSet().length, ids.length);
    });

    test('items and expenses cannot collide with each other', () {
      expect(newExpenseId(), isNot(newExpenseItemId()));
    });
  });
}