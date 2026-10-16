import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/mess_cloud_service.dart';

/// Who may add an expense: the owner always, and a member only on the day the
/// cooking turn is theirs.
///
/// These tests exist because the check guards something the mess would disagree
/// about — one person logging meals that another cooked. The wording of the
/// refusal matters as much as the refusal itself, so it is asserted too.
void main() {
  /// Builds a mess whose turn today belongs to [cook].
  ///
  /// The anchor is [today] with [cook] first in the order, so the schedule puts
  /// [cook] on today rather than having to be worked out in the test.
  Mess messWith({
    required String role,
    required String cookEmail,
    List<String>? order,
  }) {
    final today = DateTime.now();
    final key = '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final people = order ?? [cookEmail];
    return Mess(
      id: 'm1',
      name: 'Test Mess',
      ownerUid: 'owner-uid',
      joinCode: 'CODE',
      myRole: role,
      members: [
        for (final e in people) MessMember(uid: 'uid-$e', email: e, name: e),
      ],
      rotation: {'anchorDate': key, 'order': people, 'manual': true},
    );
  }

  String todayKey() {
    final d = DateTime.now();
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String yesterdayKey() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String tomorrowKey() {
    final d = DateTime.now().add(const Duration(days: 1));
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  group('the owner', () {
    final mess = messWith(role: 'owner', cookEmail: 'ali@x.com');

    test('may record their own turn', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'owner@x.com',
          cookEmail: 'owner@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });

    test('may record on somebody else\'s behalf', () {
      // The owner is the one who fixes a meal somebody forgot to enter, so this
      // has to work even though the cook is not the owner.
      expect(
        recordRefusal(
          mess: mess,
          email: 'owner@x.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });

    test('may backdate an entry to correct a mistake', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'owner@x.com',
          cookEmail: 'ali@x.com',
          date: yesterdayKey(),
        ),
        isNull,
        reason: 'the owner corrects records; members may not',
      );
    });
  });

  group('a member on turn', () {
    final mess = messWith(role: 'member', cookEmail: 'ali@x.com');

    test('may record today\'s meal', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });

    test('the address is matched however it is capitalised', () {
      // Google returns the account's email exactly as stored, so a capitalised
      // address must still be recognised or the person cannot record their turn.
      expect(
        recordRefusal(
          mess: mess,
          email: 'Ali@X.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });

    test('may record even with the cook written differently', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ALI@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });
  });

  group('a member not on turn', () {
    final mess = messWith(
      role: 'member',
      cookEmail: 'ali@x.com',
      order: ['ali@x.com', 'sara@x.com'],
    );

    test('may not record when it is somebody else\'s turn', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'sara@x.com',
          date: todayKey(),
        ),
        RecordRefusal.notTheirTurn,
      );
    });

    test('may not record their own meal on another person\'s turn', () {
      // The same refusal either way: naming yourself does not buy a turn.
      expect(
        recordRefusal(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'sara@x.com',
          date: todayKey(),
        ),
        isNotNull,
      );
    });

    test('may not nominate the person who is cooking to get around it', () {
      // Otherwise the turn check would be satisfied by writing somebody else's
      // name in the cook field.
      expect(
        recordRefusal(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        RecordRefusal.notTheirCook,
      );
    });

    test('may not backdate a meal to a turn they did not have', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'sara@x.com',
          date: yesterdayKey(),
        ),
        RecordRefusal.notTheirTurn,
      );
    });

    test('may not record a meal for tomorrow', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'sara@x.com',
          date: tomorrowKey(),
        ),
        isNotNull,
      );
    });
  });

  group('nobody signed in', () {
    final mess = messWith(role: 'member', cookEmail: 'ali@x.com');

    test('is refused rather than treated as the owner', () {
      // An empty address must not fall through to a permissive branch.
      expect(
        recordRefusal(
          mess: mess,
          email: null,
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        RecordRefusal.notSignedIn,
      );
      expect(
        recordRefusal(
          mess: mess,
          email: '   ',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        RecordRefusal.notSignedIn,
      );
    });
  });

  group('the yes/no form agrees with the refusal', () {
    test('agrees for the person on turn', () {
      final mess = messWith(role: 'member', cookEmail: 'ali@x.com');

      expect(
        mayRecordExpense(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        isTrue,
      );
    });

    test('agrees for the person off turn', () {
      final mess = messWith(
        role: 'member',
        cookEmail: 'ali@x.com',
        order: ['ali@x.com', 'sara@x.com'],
      );

      expect(
        mayRecordExpense(
          mess: mess,
          email: 'sara@x.com',
          cookEmail: 'sara@x.com',
          date: todayKey(),
        ),
        isFalse,
      );
    });
  });

  group('a date that is a month rather than a day', () {
    // The app carries both a month key ("2026-10") and a day key
    // ("2026-10-12") and they differ by three characters, so the wrong one
    // compiles and saves. Filing a meal under a month would make "today's
    // entries" show the whole month and "today's total" the whole month's sum.
    final mess = messWith(role: 'member', cookEmail: 'ali@x.com');

    test('is refused as not the person\'s turn', () {
      expect(
        recordRefusal(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ali@x.com',
          date: '${todayKey().substring(0, 7)}',
        ),
        RecordRefusal.notTheirTurn,
      );
    });

    test('is not quietly accepted as today', () {
      expect(
        mayRecordExpense(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ali@x.com',
          date: '${todayKey().substring(0, 7)}',
        ),
        isFalse,
      );
    });
  });

  group('a mess with nobody in it', () {
    test('no member has a turn, so nobody may record', () {
      final mess = Mess(
        id: 'm1',
        name: 'Empty Mess',
        ownerUid: 'owner-uid',
        joinCode: 'CODE',
        myRole: 'member',
        rotation: {'anchorDate': todayKey(), 'order': <String>[]},
      );

      expect(
        recordRefusal(
          mess: mess,
          email: 'ali@x.com',
          cookEmail: 'ali@x.com',
          date: todayKey(),
        ),
        RecordRefusal.notTheirTurn,
      );
    });

    test('the owner can still record into it', () {
      // An empty mess is a mess being set up, and the owner has to be able to
      // enter the first meal into it.
      final mess = Mess(
        id: 'm1',
        name: 'Empty Mess',
        ownerUid: 'owner-uid',
        joinCode: 'CODE',
        myRole: 'owner',
        rotation: {'anchorDate': todayKey(), 'order': <String>[]},
      );

      expect(
        recordRefusal(
          mess: mess,
          email: 'owner@x.com',
          cookEmail: 'owner@x.com',
          date: todayKey(),
        ),
        isNull,
      );
    });
  });
}
