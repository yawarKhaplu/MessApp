import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/collection_cloud_service.dart';

/// Collections are shared, so the arithmetic that decides what a member owes
/// must be right in every direction: nothing set, partly paid, exactly paid and
/// overpaid. These pin that down, because a wrong total would show one person a
/// figure the rest of the mess disagrees with.
void main() {
  CloudPayment payment(double amount) =>
      CloudPayment(id: 'p', amount: amount, date: DateTime(2026, 10, 5));

  MemberCollection withPayments(double due, List<double> amounts) =>
      MemberCollection(
        email: 'a@x.com',
        month: '2026-10',
        amountDue: due,
        payments: [
          for (final a in amounts) payment(a),
        ],
      );

  group('monthly collection', () {
    test('nothing set means nothing is owed and nothing is settled', () {
      final c = withPayments(0, const []);

      expect(c.amountDue, 0);
      expect(c.paid, 0);
      expect(c.remaining, 0);
      expect(c.hasNoShare, isTrue);
      // Crucially not "paid": the share was never set, which is different.
      expect(c.isSettled, isFalse);
    });

    test('no payments leaves the whole share outstanding', () {
      final c = withPayments(2000, const []);

      expect(c.paid, 0);
      expect(c.remaining, 2000);
      expect(c.isSettled, isFalse);
    });

    test('a part payment leaves the rest outstanding', () {
      final c = withPayments(2000, [500]);

      expect(c.paid, 500);
      expect(c.remaining, 1500);
      expect(c.isSettled, isFalse);
    });

    test('paying exactly the share settles it', () {
      final c = withPayments(2000, [2000]);

      expect(c.remaining, 0);
      expect(c.isSettled, isTrue);
    });

    test('paying in several instalments settles it', () {
      final c = withPayments(2000, [500, 700, 800]);

      expect(c.paid, 2000);
      expect(c.remaining, 0);
      expect(c.isSettled, isTrue);
    });

    test('paying extra goes negative, which is credit not a negative bill', () {
      final c = withPayments(2000, [2500]);

      expect(c.remaining, -500);
      // Settled, and the extra is visible as a negative remaining.
      expect(c.isSettled, isTrue);
    });

    test('totals add up across members', () {
      // What the Collection summary shows, worked out the same way.
      final members = [
        withPayments(2000, [2000]), // settled
        withPayments(2000, [500]), // 1500 left
        withPayments(1500, const []), // 1500 left
      ];

      final totalDue =
          members.fold<double>(0, (s, c) => s + c.amountDue);
      final totalPaid = members.fold<double>(0, (s, c) => s + c.paid);
      var stillDue = 0.0;
      var credit = 0.0;
      for (final c in members) {
        if (c.amountDue > c.paid) {
          stillDue += c.amountDue - c.paid;
        } else {
          credit += c.paid - c.amountDue;
        }
      }

      expect(totalDue, 5500);
      expect(totalPaid, 2500);
      expect(stillDue, 3000);
      expect(credit, 0);
    });
  });

  group('document keys', () {
    test('are keyed by email and month', () {
      expect(collectionDocId('Ali@X.com', '2026-10'),
          'ali@x.com__2026-10');
    });

    test('are stable regardless of the email casing used', () {
      // Two people typing the same address differently must land on one
      // document, or a payment would vanish from the mess's view.
      expect(collectionDocId('Ali@X.com', '2026-10'),
          collectionDocId('ali@x.com', '2026-10'));
    });

    test('keep months apart', () {
      expect(collectionDocId('a@x.com', '2026-10'),
          isNot(collectionDocId('a@x.com', '2026-11')));
    });

    test('ignore surrounding whitespace', () {
      expect(collectionDocId('  ali@x.com  ', '2026-10'),
          collectionDocId('ali@x.com', '2026-10'));
    });
  });
}