import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/services/expense_cloud_service.dart';

/// Who is allowed to read a saved entry, and which month it falls in.
///
/// Both of these went wrong in a way that looked fine: the read list was built
/// from something the roster did not actually hold, and the month was pushed
/// into the query as a second filter. Entries were saving to Firestore and coming
/// back empty, with nothing in the data to show why.
void main() {
  String m(String email) => email;

  group('who may read an entry', () {
    test('includes the person who recorded it', () {
      // The failure this prevents: the writer writes an entry and the read list
      // does not contain them, so they can never see what they just saved.
      final list = visibleToFor(
        rosterEmails: [m('ali@x.com'), m('sara@x.com')],
        recorderEmail: 'ali@x.com',
      );

      expect(list, contains('ali@x.com'));
    });

    test('includes the recorder even when they are not in the roster', () {
      // An owner recording on somebody's behalf is still in the roster, but a
      // removed member recording should not be locked out of their own entry.
      final list = visibleToFor(
        rosterEmails: [m('sara@x.com')],
        recorderEmail: 'gone@x.com',
      );

      expect(list, contains('gone@x.com'));
    });

    test('includes every member of the mess', () {
      final list = visibleToFor(
        rosterEmails: [m('ali@x.com'), m('sara@x.com'), m('shahbaz@x.com')],
        recorderEmail: 'ali@x.com',
      );

      expect(
        list,
        containsAll(['ali@x.com', 'sara@x.com', 'shahbaz@x.com']),
      );
    });

    test('is keyed on the address, never on a blank or an empty string', () {
      // A Firebase uid is unknown until somebody first signs in, so a roster
      // entry can carry a blank uid. A blank in this list matches nobody and
      // makes the field impossible to reason about.
      final list = visibleToFor(
        rosterEmails: [m('ali@x.com'), m('  '), m('')],
        recorderEmail: 'ali@x.com',
      );

      expect(list.every((e) => e.trim().isNotEmpty), isTrue);
      expect(list, isNot(contains('')));
    });

    test('stores every address lowercased', () {
      // The rules lowercase the token before comparing, and memberships are
      // keyed lowercased, so a capitalised entry here would never match.
      final list = visibleToFor(
        rosterEmails: [m('Ali@X.com'), m('SARA@x.com')],
        recorderEmail: 'Ali@X.com',
      );

      expect(list.every((e) => e == e.toLowerCase()), isTrue);
      expect(list, containsAll(['ali@x.com', 'sara@x.com']));
    });

    test('lists nobody twice', () {
      // The recorder is usually also in the roster, and a duplicate in an
      // array-contains filter is noise that survives into the stored document.
      final list = visibleToFor(
        rosterEmails: [m('ali@x.com'), m('ali@x.com')],
        recorderEmail: 'ali@x.com',
      );

      expect(list.where((e) => e == 'ali@x.com'), hasLength(1));
    });

    test('an empty roster still leaves the recorder able to read', () {
      final list = visibleToFor(rosterEmails: const [], recorderEmail: 'ali@x.com');

      expect(list, ['ali@x.com']);
    });

    test('an unknown recorder leaves an empty list rather than a blank', () {
      final list = visibleToFor(rosterEmails: const [], recorderEmail: null);

      expect(list, isEmpty);
      expect(list, isNot(contains('')));
    });
  });

  group('which month an entry falls in', () {
    test('a day maps to its own month', () {
      expect(monthOf('2026-10-12'), '2026-10');
    });

    test('the first of a month maps to that month, not the one before', () {
      // The mistake that would silently move an entry into last month's
      // figures, where it would be invisible on the day it was recorded.
      expect(monthOf('2026-10-01'), '2026-10');
      expect(monthOf('2026-01-01'), '2026-01');
    });

    test('the last of a month stays inside it', () {
      expect(monthOf('2026-10-31'), '2026-10');
      expect(monthOf('2026-12-31'), '2026-12');
    });

    test('every day of a month maps to that month', () {
      for (var d = 1; d <= 31; d++) {
        final key = '2026-01-${d.toString().padLeft(2, '0')}';
        expect(monthOf(key), '2026-01', reason: 'failed on $key');
      }
    });
  });
}
