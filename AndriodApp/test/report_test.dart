import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/collection_cloud_service.dart';
import 'package:messapp/services/expense_cloud_service.dart';
import 'package:messapp/services/mess_cloud_service.dart';
import 'package:messapp/services/other_expense_cloud_service.dart';
import 'package:messapp/services/report_cloud_service.dart';

/// The reports used to ask SQLite for each figure separately. They now work from
/// one bundle assembled in Dart, because a Firestore query cannot be proven
/// against a rule that reads another document — so there is no way to ask for
/// "totals grouped by member" at all.
///
/// That makes the arithmetic here the report, not a helper to it. These tests
/// cover it, with the figures that would quietly mislead somebody if they were
/// wrong.
void main() {
  CloudExpense meal(
    String date,
    String menu,
    double total, {
    String cook = 'ali@x.com',
    String? recordedBy = 'ali@x.com',
    List<CloudExpenseItem> items = const [],
  }) =>
      CloudExpense(
        id: '$date-$menu',
        date: date,
        menuName: menu,
        total: total,
        cookEmail: cook,
        recordedBy: recordedBy,
        items: items,
      );

  CloudOtherExpense other(String date, String category, double amount) =>
      CloudOtherExpense(
        id: '$date-$category',
        date: date,
        category: category,
        amount: amount,
      );

  ReportBundle bundle({
    List<CloudExpense> meals = const [],
    List<CloudOtherExpense> other = const [],
    List<MemberCollection> collections = const [],
    List<CloudOtherCategory> categories = const [],
  }) =>
      ReportBundle(
        messId: 'm1',
        roster: const [
          MessMember(uid: 'a', email: 'ali@x.com', name: 'Ali'),
          MessMember(uid: 's', email: 'sara@x.com', name: 'Sara'),
        ],
        meals: meals,
        other: other,
        collections: collections,
        categories: categories,
      );

  group('a single day', () {
    final b = bundle(
      meals: [
        meal('2026-10-12', 'Pulao', 300),
        meal('2026-10-12', 'Nasta', 100),
        meal('2026-10-11', 'Karahi', 450),
      ],
      other: [other('2026-10-12', 'Gas', 200)],
    );

    test('food counts only that day', () {
      expect(b.dayFoodTotal('2026-10-12'), 400);
    });

    test('other expenses are counted separately', () {
      expect(b.dayTotals('2026-10-12').other, 200);
    });

    test('the day total is food plus other', () {
      expect(b.dayTotal('2026-10-12'), 600);
    });

    test('the neighbouring day is not swept in', () {
      expect(b.dayTotal('2026-10-11'), 450);
    });

    test('a day with nothing on it is zero', () {
      expect(b.dayTotal('2026-10-20'), 0);
    });
  });

  group('ranges', () {
    final b = bundle(
      meals: [
        meal('2026-10-01', 'Pulao', 100),
        meal('2026-10-31', 'Karahi', 300),
        meal('2026-11-01', 'Pulao', 999),
      ],
      other: [other('2026-10-15', 'Rent', 500)],
    );

    test('both ends are included', () {
      // An off-by-one here would drop the first or last day of a month, which is
      // exactly the day a bill lands on.
      expect(b.foodBetween('2026-10-01', '2026-10-31'), 400);
    });

    test('the next month is left out', () {
      expect(b.foodBetween('2026-10-01', '2026-10-31'), isNot(999));
    });

    test('a whole month of other expenses is included', () {
      expect(b.otherBetween('2026-10-01', '2026-10-31'), 500);
    });

    test('an average divides by every day, not only days with entries', () {
      // Three entries across two days is not 200/day for the month. Counting only
      // days with records would call a quiet month as expensive as a busy one.
      final one = bundle(meals: [meal('2026-10-01', 'Pulao', 300)]);
      expect(one.averagePerDay('2026-10-01', '2026-10-31'), closeTo(300 / 31, 0.001));
    });

    test('an empty range averages zero rather than dividing by nothing', () {
      final empty = bundle();
      expect(empty.averagePerDay('2026-10-01', '2026-10-31'), 0);
    });
  });

  group('grouped by cook', () {
    final b = bundle(
      meals: [
        meal('2026-10-01', 'Pulao', 100, cook: 'ali@x.com'),
        meal('2026-10-02', 'Karahi', 250, cook: 'ali@x.com'),
        meal('2026-10-03', 'Nasta', 50, cook: 'sara@x.com'),
      ],
    );

    test('largest spender is first', () {
      final rows = b.byCook('2026-10-01', '2026-10-31');
      expect(rows.first.label, 'Ali');
      expect(rows.first.total, 350);
    });

    test('each row carries its own entry count', () {
      final rows = b.byCook('2026-10-01', '2026-10-31');
      expect(rows.first.entries, 2);
      expect(rows.last.entries, 1);
    });

    test('names come from the roster, not the address', () {
      final rows = b.byCook('2026-10-01', '2026-10-31');
      expect(rows.map((r) => r.label), containsAll(['Ali', 'Sara']));
    });

    test('one person cannot appear twice under two spellings', () {
      final mixed = bundle(
        meals: [
          meal('2026-10-01', 'Pulao', 100, cook: 'Ali@X.com'),
          meal('2026-10-02', 'Pulao', 100, cook: 'ali@x.com'),
        ],
      );

      final rows = mixed.byCook('2026-10-01', '2026-10-31');
      expect(rows, hasLength(1));
      expect(rows.first.total, 200);
    });

    test('an address with nobody on it still gets a row', () {
      final stray = bundle(
        meals: [meal('2026-10-01', 'Pulao', 100, cook: 'gone@x.com')],
      );

      final rows = stray.byCook('2026-10-01', '2026-10-31');
      expect(rows, hasLength(1), reason: 'money spent must still be accounted for');
    });

    test('nothing spent gives no rows', () {
      expect(bundle().byCook('2026-10-01', '2026-10-31'), isEmpty);
    });
  });

  group('grouped by item', () {
    test('the same item on three days is one row', () {
      final b = bundle(
        meals: [
          meal('2026-10-01', 'A', 100,
              items: [const CloudExpenseItem(id: 'i1', name: 'Rice', price: 100)]),
          meal('2026-10-02', 'B', 150,
              items: [const CloudExpenseItem(id: 'i2', name: 'Rice', price: 150)]),
        ],
      );

      final rows = b.byItem('2026-10-01', '2026-10-31');
      expect(rows, hasLength(1));
      expect(rows.first.total, 250);
      expect(rows.first.entries, 2);
    });

    test('items are matched regardless of case', () {
      final b = bundle(
        meals: [
          meal('2026-10-01', 'A', 100,
              items: [const CloudExpenseItem(id: 'i1', name: 'Rice', price: 100)]),
          meal('2026-10-02', 'B', 50,
              items: [const CloudExpenseItem(id: 'i2', name: 'rice', price: 50)]),
        ],
      );

      expect(b.byItem('2026-10-01', '2026-10-31'), hasLength(1));
    });
  });

  group('collections', () {
    MemberCollection withPayments(
      String email,
      String month,
      double due,
      List<double> paid,
    ) =>
        MemberCollection(
          email: email,
          month: month,
          amountDue: due,
          payments: [
            for (var i = 0; i < paid.length; i++)
              CloudPayment(
                id: 'p$i',
                amount: paid[i],
                date: DateTime(2026, 10, 5 + i),
              ),
          ],
        );

    test('what has been paid in is totalled', () {
      final b = bundle(collections: [
        withPayments('ali@x.com', '2026-10', 1000, [400]),
        withPayments('sara@x.com', '2026-10', 1000, [600]),
      ]);

      expect(b.collectedBetween('2026-10-01', '2026-10-31').collected, 1000);
    });

    test('what is still owed is summed per member, not netted', () {
      // Ali owes 600, Sara has overpaid by 200. The still-due figure must stay
      // 600: one person paying extra must never make the app claim Ali owes less.
      final b = bundle(collections: [
        withPayments('ali@x.com', '2026-10', 1000, [400]),
        withPayments('sara@x.com', '2026-10', 1000, [1200]),
      ]);

      final t = b.collectedBetween('2026-10-01', '2026-10-31');
      expect(t.stillDue, 600);
      expect(t.credit, 200);
    });

    test('a payment dated outside the range is left out', () {
      final b = bundle(collections: [
        MemberCollection(
          email: 'ali@x.com',
          month: '2026-10',
          amountDue: 1000,
          payments: [
            CloudPayment(id: 'p', amount: 300, date: DateTime(2026, 9, 20)),
            CloudPayment(id: 'q', amount: 700, date: DateTime(2026, 10, 20)),
          ],
        ),
      ]);

      expect(b.collectedBetween('2026-10-01', '2026-10-31').collected, 700);
    });

    test('a payment with no readable date still counts as money in', () {
      // Leaving it out would understate what has been collected, and there is
      // nothing to date it against.
      final b = bundle(collections: [
        MemberCollection(
          email: 'ali@x.com',
          month: '2026-10',
          amountDue: 1000,
          payments: [const CloudPayment(id: 'p', amount: 250, date: null)],
        ),
      ]);

      expect(b.collectedBetween('2026-10-01', '2026-10-31').collected, 250);
    });

    test('no collections is zero, not an error', () {
      final t = bundle().collectedBetween('2026-10-01', '2026-10-31');
      expect(t.collected, 0);
      expect(t.stillDue, 0);
    });
  });

  group('the month, and where it is heading', () {
    final now = DateTime(2026, 10, 12);

    test('a finished month counts every one of its days', () {
      // Comparing months as text, so a past month reports itself as complete
      // rather than running its counters backwards.
      final f = bundle().monthFigures('2026-09', now);
      expect(f.daysInMonth, 30);
      expect(f.daysElapsed, 30);
      expect(f.daysRemaining, 0);
    });

    test('the current month counts up to today', () {
      final f = bundle().monthFigures('2026-10', now);
      expect(f.daysElapsed, 12);
      expect(f.daysRemaining, 19);
      expect(f.daysInMonth, 31);
    });

    test('a future month has not started', () {
      final f = bundle().monthFigures('2026-11', now);
      expect(f.daysElapsed, 0);
      expect(f.daysRemaining, 0);
    });

    test('food and other spending are kept apart', () {
      final b = bundle(
        meals: [meal('2026-10-05', 'Pulao', 300)],
        other: [other('2026-10-05', 'Gas', 200)],
      );

      final f = b.monthFigures('2026-10', now);
      expect(f.foodSpent, 300);
      expect(f.otherSpent, 200);
      expect(f.spent, 500);
    });

    test('an unpaid allowance still counts as committed', () {
      // Rent that is due but not yet entered still has to be paid, so the month
      // has to show it.
      final b = bundle(
        categories: const [
          CloudOtherCategory(name: 'Rent', budget: 25000),
          CloudOtherCategory(name: 'Gas', budget: 3000),
        ],
      );

      final f = b.monthFigures('2026-10', now);
      expect(f.expectedOther, 28000);
      expect(f.committed, 28000);
    });

    test('committed never goes negative', () {
      final b = bundle(
        categories: const [CloudOtherCategory(name: 'Gas', budget: 1000)],
        other: [other('2026-10-05', 'Gas', 4000)],
      );

      final f = b.monthFigures('2026-10', now);
      expect(f.committed, 0, reason: 'an over-spent allowance is not negative');
    });

    test('a month with no spending projects to nothing', () {
      final f = bundle().monthFigures('2026-10', now);
      expect(f.projected, 0);
    });

    test('the projection follows the current rate', () {
      final b = bundle(meals: [meal('2026-10-05', 'Pulao', 1200)]);
      final f = b.monthFigures('2026-10', now);

      // 1200 over 12 days so far, carried across 31.
      expect(f.projected, closeTo(1200 / 12 * 31, 0.01));
    });
  });

  group('names', () {
    test('a real name is found', () {
      expect(bundle().nameOf('ali@x.com'), 'Ali');
    });

    test('the address is matched however it is capitalised', () {
      expect(bundle().nameOf('ALI@X.com'), 'Ali');
    });

    test('a roster entry whose name is really the address gives nothing', () {
      // Otherwise the report would print "ali@x.com" in the name column.
      final b = ReportBundle(
        messId: 'm1',
        roster: const [MessMember(uid: 'a', email: 'ali@x.com', name: 'ali@x.com')],
      );
      expect(b.nameOf('ali@x.com'), isNull);
    });

    test('somebody who has left gives nothing rather than a blank', () {
      expect(bundle().nameOf('gone@x.com'), isNull);
    });
  });

  group('category budgets', () {
    test('carry the allowance and what was spent', () {
      final b = bundle(
        categories: const [CloudOtherCategory(name: 'Gas', budget: 3000)],
        other: [other('2026-10-05', 'Gas', 1200)],
      );

      final rows = b.categoryBudgets('2026-10');
      expect(rows, hasLength(1));
      expect(rows.first.budget, 3000);
      expect(rows.first.spent, 1200);
      expect(rows.first.remaining, 1800);
    });

    test('spending in another month is not counted against this one', () {
      final b = bundle(
        categories: const [CloudOtherCategory(name: 'Gas', budget: 3000)],
        other: [other('2026-09-05', 'Gas', 1200)],
      );

      expect(b.categoryBudgets('2026-10').first.spent, 0);
    });
  });

  group('an empty bundle', () {
    test('answers zero everywhere rather than failing', () {
      // Reports render while the mess is still loading; showing zeroes is honest,
      // an exception is not.
      final b = ReportBundle.empty();

      expect(b.dayTotal('2026-10-12'), 0);
      expect(b.spentBetween('2026-10-01', '2026-10-31'), 0);
      expect(b.averagePerDay('2026-10-01', '2026-10-31'), 0);
      expect(b.byCook('2026-10-01', '2026-10-31'), isEmpty);
      expect(b.byMenu('2026-10-01', '2026-10-31'), isEmpty);
      expect(b.byItem('2026-10-01', '2026-10-31'), isEmpty);
      expect(b.categoryBudgets('2026-10'), isEmpty);
      expect(b.collectedBetween('2026-10-01', '2026-10-31').collected, 0);
      expect(b.isEmpty, isTrue);
    });
  });
}
