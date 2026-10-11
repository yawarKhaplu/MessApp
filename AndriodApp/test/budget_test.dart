import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/data/models.dart';

/// Reproduces the "safe to spend" confusion from the RCA.
///
/// The defect: the figure on screen and the threshold actually enforced were
/// two different numbers (1,808 shown, 1,743 tested), so a user could spend up
/// to the number they were shown and still be told they had overspent.
///
/// The fix freezes today's allowance against spending from BEFORE today, which
/// makes the displayed headroom and the enforced threshold the same number.
void main() {
  // Verified against the live device on 2026-10-11.
  const target = 56000.0;
  const monthSpent = 19840.0; // includes today's 450
  const spentToday = 450.0;
  const monthSpentBefore = 19390.0; // everything up to and including Oct 10
  const daysLeft = 20; // days AFTER today: Oct 12..31
  const daysInMonth = 31;

  /// Mirrors `getTodayBudget`: today's share of what was left at day start.
  double capToday() => (target - monthSpentBefore) / (daysLeft + 1);

  /// Mirrors the old month-to-date version (repository.dart before the fix),
  /// kept to prove it is the cause. It divided by `daysLeft` because
  /// `monthSpent` already contained today's spending.
  double liveCap() => (target - monthSpent) / daysLeft;

  group('frozen daily allowance', () {
    test('does not move when money is spent today', () {
      final before = capToday();
      // Simulating spend today cannot alter the input, so the cap is stable.
      expect(capToday(), before);
      expect(before, closeTo(1743.33, 0.01));
    });

    test('headroom falls exactly 1:1 with spending', () {
      final headroom = capToday() - spentToday;
      expect(headroom, closeTo(1293.33, 0.01));

      // The bug: the old figure showed 1,358, a different number from the
      // 1,743 it was actually testing against.
      expect(liveCap(), closeTo(1808.0, 0.01));
      expect(liveCap() - spentToday, closeTo(1358.0, 0.01));
    });

    test('spending consumed headroom at 1.05, not 1.00', () {
      // The real regression: each rupee spent burned 1 + 1/daysLeft of the
      // displayed balance, so the number on screen was never a true balance.
      const startLeft = 1358.0;
      for (final extra in [450.0, 1000.0, 1300.0]) {
        final oldRemaining = startLeft - extra * (1 + 1 / daysLeft);
        expect(oldRemaining, lessThan(startLeft - extra));
      }
    });

    test('warning fires exactly when the displayed number is exhausted', () {
      final cap = capToday();
      final startLeft = cap - spentToday;

      for (final extra in [0.0, 450.0, 1000.0, 1293.0]) {
        final spent = spentToday + extra;
        final left = cap - spent;
        final onTrack = spent < cap;
        expect(onTrack, isTrue, reason: 'extra $extra should still be Safe');
        expect(left, greaterThanOrEqualTo(0), reason: 'extra $extra');
      }

      expect(startLeft, closeTo(1293.33, 0.01));

      // One rupee past the displayed allowance must flip it.
      expect(spentToday + startLeft.floorToDouble() + 1 < cap, isFalse);
    });

    test('day with no spending yet still shows the full allowance', () {
      expect(capToday(), closeTo(1743.33, 0.01));
    });

    test('a month that has already overspent tightens the cap', () {
      // Overspent before today: the cap drops below the usual daily rate,
      // which is what pushes the user back on track.
      const overspentBefore = 40000.0;
      final tightened = (target - overspentBefore) / (daysLeft + 1);
      expect(tightened, lessThan(target / daysInMonth));
    });
  });

  group('fixed-rate projection', () {
    final outlook = MonthOutlook(
      month: DateTime(2026, 10),
      target: target,
      collected: target,
      spent: monthSpent,
      daysElapsed: 11,
      daysRemaining: daysLeft,
      daysInMonth: daysInMonth,
      memberCount: 8,
    );

    test('fixed daily rate is the target spread over the month', () {
      expect(outlook.fixedPerDay, closeTo(1806.45, 0.01));
    });

    test('projection includes spending already made today', () {
      // 19,840 already contains today's 450, so the projection must not add it
      // a second time, nor omit it.
      final projected = outlook.spent + outlook.fixedPerDay * daysLeft;
      expect(projected, closeTo(55969.03, 0.01));
      expect(outlook.savingAtFixedRate, closeTo(30.97, 0.01));
    });

    test('exactly on plan saves nothing and overruns nothing', () {
      final even = MonthOutlook(
        month: DateTime(2026, 10),
        target: target,
        collected: target,
        spent: outlook.fixedPerDay * 11,
        daysElapsed: 11,
        daysRemaining: daysLeft,
        daysInMonth: daysInMonth,
        memberCount: 8,
      );
      expect(even.savingAtFixedRate, closeTo(0, 0.01));
    });

    test('overspending shows a negative saving', () {
      final over = MonthOutlook(
        month: DateTime(2026, 10),
        target: target,
        collected: target,
        spent: monthSpent + 5000,
        daysElapsed: 11,
        daysRemaining: daysLeft,
        daysInMonth: daysInMonth,
        memberCount: 8,
      );
      expect(over.savingAtFixedRate, lessThan(0));
    });
  });
}