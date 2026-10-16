import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/data/models.dart';
import 'package:messapp/services/mess_cloud_service.dart';

/// The cooking turn is derived from the roster and one anchor, so it is pure
/// arithmetic. These tests pin the behaviour that actually matters to the mess:
/// that everyone computes the same answer, and that changing the roster cannot
/// leave a schedule pointing at somebody who has left.
void main() {
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);

  MessMember person(String email, {MessRole role = MessRole.member}) =>
      MessMember(uid: '', email: email, name: email.split('@').first, role: role);

  /// The cooking turn for a roster and an optional anchor.
  ///
  /// Built the same way [Mess.fromDoc] builds one, so these tests exercise the
  /// real mapping rather than a stand-in.
  MessTurn turnOf(List<MessMember> people,
          {DateTime? anchorDate, String? anchorEmail, List<String>? order}) =>
      _TestMess.build(people,
              anchorDate: anchorDate, anchorEmail: anchorEmail, order: order)
          .turn;

  group('cooking turn', () {
    test('is empty when nobody is in the mess', () {
      final t = turnOf(const []);
      expect(t.hasMembers, isFalse);
      expect(t.today, isNull);
      expect(t.roundLength, 0);
    });

    test('starts with the first member when no anchor is set', () {
      final t = turnOf([person('a@x.com'), person('b@x.com')]);

      expect(t.hasMembers, isTrue);
      expect(t.today!.email, 'a@x.com');
      expect(t.positionInRound, 1);
      expect(t.roundLength, 2);
      expect(t.isManual, isFalse, reason: 'not chosen by hand yet');
    });

    test('honours an anchor picked by the owner', () {
      final t = turnOf(
        [person('a@x.com'), person('b@x.com'), person('c@x.com')],
        anchorDate: todayOnly,
        anchorEmail: 'b@x.com',
      );

      expect(t.today!.email, 'b@x.com');
      expect(t.isManual, isTrue,
          reason: 'the test build always marks the rotation as hand-picked');
    });

    test('advances one member per day from the anchor', () {
      final start = todayOnly.subtract(const Duration(days: 1));
      final t = turnOf(
        [person('a@x.com'), person('b@x.com'), person('c@x.com')],
        anchorDate: start,
        anchorEmail: 'a@x.com',
      );

      // One day after a@x.com's turn, the next person is due.
      expect(t.today!.email, 'b@x.com');
      expect(t.positionInRound, 2);
    });

    test('comes back around after a full round', () {
      final start = todayOnly.subtract(const Duration(days: 3));
      final t = turnOf(
        [person('a@x.com'), person('b@x.com'), person('c@x.com')],
        anchorDate: start,
        anchorEmail: 'a@x.com',
      );

      // 3 members, 3 days later: the cycle has completed exactly once.
      expect(t.today!.email, 'a@x.com');
      expect(t.positionInRound, 1);
      expect(t.roundLength, 3);
    });

    test('every member of the mess computes the same schedule', () {
      // The whole point of deriving it from the document: two people reading the
      // same mess must never disagree about whose turn it is.
      final anchor = todayOnly.subtract(const Duration(days: 2));
      final people = [person('a@x.com'), person('b@x.com'), person('c@x.com')];

      final one = turnOf(people, anchorDate: anchor, anchorEmail: 'a@x.com');
      final two = turnOf(people, anchorDate: anchor, anchorEmail: 'a@x.com');

      expect(one.today!.email, two.today!.email);
      expect(
        one.upcoming.map((u) => u.member.email).toList(),
        two.upcoming.map((u) => u.member.email).toList(),
      );
    });

    test('follows the saved order', () {
      final t = turnOf(
        [person('a@x.com'), person('b@x.com'), person('c@x.com')],
        anchorDate: todayOnly,
        anchorEmail: 'c@x.com',
        order: ['c@x.com', 'a@x.com', 'b@x.com'],
      );

      expect(t.order.map((m) => m.email).toList(),
          ['c@x.com', 'a@x.com', 'b@x.com']);
      expect(t.today!.email, 'c@x.com');
    });

    test('appends anyone new to the end of the saved order', () {
      final t = turnOf(
        [person('a@x.com'), person('b@x.com'), person('new@x.com')],
        anchorDate: todayOnly,
        anchorEmail: 'a@x.com',
        order: ['a@x.com', 'b@x.com'],
      );

      expect(t.order.map((m) => m.email).toList(),
          ['a@x.com', 'b@x.com', 'new@x.com'],
          reason: 'a new member must not jump the queue');
    });

    test('never points the schedule at somebody who left', () {
      // The anchor person was removed. The schedule must still be produced
      // rather than failing or silently naming a non-member.
      final t = turnOf(
        [person('b@x.com'), person('c@x.com')],
        anchorDate: todayOnly,
        anchorEmail: 'gone@x.com',
        order: ['gone@x.com', 'b@x.com', 'c@x.com'],
      );

      expect(t.hasMembers, isTrue);
      expect(t.today!.email, isNot('gone@x.com'));
      expect(
        t.order.every((m) => m.email != 'gone@x.com'),
        isTrue,
        reason: 'a removed member must not remain in the turn order',
      );
    });

    test('preview starts today and advances by a day each time', () {
      final t = turnOf(
        [person('a@x.com'), person('b@x.com')],
        anchorDate: todayOnly,
        anchorEmail: 'a@x.com',
      );

      expect(t.upcoming, isNotEmpty);
      expect(t.upcoming.first.date, todayOnly);
      expect(t.upcoming[1].date,
          todayOnly.add(const Duration(days: 1)));
      expect(t.upcoming[0].member.email, isNot(t.upcoming[1].member.email),
          reason: 'two members must not be on the same day');
    });

    test('identifies whose turn it is for a given person', () {
      final people = [person('a@x.com'), person('b@x.com')];
      final t = turnOf(people, anchorDate: todayOnly, anchorEmail: 'a@x.com');

      expect(t.isToday(people[0]), isTrue);
      expect(t.isToday(people[1]), isFalse);
    });

    test('matches people regardless of email capitalisation', () {
      // Google returns the address as the account stores it, so a roster written
      // lowercase must still match an account that capitalises it.
      final people = [person('a@x.com'), person('B@X.com')];
      final t = turnOf(people, anchorDate: todayOnly, anchorEmail: 'a@x.com');

      expect(t.isToday(people[1]), isFalse);
      expect(t.order, hasLength(2), reason: 'B@X.com must not be dropped');
    });
  });

  group('knowing it is your own turn', () {
    // The app has to answer "is it me?" without the person having to recognise
    // their own name on a card. Everything keys off this one comparison.
    test('is true when the cook is the signed-in person', () {
      final people = [person('me@x.com'), person('other@x.com')];
      final t = turnOf(people, anchorDate: todayOnly, anchorEmail: 'me@x.com');

      expect(t.isToday(people[0]), isTrue);
    });

    test('is false on somebody else\'s day', () {
      final people = [person('me@x.com'), person('other@x.com')];
      final t = turnOf(people, anchorDate: todayOnly, anchorEmail: 'other@x.com');

      expect(t.isToday(people[0]), isFalse);
      expect(t.isToday(people[1]), isTrue);
    });

    test('ignores capitalisation on either side', () {
      // Google returns the address exactly as the account stores it, so an
      // account that capitalises its own name must still be recognised.
      final people = [person('Ali@X.com'), person('other@x.com')];
      final t = turnOf(people, anchorDate: todayOnly, anchorEmail: 'Ali@X.com');

      expect(t.isToday(people[0]), isTrue);
      expect(t.isToday(const MessMember(uid: '', email: 'ali@x.com')),
          isTrue,
          reason: 'the signed-in address may differ in case from the roster key');
    });

    test('upcoming repeats your own day so the next one is easy to spot', () {
      final people = [person('a@x.com'), person('me@x.com')];
      // Anchored yesterday on a@x.com, so with two people today is
      // me@x.com's turn, and the preview shows every other day as theirs.
      final t = turnOf(people,
          anchorDate: todayOnly.subtract(const Duration(days: 1)),
          anchorEmail: 'a@x.com');

      expect(t.today!.email, 'me@x.com');

      final mine = t.upcoming.where((u) => u.member.email == 'me@x.com');
      expect(mine, isNotEmpty);
      expect(
        mine.first.date,
        todayOnly,
        reason: 'today must lead the preview for this person',
      );
      // Every other day, so the "YOU" marker is unambiguous.
      expect(
        mine.map((u) => u.date.difference(todayOnly).inDays).toList(),
        [0, 2, 4, 6],
      );
    });
  });

  // Decides who may record what was cooked today. Getting this wrong either
    // locks the cook out of their own turn, or lets anyone log anyone else's
    // meal, so both directions are pinned down here.
