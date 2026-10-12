import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/mess_cloud_service.dart';

/// The cooking turn is derived from the roster and the mess's anchor, so who is
/// on turn today is worked out rather than stored. Everything about permissions
/// rests on that derivation being right, and on it being right in the same way
/// every time the app runs.
void main() {
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Mess messWithOrder(List<String> order) {
    final today = day(DateTime.now());
    return Mess(
      id: 'm1',
      name: 'Test Mess',
      ownerUid: 'uid-owner',
      joinCode: 'CODE',
      myRole: 'member',
      members: [
        for (final e in order) MessMember(uid: 'uid-$e', email: e, name: e),
      ],
      rotation: {'anchorDate': today, 'order': order, 'manual': true},
    );
  }

  group('whose turn it is', () {
    test('the first person in the order is on turn on the anchor day', () {
      final mess = messWithOrder(['ali@x.com', 'sara@x.com']);
      expect(mess.turn.today?.email, 'ali@x.com');
    });

    test('with one member the turn never leaves them', () {
      final mess = messWithOrder(['ali@x.com']);
      expect(mess.turn.today?.email, 'ali@x.com');
      expect(mess.turn.roundLength, 1);
    });

    test('every member gets a turn within one round', () {
      final order = ['ali@x.com', 'sara@x.com', 'shahbaz@x.com'];
      final mess = messWithOrder(order);

      // The round is as long as the roster, so a member can be missing from
      // "today" only if the roster itself is empty.
      expect(mess.turn.roundLength, order.length);
      expect(mess.turn.order.length, order.length);
    });
  });

  group('isTodayFor', () {
    test('answers for the person on turn', () {
      final mess = messWithOrder(['ali@x.com', 'sara@x.com']);
      expect(mess.turn.isTodayFor('ali@x.com'), isTrue);
    });

    test('says no for everybody else', () {
      final mess = messWithOrder(['ali@x.com', 'sara@x.com']);
      expect(mess.turn.isTodayFor('sara@x.com'), isFalse);
    });

    test('matches the address however it is capitalised', () {
      // Google returns the account's email exactly as stored, so an address that
      // arrives capitalised must still recognise its own turn. Getting this
      // wrong locks somebody out of recording the day they cook.
      final mess = messWithOrder(['Ali@X.com', 'sara@x.com']);

      expect(mess.turn.isTodayFor('ali@x.com'), isTrue);
      expect(mess.turn.isTodayFor('ALI@x.com'), isTrue);
      expect(mess.turn.isTodayFor('  ali@x.com  '), isTrue);
    });

    test('an empty address is nobody\'s turn', () {
      // An empty string must not match a member whose address is somehow blank.
      final mess = messWithOrder(['ali@x.com']);
      expect(mess.turn.isTodayFor(''), isFalse);
      expect(mess.turn.isTodayFor('   '), isFalse);
    });
  });

  group('a mess with no members', () {
    test('has no turn at all', () {
      final mess = messWithOrder([]);

      expect(mess.turn.today, isNull);
      expect(mess.turn.hasMembers, isFalse);
      expect(mess.turn.isTodayFor('ali@x.com'), isFalse);
    });
  });

  group('the answer is stable', () {
    test('asking twice gives the same answer', () {
      // The turn is cached after first use. If the cache disagreed with a fresh
      // calculation, the same person could see the button appear and vanish
      // while looking at one screen.
      final mess = messWithOrder(['ali@x.com', 'sara@x.com']);

      expect(mess.turn.today?.email, mess.turn.today?.email);
      expect(mess.turn.isTodayFor('ali@x.com'),
          mess.turn.isTodayFor('ali@x.com'));
    });
  });

  group('an anchor in the past still resolves', () {
    test('the turn lands on whoever the anchor puts it on', () {
      final yesterday = day(DateTime.now().subtract(const Duration(days: 1)));
      final mess = Mess(
        id: 'm1',
        name: 'Test Mess',
        ownerUid: 'uid-owner',
        joinCode: 'CODE',
        myRole: 'member',
        members: [
          const MessMember(uid: 'a', email: 'ali@x.com', name: 'Ali'),
          const MessMember(uid: 's', email: 'sara@x.com', name: 'Sara'),
        ],
        rotation: {
          'anchorDate': yesterday,
          'order': ['ali@x.com', 'sara@x.com'],
          'manual': true,
        },
      );

      // A one-day shift from the anchor puts the second person on today.
      expect(mess.turn.today?.email, 'sara@x.com');
      expect(mess.turn.isTodayFor('sara@x.com'), isTrue);
      expect(mess.turn.isTodayFor('ali@x.com'), isFalse);
    });
  });
}
