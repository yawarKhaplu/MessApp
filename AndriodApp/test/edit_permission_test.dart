import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/mess_cloud_service.dart';

/// Who may edit a saved entry.
///
/// The owner may change any of them. The turn member — the person whose bari it
/// is — may change only what they recorded themselves. That second half is the
/// part worth testing: being on turn is not the same as owning the record, and
/// treating it as though it were would let whoever happens to be cooking rewrite
/// a meal somebody else entered.
void main() {
  /// A mess of three people whose turn today belongs to [turnOwner].
  Mess messWith({required String role, required String turnOwner}) {
    final now = DateTime.now();
    final key = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final people = ['owner@x.com', 'ali@x.com', 'sara@x.com'];

    return Mess(
      id: 'm1',
      name: 'Test Mess',
      ownerUid: 'uid-owner',
      joinCode: 'CODE',
      myRole: role,
      members: [
        for (final e in people) MessMember(uid: 'uid-$e', email: e, name: e),
      ],
      rotation: {
        'anchorDate': key,
        // Put the turn owner first so the schedule puts them on today.
        'order': [turnOwner, ...people.where((e) => e != turnOwner)],
        'manual': true,
      },
    );
  }

  final owner = messWith(role: 'owner', turnOwner: 'ali@x.com');
  final turnMember = messWith(role: 'member', turnOwner: 'ali@x.com');
  final bystander = messWith(role: 'member', turnOwner: 'ali@x.com');

  group('the owner', () {
    test('may edit an entry they recorded', () {
      expect(
        mayEditExpense(
            mess: owner, email: 'owner@x.com', recordedBy: 'owner@x.com'),
        isTrue,
      );
    });

    test('may edit an entry the turn member recorded', () {
      // The whole point of the owner role: correcting a meal somebody else
      // entered is the owner's job, not the cook's.
      expect(
        mayEditExpense(
            mess: owner, email: 'owner@x.com', recordedBy: 'ali@x.com'),
        isTrue,
      );
    });

    test('may edit an entry recorded on another day or month', () {
      expect(
        mayEditExpense(
          mess: owner,
          email: 'owner@x.com',
          recordedBy: 'sara@x.com',
        ),
        isTrue,
      );
    });
  });

  group('the turn member', () {
    test('may edit the entry they recorded themselves', () {
      expect(
        mayEditExpense(
            mess: turnMember, email: 'ali@x.com', recordedBy: 'ali@x.com'),
        isTrue,
      );
    });

    test('may not edit an entry somebody else recorded', () {
      // Being on turn does not extend to the whole day. This is the rule most
      // likely to be got wrong, because on a busy day the owner may well have
      // entered several meals of their own.
      expect(
        mayEditExpense(
            mess: turnMember, email: 'ali@x.com', recordedBy: 'owner@x.com'),
        isFalse,
        reason: 'on turn is not the same as having recorded it',
      );
    });

    test('may not edit another member\'s entry', () {
      expect(
        mayEditExpense(
            mess: turnMember, email: 'ali@x.com', recordedBy: 'sara@x.com'),
        isFalse,
      );
    });

    test('the owner\'s address is matched however it is capitalised', () {
      // Addresses come back from Google exactly as the account stores them, so
      // a capitalised one must still recognise its own entry.
      expect(
        mayEditExpense(
            mess: turnMember, email: 'Ali@X.com', recordedBy: 'ali@x.com'),
        isTrue,
      );
    });
  });

  group('a member who is not the turn member', () {
    test('may not edit their own earlier entry', () {
      // Somebody may have recorded a meal on a day that was theirs. That does
      // not carry over to today, when somebody else is cooking.
      expect(
        mayEditExpense(
            mess: bystander, email: 'sara@x.com', recordedBy: 'sara@x.com'),
        isFalse,
      );
    });

    test('may not edit the turn member\'s entry', () {
      expect(
        mayEditExpense(
            mess: bystander, email: 'sara@x.com', recordedBy: 'ali@x.com'),
        isFalse,
      );
    });
  });

  group('nobody signed in', () {
    test('is refused rather than treated as the owner', () {
      final role = 'member';
      final m = messWith(role: role, turnOwner: 'ali@x.com');

      expect(
        mayEditExpense(mess: m, email: null, recordedBy: 'ali@x.com'),
        isFalse,
      );
      expect(
        mayEditExpense(mess: m, email: '  ', recordedBy: 'ali@x.com'),
        isFalse,
      );
    });
  });

  group('an entry with no recorder recorded', () {
    test('nobody but the owner may edit it', () {
      // Older entries have no recordedBy at all. Defaulting that to "somebody"
      // would let the turn member claim an entry nobody can attribute.
      expect(
        mayEditExpense(
            mess: turnMember, email: 'ali@x.com', recordedBy: ''),
        isFalse,
      );
      expect(
        mayEditExpense(
            mess: owner, email: 'owner@x.com', recordedBy: ''),
        isTrue,
      );
    });
  });
}