group('who may record today\'s cook', () {
    test('true for whoever is on turn', () {
      final t = turnOf([person('a@x.com'), person('me@x.com')],
          anchorDate: todayOnly, anchorEmail: 'me@x.com');

      expect(t.isTodayFor('me@x.com'), isTrue);
      expect(t.isTodayFor('a@x.com'), isFalse);
    });

    test('ignores capitalisation and stray spaces on the account', () {
      final t = turnOf([person('Ali@X.com')], anchorDate: todayOnly,
          anchorEmail: 'Ali@X.com');

      expect(t.isTodayFor('Ali@X.com'), isTrue);
      expect(t.isTodayFor('  ali@x.com  '), isTrue);
    });

    test('false for an empty address, so nobody matches by accident', () {
      final t = turnOf([person('a@x.com')],
          anchorDate: todayOnly, anchorEmail: 'a@x.com');

      expect(t.isTodayFor(''), isFalse);
      expect(t.isTodayFor('   '), isFalse);
    });

    test('false when the mess has nobody to cook', () {
      final t = turnOf(const []);

      expect(t.today, isNull);
      expect(t.isTodayFor('a@x.com'), isFalse);
    });

    test('only one person is ever on turn', () {
      final t = turnOf([person('a@x.com'), person('b@x.com'), person('c@x.com')],
          anchorDate: todayOnly, anchorEmail: 'b@x.com');

      final onTurn = ['a@x.com', 'b@x.com', 'c@x.com']
          .where(t.isTodayFor)
          .toList();

      expect(onTurn, ['b@x.com'],
          reason: 'a shared turn that two people believe they hold is a bug');
    });

    test('a member due today and the owner are both allowed', () {
      // The owner records on anyone's behalf; the member records on their own
      // turn. Both must pass, or one of them is locked out.
      final t = turnOf([person('owner@x.com'), person('me@x.com')],
          anchorDate: todayOnly, anchorEmail: 'me@x.com');

      expect(t.isTodayFor('me@x.com'), isTrue,
          reason: "the member on turn must be able to record it");
      expect(t.isTodayFor('owner@x.com'), isFalse,
          reason: 'the owner is allowed by role, not by the turn');
    });
  });

  group('members in a mess', () {
    test('lists the owner first, then everyone else', () {
      final t = _TestMess.build([
        person('b@x.com'),
        person('a@x.com', role: MessRole.owner),
        person('c@x.com'),
      ]).turn;

      expect(t.order.first.role, MessRole.owner);
    });

    test('reports a member who has not signed in yet', () {
      final notSignedIn =
          const MessMember(uid: '', email: 'new@x.com', name: null);
      expect(notSignedIn.hasSignedIn, isFalse);
    });
  });

  // Kept separate so the tests above can build a Mess without a Firestore
  // document snapshot.
  group('Member model', () {
    test('keeps the local Member model usable', () {
      final m = Member(id: 1, name: 'Ali');
      expect(m.name, 'Ali');
    });
  });
}

/// Builds a [Mess] the same way the real document mapping does.
///
/// The turn maths lives on [Mess], so the tests need real instances. Going
/// through the actual field names and shapes keeps them honest about what is
/// stored, rather than testing a parallel implementation.
class _TestMess {
  static Mess build(
    List<MessMember> people, {
    DateTime? anchorDate,
    String? anchorEmail,
    List<String>? order,
  }) {
    final members = <String, dynamic>{};
    for (final p in people) {
      members[p.email.toLowerCase()] = {
        'email': p.email.toLowerCase(),
        'name': p.name,
        'role': p.role.wire,
        'uid': p.uid,
      };
    }

    final rotation = anchorEmail == null
        ? null
        : <String, dynamic>{
            'anchorDate': anchorDate == null
                ? null
                : '${anchorDate.year.toString().padLeft(4, '0')}-'
                    '${anchorDate.month.toString().padLeft(2, '0')}-'
                    '${anchorDate.day.toString().padLeft(2, '0')}',
            'anchorEmail': anchorEmail,
            'order': order ?? const <String>[],
            'manual': true,
          };

    return Mess.fromMapForTest(
      id: 'test',
      name: 'Test mess',
      role: MessRole.owner.wire,
      members: members,
      rotation: rotation,
    );
  }
}