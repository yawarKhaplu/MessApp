import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/data/models.dart' show dayKey, monthKey;
import 'package:messapp/services/expense_cloud_service.dart';

/// The app partitions expenses by month and refers to individual days by a
/// separate key. The two differ only by three characters, which is enough for
/// the wrong one to compile, save, and quietly file a whole month of meals under
/// one day.
///
/// These tests exist to pin the difference down, because the mistake is
/// invisible until somebody reads a month of history as if it were a day.
void main() {
  final day = DateTime(2026, 10, 12);

  group('the two keys', () {
    test('a day key is ten characters and a month key is seven', () {
      expect(dayKey(day), '2026-10-12');
      expect(monthKey(day), '2026-10');
    });

    test('the month key is the first part of the day key', () {
      // Why the two are so easy to swap: one is literally the prefix of the
      // other, so a substring of the wrong length still looks plausible.
      expect(monthKey(day), dayKey(day).substring(0, 7));
    });

    test('they are never equal', () {
      expect(monthKey(day) == dayKey(day), isFalse);
    });
  });

  group('a month key is not usable as a day', () {
    // This is the exact shape that reaches the app: a value built by monthKey
    // being handed to something that needs dayKey.
    final monthOnly = monthKey(day);

    test('it selects nothing from a range that should select the day', () {
      final entries = [
        CloudExpense(
          id: 'e1',
          date: dayKey(day),
          menuName: 'Pulao',
          total: 300,
          cookEmail: 'ali@x.com',
        ),
      ];

      expect(totalBetween(entries, monthOnly, monthOnly).entries, 0,
          reason: 'a month key is shorter than any day, so nothing can fall '
              'inside it');
    });

    test('and would silently drop a real day from the same figures', () {
      final entries = [
        CloudExpense(
          id: 'e1',
          date: dayKey(day),
          menuName: 'Pulao',
          total: 300,
          cookEmail: 'ali@x.com',
        ),
        CloudExpense(
          id: 'e2',
          date: '2026-10-13',
          menuName: 'Karahi',
          total: 450,
          cookEmail: 'sara@x.com',
        ),
      ];

      expect(totalBetween(entries, dayKey(day), dayKey(day)).total, 300);
      expect(totalBetween(entries, monthOnly, monthOnly).total, 0);
    });
  });

  group('monthOf takes a day and returns its month', () {
    test('reduces a day key to the month it partitions under', () {
      expect(monthOf('2026-10-12'), '2026-10');
    });

    test('is what a caller must apply before asking for a month', () {
      // The mistake avoided: passing the day straight to the month lookup.
      final today = DateTime.now();
      expect(
        monthOf(dayKey(today)),
        monthKey(today),
        reason: 'the month partition and the derived month must agree, '
            'otherwise the entry is saved where no query will find it',
      );
    });

    test('still works if handed a month key, which is why it hid the bug', () {
      // monthOf truncates to seven characters, so a month key passes through
      // unchanged and gives the right answer. That is precisely why the wrong
      // key was not caught earlier.
      expect(monthOf(monthKey(day)), '2026-10');
    });
  });

  group('round-tripping a saved entry', () {
    test('keeps the day so it can be found again by day', () {
      final entry = CloudExpense(
        id: 'e1',
        date: dayKey(day),
        menuName: 'Pulao',
        total: 100,
        cookEmail: 'ali@x.com',
      );

      final doc = entry.toDoc();

      expect(doc['date'], '2026-10-12');
      expect(doc['date'], isNot('2026-10'));
    });
  });
}
