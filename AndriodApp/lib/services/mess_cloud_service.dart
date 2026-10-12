import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'collection_cloud_service.dart';
import 'expense_cloud_service.dart';
import 'menu_cloud_service.dart';
import 'other_expense_cloud_service.dart';

/// Roles a person can hold in a mess.
enum MessRole {
  owner,
  member;

  static MessRole parse(String? value) =>
      value == 'owner' ? MessRole.owner : MessRole.member;

  String get wire => name;
}

/// One person's place in a mess.
class MessMember {
  /// Empty until this person signs in for the first time. A Firebase uid cannot
  /// be known before that, which is why seats are keyed by email.
  final String uid;
  final String email;
  final String? name;
  final MessRole role;

  const MessMember({
    required this.uid,
    required this.email,
    this.name,
    this.role = MessRole.member,
  });

  bool get hasSignedIn => uid.isNotEmpty;

  /// Builds a seat from its entry in the mess document's members map. The map is
  /// keyed by the lowercased email, which is the same key used by the rules.
  factory MessMember.fromEntry(String email, Map<dynamic, dynamic> entry) {
    return MessMember(
      uid: (entry['uid'] as String?) ?? '',
      email: (entry['email'] as String?) ?? email,
      name: entry['name'] as String?,
      role: MessRole.parse(entry['role'] as String?),
    );
  }
}

/// One day of the cooking turn.
class TurnEntry {
  final DateTime date;
  final MessMember member;

  const TurnEntry(this.date, this.member);
}

/// Whose turn it is to cook, for everyone in the mess.
///
/// Computed from the mess document rather than stored per day, because the
/// schedule is a pure function of the roster and one anchor. That keeps a single
/// source of truth: change the anchor or the roster and every day follows,
/// instead of a stored list that can disagree with the roster it was built from.
class MessTurn {
  /// Everyone in turn order.
  final List<MessMember> order;

  /// Who cooks today, or null when the mess has no members yet.
  final MessMember? today;

  /// Who cooks tomorrow.
  final MessMember? next;

  /// 1-based position of [today] in the current round.
  final int positionInRound;

  /// How many days one full round takes.
  final int roundLength;

  /// The day the cycle is anchored on.
  final DateTime? anchorDate;

  /// Today plus the coming days.
  final List<TurnEntry> upcoming;

  /// False until someone picks an anchor by hand, which tells the screen to say
  /// the schedule is a suggestion rather than a decision.
  final bool isManual;

  const MessTurn({
    required this.order,
    required this.today,
    required this.next,
    required this.positionInRound,
    required this.roundLength,
    required this.anchorDate,
    required this.upcoming,
    required this.isManual,
  });

  const MessTurn.empty()
      : order = const [],
        today = null,
        next = null,
        positionInRound = 0,
        roundLength = 0,
        anchorDate = null,
        upcoming = const [],
        isManual = false;

  bool get hasMembers => order.isNotEmpty;

  /// True when today is this person's turn. Used to decide who may add an entry
  /// for today, so it must answer exactly as the schedule does.
  bool isToday(MessMember member) => isTodayFor(member.email);

  /// True when the turn belongs to [email].
  ///
  /// Matched on the lowercased address, because Google returns an account's email
  /// exactly as it is stored and may capitalise it. Comparing raw would leave
  /// someone unable to record their own turn.
  bool isTodayFor(String email) {
    final cook = today;
    if (cook == null) return false;
    final lower = email.trim().toLowerCase();
    return lower.isNotEmpty && lower == cook.email.trim().toLowerCase();
  }
}

/// Why someone may not record an expense, or null when they may.
///
/// A distinct value per reason rather than a bare yes/no, because the message
/// shown is the useful part: telling someone it is not their turn without saying
/// whose it is leaves them with nothing to do about it.
enum RecordRefusal {
  notSignedIn,
  notTheirTurn,
  notTheirCook,
}

/// Today as `yyyy-MM-dd`, matched against the `date` a meal is filed under.
///
/// Written out here rather than imported from the data models: the shared layer
/// must not depend on the local models it is replacing, or moving a feature out
/// of SQLite would never actually remove it.
String _dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Decides whether [email] may record a meal for [cookEmail] on [date].
///
/// One function rather than a check written at each use, so the button and the
/// save cannot drift apart — a screen can be reached without passing the button,
/// and a rule that only guards the button is no rule at all.
///
/// The owner may record anything, for anyone. A member may record a meal only
/// when they are the turn member — the person whose bari it is today — and only
/// their own entry: without that second half the check would be satisfied by
/// nominating somebody else as the cook.
RecordRefusal? recordRefusal({
  required Mess mess,
  required String? email,
  required String cookEmail,
  required String date,
}) {
  if (mess.isOwner) return null;

  final lower = (email ?? '').trim().toLowerCase();
  if (lower.isEmpty) return RecordRefusal.notSignedIn;

  if (cookEmail.trim().toLowerCase() != lower) {
    return RecordRefusal.notTheirCook;
  }

  // Only today is recordable by the turn member, meaning the person whose bari
  // it is. Backdating a meal would let somebody rebuild a round they did not
  // cook.
  final today = _dayKey(DateTime.now());
  if (date.trim() != today) return RecordRefusal.notTheirTurn;

  if (!mess.turn.isTodayFor(lower)) return RecordRefusal.notTheirTurn;

  return null;
}

/// The plain yes/no form of [recordRefusal], for gating a control.
bool mayRecordExpense({
  required Mess mess,
  required String? email,
  required String cookEmail,
  required String date,
}) =>
    recordRefusal(
      mess: mess,
      email: email,
      cookEmail: cookEmail,
      date: date,
    ) ==
    null;

/// Who may edit or delete a shared entry.
///
/// The owner may change any of them — a correction changes what the mess owes,
/// and the owner is the one answerable for that.
///
/// The turn member, meaning the person whose bari it is today, may change only
/// the entries they recorded themselves. Being on turn is not enough on its own:
/// without the second half, whoever happens to be cooking could rewrite a meal
/// somebody else entered, which is precisely the thing the turn exists to
/// prevent.
///
/// Everyone else may read but not change. The rules enforce the same shape
/// independently, so this is the app agreeing with the server rather than
/// substituting for it.
bool mayEditExpense({
  required Mess mess,
  required String? email,
  required String recordedBy,
}) {
  if (mess.isOwner) return true;

  final lower = (email ?? '').trim().toLowerCase();
  if (lower.isEmpty) return false;

  if (recordedBy.trim().toLowerCase() != lower) return false;

  return mess.turn.isTodayFor(lower);
}

/// Checks that [date] is a full `yyyy-MM-dd` day.
///
/// The app has both a month key and a day key and they differ by three
/// characters, so passing the wrong one compiles, saves without complaint, and
/// quietly files every entry in a month under the first day of it. Rejecting a
/// short key at the write boundary turns that class of mistake into an error
/// rather than a mess's history quietly rearranging itself.
bool _isDayKey(String date) =>
    date.length == 10 &&
    date[4] == '-' &&
    date[7] == '-' &&
    int.tryParse(date.substring(0, 4)) != null &&
    int.tryParse(date.substring(5, 7)) != null &&
    int.tryParse(date.substring(8, 10)) != null;

/// A mess the signed-in person belongs to.
class Mess {
  final String id;
  final String name;
  final String ownerUid;
  final String joinCode;
  final String? location;

  /// This person's role, taken from their membership document. The membership
  /// collection is the single source of truth for roles, not the mess roster.
  final String myRole;

  /// Everyone in the mess, read straight off this document.
  ///
  /// The list lives on the mess rather than in a subcollection so that a single
  /// document read returns both the mess and its members.
  final List<MessMember> members;

  /// The shared cooking turn, derived from [members] and the mess's anchor.
  ///
  /// Worked out on first use and then reused. Not const: the schedule depends on
  /// today's date, so it cannot be a compile-time value.
  MessTurn? _turnCache;

  MessTurn get turn => _turnCache ??= _computeTurn();

  Mess({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.joinCode,
    this.location,
    required this.myRole,
    this.members = const [],
    Map<dynamic, dynamic>? rotation,
  }) : _rotation = rotation;

  final Map<dynamic, dynamic>? _rotation;

  /// Builds a Mess from raw fields, bypassing a Firestore snapshot.
  ///
  /// Exists so the turn arithmetic can be tested without a live database. The
  /// snapshot path in [Mess.fromDoc] and this share the same field shapes, so
  /// the tests exercise the real mapping rather than a copy of it.
  @visibleForTesting
  factory Mess.fromMapForTest({
    required String id,
    required String name,
    required String role,
    required Map<String, dynamic> members,
    Map<String, dynamic>? rotation,
  }) {
    return Mess._fromFields(
      id: id,
      name: name,
      ownerUid: '',
      joinCode: '',
      location: null,
      role: role,
      members: members,
      rotation: rotation,
    );
  }

  /// The single place a mess is assembled from raw fields.
  ///
  /// [Mess.fromDoc] and the test constructor both go through here, so the roster
  /// cannot be ordered one way in the app and another way in the tests.
  factory Mess._fromFields({
    required String id,
    required String name,
    required String ownerUid,
    required String joinCode,
    required String? location,
    required String role,
    required Map<dynamic, dynamic> members,
    Map<dynamic, dynamic>? rotation,
  }) {
    final people = <MessMember>[];
    for (final entry in members.entries) {
      final seat = entry.value;
      if (seat is Map) {
        people.add(MessMember.fromEntry(
          '${entry.key}',
          Map<dynamic, dynamic>.from(seat),
        ));
      }
    }
    // Owner first, then alphabetically. Ascending by role index, since
    // MessRole.owner is 0.
    people.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      if (byRole != 0) return byRole;
      return a.email.compareTo(b.email);
    });

    return Mess(
      id: id,
      name: name,
      ownerUid: ownerUid,
      joinCode: joinCode,
      location: location,
      myRole: role,
      members: people,
      rotation: rotation,
    );
  }

  factory Mess.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String role,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};

    return Mess._fromFields(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Mess',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      joinCode: (data['joinCode'] as String?) ?? '',
      location: data['location'] as String?,
      role: role,
      members: Map<dynamic, dynamic>.from(
        (data['members'] as Map?) ?? const {},
      ),
      rotation: data['rotation'] is Map
          ? Map<dynamic, dynamic>.from(data['rotation'] as Map)
          : null,
    );
  }

  bool get isOwner => myRole == MessRole.owner.wire;

  /// Works out whose turn it is.
  ///
  /// Deliberately the same rule as the offline rotation: an anchor day plus a
  /// position, advancing one member per day. Storing only the anchor means the
  /// schedule can never drift out of step with the roster — add someone and the
  /// round simply gets longer.
  MessTurn _computeTurn() {
    if (members.isEmpty) return const MessTurn.empty();

    // Turn order follows the saved order where it still matches the roster, then
    // appends anyone new at the end, so removing someone cannot break the cycle.
    final saved = <String>[
      for (final e in (_rotation?['order'] as List?) ?? const [])
        '${e}'.toLowerCase(),
    ];

    final order = <MessMember>[];
    for (final email in saved) {
      for (final m in members) {
        if (m.email.toLowerCase() == email) {
          order.add(m);
          break;
        }
      }
    }
    for (final m in members) {
      if (!order.any((o) => o.email.toLowerCase() == m.email.toLowerCase())) {
        order.add(m);
      }
    }

    final n = order.length;
    final today = _dateOnly(DateTime.now());

    final anchor = _parseDate(_rotation?['anchorDate'] as String?) ?? today;
    final anchorEmail = (_rotation?['anchorEmail'] as String?)?.toLowerCase();

    // Where the anchor sits in the current order. If that person has left, fall
    // back to the start rather than failing to produce a schedule at all.
    var anchorIndex = anchorEmail == null
        ? 0
        : order.indexWhere((m) => m.email.toLowerCase() == anchorEmail);
    if (anchorIndex < 0) anchorIndex = 0;

    var idx = (anchorIndex + today.difference(anchor).inDays) % n;
    if (idx < 0) idx += n;

    const lookahead = 7;
    final upcoming = <TurnEntry>[];
    for (var i = 0; i < lookahead; i++) {
      var k = (idx + i) % n;
      if (k < 0) k += n;
      upcoming.add(TurnEntry(today.add(Duration(days: i)), order[k]));
    }

    return MessTurn(
      order: order,
      today: order[idx],
      next: order[(idx + 1) % n],
      positionInRound: idx + 1,
      roundLength: n,
      anchorDate: anchor,
      upcoming: upcoming,
      isManual: _rotation?['manual'] == true,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _dateOnly(parsed);
  }
}

class CloudMessage implements Exception {
  final String text;
  const CloudMessage(this.text);

  @override
  String toString() => text;
}

/// Talks to Firestore about messes, members and approval.
///
/// Expense and collection data still lives in the local SQLite database.
/// This is the membership layer only, which is what shared access needs first.
class MessCloudService {
  MessCloudService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  // Top-level so the path is creators/<email>: one collection, one document.
  static const _creators = 'creators';
  static const _messes = 'messes';
  static const _memberships = 'memberships';

  /// The signed-in person's address, normalised.
  ///
  /// Google does not normalise the case of an address and Firebase returns the
  /// token email exactly as the account stores it, so seats keyed by the raw
  /// value would silently miss anyone whose account capitalises it. Keys are
  /// always lowercased, and the rules lowercase their side to match.
  String? get _myEmail {
    final raw = _user?.email?.trim() ?? '';
    return raw.isEmpty ? null : raw.toLowerCase();
  }

  User? get _user => _auth.currentUser;

  // ---- Approval gate ----

  /// True when the app owner has explicitly approved this email to create a
  /// mess. This is the gate that stops the open internet from creating messes.
  Future<bool> isApprovedCreator() async {
    final raw = _user?.email?.trim() ?? '';
    if (raw.isEmpty) {
      // Nothing can be looked up without an email, and an empty one would build
      // a malformed path. Treat it as "not approved" rather than crashing.
      // ignore: avoid_print
      print('MessApp: signed in but no email on the account '
          '(uid ${_user?.uid}); treating as not approved.');
      return false;
    }
    final email = _myEmail!;
    // ignore: avoid_print
    print('MessApp: checking approval for "$email"');

    try {
      // A direct read, not a query: the document id is known once the email is
      // known, so nothing has to be searched for and no rule has to be proven.
      final doc = await _db.collection(_creators).doc(email).get();
      return doc.exists && (doc.data()?['enabled'] as bool? ?? false);
    } on FirebaseException catch (e) {
      // A rules denial must not be read as "not approved" silently: the user
      // would see the wrong screen and have no idea why.
      throw CloudMessage(_friendly(e));
    } on ArgumentError catch (e) {
      throw CloudMessage('Could not check approval: ${e.message}');
    }
  }

  // ---- Membership ----

  /// This person's membership: the mess they belong to and their role in it.
  ///
  /// One document read, keyed by their own email. The email is the key because a
  /// Firebase uid does not exist until someone signs in, so it is the only
  /// identifier available when the owner invites them.
  Future<({String messId, String role})?> myMembership() async {
    final email = _myEmail;
    if (email == null) return null;

    final snap = await _db.collection(_memberships).doc(email).get();
    final messId = snap.data()?['messId'] as String?;
    if (messId == null || messId.isEmpty) return null;

    return (
      messId: messId,
      role: MessRole.parse(snap.data()?['role'] as String?).wire,
    );
  }

  /// The mess this person belongs to, or null when they have no membership.
  Future<Mess?> myMess() async {
    final membership = await myMembership();
    if (membership == null) return null;

    final doc = await _db.collection(_messes).doc(membership.messId).get();
    if (!doc.exists) return null;

    return Mess.fromDoc(doc, role: membership.role);
  }

  /// Finds the mess this person should open.
  ///
  /// The membership document answers both questions at once — which mess, and
  /// what role — so this is one read rather than a search. A creator with no
  /// membership gets null, which is what routes them to the create screen.
  Future<Mess?> resolveMess(String uid) async {
    try {
      return await myMess();
    } on FirebaseException catch (e) {
      // Turn the raw denial into something a person can read, rather than dying
      // on a bare "[cloud_firestore/permission-denied]".
      throw CloudMessage(_friendly(e));
    }
  }

  /// Whether this person already belongs to a mess, in either role.
  ///
  /// Used to keep a creator away from the create screen once they own one.
  Future<bool> hasMembership() async => await myMembership() != null;

  /// Creates a mess and returns it. The creator becomes owner and first member.
  ///
  /// The mess and the owner's profile are written in one batch, so the
  /// "one account, one mess" rule cannot be half-applied: either both land or
  /// neither does.
  Future<Mess> createMess({
    required String name,
    String? location,
  }) async {
    final uid = _user?.uid;
    final email = _myEmail;
    if (uid == null || email == null) {
      throw const CloudMessage('Sign in again before creating a mess.');
    }
    if (!await isApprovedCreator()) {
      throw const CloudMessage(
          'Your account is not approved to create a mess yet.');
    }
    // Refused here rather than only in the rules, so the person gets a sentence
    // explaining why instead of a bare denial. Being a member counts as
    // belonging to a mess: creating a second would leave them in two.
    if (await hasMembership()) {
      throw const CloudMessage(
          'You already belong to a mess. One account, one mess.');
    }

    final doc = _db.collection(_messes).doc();
    final code = _generateJoinCode();
    final trimmedName = name.trim();

    try {
      final batch = _db.batch();
      batch.set(doc, {
        'name': trimmedName,
        'location': location?.trim(),
        'ownerUid': uid,
        'ownerEmail': email,
        'joinCode': code,
        'createdAt': FieldValue.serverTimestamp(),
        // The roster lives on the mess document itself, so one read returns both
        // the mess and everyone in it. A separate subcollection would need its
        // own query, and a query cannot prove itself against these rules.
        'members': {
          email: {
            'email': email,
            'name': _user?.displayName,
            'role': MessRole.owner.wire,
            'uid': uid,
            'joinedAt': FieldValue.serverTimestamp(),
          },
        },
      });
      // The creator's own membership, in the same batch as the mess, so the mess can
      // never exist without an owner able to reach it.
      batch.set(_db.collection(_memberships).doc(email), {
        'email': email,
        'messId': doc.id,
        'role': MessRole.owner.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudMessage(
          'Could not create the mess. Your account may not be approved to '
          'create one, or you may already run a mess.',
        );
      }
      throw CloudMessage(_friendly(e));
    }

    // Read back rather than rebuilding here, so the caller sees exactly what was
    // stored and the object cannot drift from the database.
    return Mess.fromDoc(
      await doc.get(),
      role: MessRole.owner.wire,
    );
  }

  // ---- Members ----

  /// Adds a person to a mess by email. Owner only.
  ///
  /// The seat is keyed by the lowercased email, which is also the key the rules
  /// use. A Firebase uid cannot be known before this person has signed in, so it
  /// is left empty and their membership record is what lets them in.
  Future<void> addMember({
    required String messId,
    required String email,
  }) async {
    final uid = _user?.uid;
    if (uid == null) throw const CloudMessage('Sign in again.');

    final clean = email.trim().toLowerCase();
    if (!clean.contains('@')) {
      throw const CloudMessage('That does not look like an email address.');
    }

    try {
      final ref = _db.collection(_messes).doc(messId);
      final snap = await ref.get();
      final existing =
          Map<dynamic, dynamic>.from((snap.data()?['members'] as Map?) ?? const {});

      if (existing.containsKey(clean)) {
        // Already listed. This is the case for anyone added before membership
        // records existed: they have a seat but no way in, because the app reads
        // the membership document to decide where to send them. Write the missing
        // record instead of refusing, which would leave them stuck permanently.
        final membership =
            await _db.collection(_memberships).doc(clean).get();
        if (membership.exists) {
          throw const CloudMessage('They are already in this mess.');
        }

        await _db.collection(_memberships).doc(clean).set({
          'email': clean,
          'messId': messId,
          'role': MessRole.member.wire,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Roster entry and membership record together, so nobody can end up listed
      // in the mess with no way in, or able to get in without being listed.
      final batch = _db.batch();
      batch.set(ref, {
        'members': {
          clean: {
            'email': clean,
            'name': null,
            'role': MessRole.member.wire,
            'uid': null,
            'addedAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
      batch.set(_db.collection(_memberships).doc(clean), {
        'email': clean,
        'messId': messId,
        'role': MessRole.member.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes a person from a mess. Owner only.
  ///
  /// The membership record goes too. Leaving it behind would be the more
  /// dangerous half: they would keep passing `isMemberOf` in the rules and still
  /// be able to read the mess even though they are no longer listed in it.
  Future<void> removeMember({
    required String messId,
    required String email,
  }) async {
    final clean = email.trim().toLowerCase();

    try {
      final ref = _db.collection(_messes).doc(messId);
      final snap = await ref.get();
      final seats =
          Map<dynamic, dynamic>.from((snap.data()?['members'] as Map?) ?? const {});
      if (!seats.containsKey(clean)) {
        throw const CloudMessage('They are not in this mess.');
      }

      final batch = _db.batch();
      batch.set(ref, {
        'members': {clean: FieldValue.delete()},
      }, SetOptions(merge: true));
      batch.delete(_db.collection(_memberships).doc(clean));
      await batch.commit();
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  // ---- Expenses ----

  /// Every expense the caller may read, newest day first.
  ///
  /// One filter, on purpose: `visibleTo` alone. Adding an equality clause on
  /// `month` makes this a two-field query, and Firestore does not create
  /// composite indexes automatically — the query fails outright with
  /// FAILED_PRECONDITION and the list comes back empty with an error behind it.
  /// A single-field array-contains filter is served by the automatic index, and
  /// the month is applied in Dart instead, which cannot fail that way.
  ///
  /// The filter is also the only shape these rules can prove: the rule reads
  /// `visibleTo` off the document, so a query constrained to exactly that field
  /// is checkable, while anything reading another document would be denied.
  Future<List<CloudExpense>> _visibleExpenses(String messId) async {
    final email = _myEmail;
    if (email == null) return const [];

    final snap = await _db
        .collection('$_messes/$messId/expenses')
        .where('visibleTo', arrayContains: email)
        .get();

    final list = snap.docs
        .map((d) => CloudExpense.fromDoc(d.id, d.data()))
        .toList();

    list.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      // Same day: newest entry first.
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });

    return list;
  }

  /// Expenses the caller may read inside one month.
  ///
  /// [month] is `yyyy-MM`. The day field is `yyyy-MM-dd`, so matching on the
  /// leading seven characters is what puts an entry in its month.
  Future<List<CloudExpense>> expenses(
    String messId,
    String month,
  ) async {
    final all = await _visibleExpenses(messId);
    return all.where((e) => monthOf(e.date) == month).toList();
  }

  /// Every expense the caller may read across the given months.
  ///
  /// Reads once and picks out the months wanted, rather than asking per month.
  /// The query is the same either way, so a loop would only pay the round trip
  /// again for a result already in hand.
  Future<List<CloudExpense>> allExpenses(
    String messId,
    List<String> months,
  ) async {
    final wanted = months.toSet();
    final all = await _visibleExpenses(messId);
    return all.where((e) => wanted.contains(monthOf(e.date))).toList();
  }

  /// Saves one day's entry.
  ///
  /// [visibleTo] carries every uid allowed to read it, which is what makes the
  /// read query provable. [cookEmail] is who cooked, which is not necessarily the
  /// person recording it.
  Future<String> addExpense({
    required String messId,
    required String date,
    required String menuName,
    required String cookEmail,
    required List<CloudExpenseItem> items,
    required List<MessMember> roster,
  }) async {
    final uid = _user?.uid;
    if (uid == null) throw const CloudMessage('Sign in again.');

    if (!_isDayKey(date)) {
      throw const CloudMessage('That date is not a day, so it was not saved.');
    }

    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final ref = _db.collection('$_messes/$messId/expenses').doc();

    try {
      await ref.set({
        'month': monthOf(date),
        'date': date,
        // Kept as a timestamp as well, because the rules can only compare a
        // timestamp against request.time. The text date is what the app reads.
        'dateTime': Timestamp.fromDate(DateTime.parse(date)),
        'menuName': menuName,
        'total': total,
        'cookEmail': cookEmail.trim().toLowerCase(),
        'recordedBy': _myEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'visibleTo': visibleToFor(
          rosterEmails: [for (final m in roster) m.email],
          recorderEmail: _myEmail,
        ),
        'items': {for (final i in items) i.id: i.toDoc()},
      });
      return ref.id;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudMessage(
          'You can only record a meal on your own cooking turn.',
        );
      }
      throw CloudMessage(_friendly(e));
    }
  }

  /// Edits an existing entry. Owner only.
  Future<void> updateExpense({
    required String messId,
    required String expenseId,
    required String date,
    required String menuName,
    required String cookEmail,
    required List<CloudExpenseItem> items,
  }) async {
    if (!_isDayKey(date)) {
      throw const CloudMessage('That date is not a day, so it was not saved.');
    }

    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    try {
      await _db.collection('$_messes/$messId/expenses').doc(expenseId).set({
        'date': date,
        'dateTime': Timestamp.fromDate(DateTime.parse(date)),
        'menuName': menuName,
        'total': total,
        'cookEmail': cookEmail.trim().toLowerCase(),
        'items': {for (final i in items) i.id: i.toDoc()},
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes an entry. Owner only.
  Future<void> deleteExpense({
    required String messId,
    required String expenseId,
  }) async {
    try {
      await _db
          .collection('$_messes/$messId/expenses')
          .doc(expenseId)
          .delete();
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  // ---- Other expenses ----

  /// Every other expense in one month.
  ///
  /// Read as a single document keyed by month rather than a query. That is what
  /// lets the membership check be used here at all: a rule that reads another
  /// document cannot be proven against a query, but it is fine for a direct read
  /// of a document whose id the app already knows.
  ///
  /// Only the owner writes here, so every member reads the whole month and there
  /// is nothing to filter per person.
  Future<List<CloudOtherExpense>> otherExpenses(
    String messId,
    String month,
  ) async {
    try {
      final doc = await _db
          .collection('$_messes/$messId/otherExpenses')
          .doc(month)
          .get();

      if (!doc.exists) return const [];

      final raw = Map<dynamic, dynamic>.from(
          (doc.data()?['entries'] as Map?) ?? const {});

      final list = <CloudOtherExpense>[];
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final data =
            Map<String, dynamic>.from(Map<dynamic, dynamic>.from(e.value as Map));
        list.add(CloudOtherExpense.fromDoc('${e.key}', data));
      }

      // Newest day first, then newest entry first within a day, so the order
      // never depends on map iteration order.
      list.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });

      return list;
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Months that hold at least one other expense.
  ///
  /// Kept as a list on the mess document because renaming or deleting a
  /// category has to reach the months that actually hold records, and there is
  /// no way to ask "which months have data" without a query.
  Future<List<String>> otherExpenseMonths(String messId) async {
    try {
      final doc = await _db.collection(_messes).doc(messId).get();
      final raw = doc.data()?['otherExpenseMonths'];
      if (raw is! List) return const [];
      return [for (final m in raw) '$m'];
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Records another expense. Owner only.
  ///
  /// [id] is supplied when editing, so the same row is overwritten instead of a
  /// second one appearing.
  Future<String> addOtherExpense({
    required String messId,
    required String date,
    required String category,
    required double amount,
    String? note,
    String? title,
    String? id,
  }) async {
    if (!_isDayKey(date)) {
      throw const CloudMessage('That date is not a day, so it was not saved.');
    }
    if (category.trim().isEmpty) {
      throw const CloudMessage('Choose a category.');
    }
    if (amount <= 0) {
      throw const CloudMessage('Enter an amount greater than zero.');
    }

    final month = monthOf(date);
    final key = id ?? 'o${DateTime.now().microsecondsSinceEpoch}';

    final noteText = (note ?? '').trim();
    final titleText = (title ?? '').trim();

    final entry = CloudOtherExpense(
      id: key,
      date: date,
      category: category.trim(),
      amount: amount,
      note: noteText.isEmpty ? null : noteText,
      title: titleText.isEmpty ? null : titleText,
      recordedBy: _myEmail,
    ).toDoc();

    final ref = _db.collection('$_messes/$messId/otherExpenses').doc(month);

    try {
      // Written as two steps rather than a merged set of the whole map. A plain
      // 'entries.<key>' string key inside a set creates a field literally named
      // "entries.<key>" instead of an entry in the map, so the entry would save
      // and then read back as empty. A FieldPath is the only way to add one entry
      // to a map without first reading the whole map.
      await ref.set({'month': month}, SetOptions(merge: true));
      await ref.update({FieldPath(['entries', key]): entry});

      await _rememberMonth(messId, month);
      return key;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudMessage('Only the owner can add other expenses.');
      }
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes an other expense. Owner only.
  ///
  /// The month is required because the document is keyed by it and the entry id
  /// alone does not say where to look.
  Future<void> deleteOtherExpense({
    required String messId,
    required String month,
    required String id,
  }) async {
    try {
      final ref = _db.collection('$_messes/$messId/otherExpenses').doc(month);
      final snap = await ref.get();

      // Nothing to remove if the month was never written, rather than failing on
      // a delete aimed at a document that does not exist.
      if (!snap.exists) return;

      await ref.update(<Object, Object?>{
        FieldPath(['entries', id]): FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Notes that [month] holds records, so a category rename can find it later.
  Future<void> _rememberMonth(String messId, String month) async {
    if ((await otherExpenseMonths(messId)).contains(month)) return;

    await _db.collection(_messes).doc(messId).update({
      'otherExpenseMonths': FieldValue.arrayUnion([month]),
    });
  }

  // ---- Other categories ----

  /// Categories of other expense, with their monthly allowances.
  ///
  /// Held on the mess document beside the menu catalogue, so one read covers
  /// both and they inherit the owner-only write rule already protecting it.
  Future<List<CloudOtherCategory>> otherCategories(String messId) async {
    try {
      final doc = await _db.collection(_messes).doc(messId).get();
      final raw = Map<dynamic, dynamic>.from(
          (doc.data()?['otherCategories'] as Map?) ?? const {});

      final list = <CloudOtherCategory>[];
      for (final e in raw.entries) {
        list.add(CloudOtherCategory.fromEntry('${e.key}', e.value));
      }

      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Adds a category. Owner only.
  Future<void> addOtherCategory(String messId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const CloudMessage('Give the category a name.');
    }

    try {
      await _db.collection(_messes).doc(messId).set({
        'otherCategories': {
          clean.toLowerCase(): CloudOtherCategory(name: clean).toDoc(),
        },
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloudMessage('Only the owner can change categories.');
      }
      throw CloudMessage(_friendly(e));
    }
  }

  /// Sets a category's monthly allowance. Zero clears it.
  Future<void> setCategoryBudget(
    String messId,
    String name,
    double budget,
  ) async {
    final clean = name.trim();
    if (clean.isEmpty) return;

    try {
      await _db.collection(_messes).doc(messId).set({
        'otherCategories': {
          clean.toLowerCase(): {'name': clean, 'budget': budget},
        },
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Renames a category everywhere, including on records already filed under it.
  ///
  /// Every month holding a record is rewritten, because a rename that only
  /// changed the list would leave past spending filed under a name that no longer
  /// exists — money the mess spent with nothing to account for it.
  Future<void> renameOtherCategory({
    required String messId,
    required String oldName,
    required String newName,
  }) async {
    final from = oldName.trim();
    final to = newName.trim();

    if (to.isEmpty) {
      throw const CloudMessage('Give the category a name.');
    }
    if (from.toLowerCase() == to.toLowerCase()) return;

    final budget = await _budgetOf(messId, from);

    try {
      await _db.collection(_messes).doc(messId).set({
        'otherCategories': {
          to.toLowerCase(): {'name': to, 'budget': budget},
        },
      }, SetOptions(merge: true));

      await _recategorise(messId, from, to);

      // The old key would otherwise linger as a duplicate and the list would show
      // the same category twice under two names.
      await _db.collection(_messes).doc(messId).update({
        FieldPath(['otherCategories', from.toLowerCase()]): FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes a category.
  ///
  /// With [keepRecords] the entries stay and become "Other"; without it they go
  /// too. Deleting spending is not reversible, so it is a separate decision
  /// rather than the default.
  Future<void> deleteOtherCategory({
    required String messId,
    required String name,
    required bool keepRecords,
  }) async {
    final key = name.trim().toLowerCase();

    try {
      if (keepRecords) {
        await _recategorise(messId, name, 'Other');
      } else {
        for (final month in await otherExpenseMonths(messId)) {
          // A plain string key here, not a FieldPath: set() takes string keys
          // only. With merge:true the delete sentinel removes the whole map
          // while leaving the month field alone.
          await _db
              .collection('$_messes/$messId/otherExpenses')
              .doc(month)
              .set({'entries': FieldValue.delete()},
                  SetOptions(merge: true));
        }
      }

      await _db.collection(_messes).doc(messId).update(<Object, Object?>{
        FieldPath(['otherCategories', key]): FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Rewrites every record filed under [from] so it reads [to].
  Future<void> _recategorise(
    String messId,
    String from,
    String to,
  ) async {
    final wanted = from.trim().toLowerCase();

    for (final month in await otherExpenseMonths(messId)) {
      final ref = _db.collection('$_messes/$messId/otherExpenses').doc(month);
      final snap = await ref.get();
      if (!snap.exists) continue;

      final raw = Map<dynamic, dynamic>.from(
          (snap.data()?['entries'] as Map?) ?? const {});
      if (raw.isEmpty) continue;

      final updates = <FieldPath, Object?>{};
      for (final e in raw.entries) {
        if (e.value is! Map) continue;

        final data = Map<String, dynamic>.from(
            Map<dynamic, dynamic>.from(e.value as Map));
        if ('${data['category']}'.trim().toLowerCase() != wanted) continue;

        updates[FieldPath(['entries', '${e.key}', 'category'])] = to;
      }

      if (updates.isEmpty) continue;
      await ref.update(updates);
    }
  }

  /// A category's current allowance, read so a rename can carry it over.
  Future<double> _budgetOf(String messId, String name) async {
    final wanted = name.trim().toLowerCase();
    for (final c in await otherCategories(messId)) {
      if (c.name.trim().toLowerCase() == wanted) return c.budget;
    }
    return 0;
  }

  // ---- Menu catalogue ----

  /// The whole catalogue, or an empty one when the mess has none yet.
  ///
  /// The roster already lives on the mess document, and so does the catalogue:
  /// putting the menus in the same place means one read covers both, and keeps
  /// the owner-only write rule that already protects the mess document.
  Future<MenuCatalogue> menus(String messId) async {
    final doc = await _db.collection(_messes).doc(messId).get();
    if (!doc.exists) return const MenuCatalogue.empty();

    final raw = Map<dynamic, dynamic>.from(
        (doc.data()?['menus'] as Map?) ?? const {});

    final list = <CloudMenu>[];
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) {
        list.add(CloudMenu.fromEntry(
          '${entry.key}',
          Map<dynamic, dynamic>.from(value),
        ));
      }
    }
    list.sort(compareMenus);

    return MenuCatalogue(list);
  }

  /// Saves the whole catalogue in one write.
  ///
  /// Sorted on the way out, so a reorder is stored as the order the user sees
  /// rather than depending on how the list happened to be assembled.
  Future<void> saveMenus(
    String messId,
    List<CloudMenu> menus,
  ) async {
    try {
      await _db.collection(_messes).doc(messId).update({
        'menus': {for (final m in sortMenus(menus)) m.id: m.toEntry()},
      });
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Adds a menu, optionally with the starter menus when the mess has none.
  Future<void> addMenu(
    String messId,
    String name, {
    List<CloudMenu>? existing,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const CloudMessage('Give the menu a name.');
    }

    final current = existing ?? (await menus(messId)).menus;
    if (current.any((m) => m.name.toLowerCase() == clean.toLowerCase())) {
      throw const CloudMessage('A menu with that name already exists.');
    }

    await saveMenus(messId, [
      ...current,
      CloudMenu(id: newMenuId(), name: clean, order: current.length),
    ]);
  }

  Future<void> renameMenu(
    String messId,
    List<CloudMenu> existing,
    String menuId,
    String name,
  ) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const CloudMessage('Give the menu a name.');
    }

    await saveMenus(messId, [
      for (final m in existing)
        if (m.id == menuId) m.copyWith(name: clean) else m,
    ]);
  }

  Future<void> deleteMenu(
    String messId,
    List<CloudMenu> existing,
    String menuId,
  ) async {
    await saveMenus(
        messId, existing.where((m) => m.id != menuId).toList());
  }

  /// Adds an item to a menu.
  Future<void> addMenuItem(
    String messId,
    List<CloudMenu> existing,
    String menuId, {
    required String name,
    double defaultPrice = 0,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const CloudMessage('Give the item a name.');
    }

    await saveMenus(messId, [
      for (final m in existing)
        if (m.id == menuId)
          m.copyWith(items: [
            ...m.items,
            CloudMenuItem(
              id: newMenuItemId(),
              name: clean,
              defaultPrice: defaultPrice,
              // Placed at the end so a new item never reorders the rest.
              order: m.items.isEmpty ? 0 : m.items.last.order + 1,
            ),
          ])
        else
          m,
    ]);
  }

  Future<void> updateMenuItem(
    String messId,
    List<CloudMenu> existing,
    String menuId,
    String itemId, {
    required String name,
    double defaultPrice = 0,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const CloudMessage('Give the item a name.');
    }

    await saveMenus(messId, [
      for (final m in existing)
        if (m.id == menuId)
          m.copyWith(items: [
            for (final i in m.items)
              if (i.id == itemId)
                i.copyWith(name: clean, defaultPrice: defaultPrice)
              else
                i,
          ])
        else
          m,
    ]);
  }

  Future<void> deleteMenuItem(
    String messId,
    List<CloudMenu> existing,
    String menuId,
    String itemId,
  ) async {
    await saveMenus(messId, [
      for (final m in existing)
        if (m.id == menuId)
          m.copyWith(items: m.items.where((i) => i.id != itemId).toList())
        else
          m,
    ]);
  }

  /// Saves a new item order after a drag.
  ///
  /// Only the order changes, so nothing typed by the user can be lost by a
  /// reorder the way a full rewrite could.
  Future<void> reorderMenuItems(
    String messId,
    List<CloudMenu> existing,
    String menuId,
    List<String> itemIds,
  ) async {
    final position = <String, int>{
      for (var i = 0; i < itemIds.length; i++) itemIds[i]: i,
    };

    await saveMenus(messId, [
      for (final m in existing)
        if (m.id == menuId)
          m.copyWith(items: [
            for (final i in m.items)
              CloudMenuItem(
                id: i.id,
                name: i.name,
                defaultPrice: i.defaultPrice,
                order: position[i.id] ?? i.order,
              ),
          ])
        else
          m,
    ]);
  }

  // ---- Collections ----

  /// Reads every member's collection for a month.
  ///
  /// One document read per member rather than a query, so the security rule can
  /// be proven and Firestore cannot deny it. A mess is a handful of people
  /// sharing a kitchen, so a few reads cost less than the complexity of making
  /// a query provable.
  Future<Map<String, MemberCollection>> collectionsFor(
    String messId,
    String month,
    List<MessMember> roster,
  ) async {
    final result = <String, MemberCollection>{};

    for (final member in roster) {
      final email = member.email.trim().toLowerCase();
      if (email.isEmpty) continue;
      result[email] = await collectionFor(messId, email, month);
    }

    return result;
  }

  /// One member's collection for a month. Missing means no share is set.
  Future<MemberCollection> collectionFor(
    String messId,
    String email,
    String month,
  ) async {
    final doc = await _db
        .collection('$_messes/$messId/collections')
        .doc(collectionDocId(email, month))
        .get();

    if (!doc.exists) {
      return MemberCollection(email: email, month: month, amountDue: 0);
    }

    final data = doc.data() ?? const {};

    // Payments live in a map. An earlier build wrote each one as a field
    // literally NAMED "payments.<key>" rather than an entry inside the map, so
    // both shapes are read here. Without this, payments already recorded on that
    // build would stay invisible, which is worse than a duplicate.
    final raw =
        Map<dynamic, dynamic>.from((data['payments'] as Map?) ?? const {});
    final payments = <CloudPayment>[];

    void addEntry(String id, Map<dynamic, dynamic> p) {
      payments.add(CloudPayment(
        id: id,
        amount: (p['amount'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse('${p['date'] ?? ''}'),
        recordedBy: p['recordedBy'] as String?,
      ));
    }

    for (final entry in raw.entries) {
      final p = entry.value;
      if (p is Map) addEntry('${entry.key}', Map<dynamic, dynamic>.from(p));
    }

    for (final entry in data.entries) {
      final key = entry.key;
      if (key is String &&
          key.startsWith('payments.') &&
          entry.value is Map) {
        addEntry(
          key.substring('payments.'.length),
          Map<dynamic, dynamic>.from(entry.value as Map),
        );
      }
    }

    // Newest first. Null dates sort last so a malformed row does not jump to the
    // top of the history.
    payments.sort((a, b) {
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });

    return MemberCollection(
      email: email,
      month: month,
      amountDue: (data['amountDue'] as num?)?.toDouble() ?? 0,
      payments: payments,
    );
  }

  /// Sets one member's monthly share. Owner only.
  Future<void> setMonthlyShare({
    required String messId,
    required String email,
    required String month,
    required double amount,
  }) async {
    try {
      // Merge, so setting a share never discards payments already recorded
      // against it.
      await _db
          .collection('$_messes/$messId/collections')
          .doc(collectionDocId(email, month))
          .set({
        'email': email.trim().toLowerCase(),
        'month': month,
        'amountDue': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Sets the same share for everybody in the mess. Owner only.
  Future<void> setMonthlyShareForAll({
    required String messId,
    required String month,
    required double amount,
    required List<MessMember> roster,
  }) async {
    for (final member in roster) {
      await setMonthlyShare(
        messId: messId,
        email: member.email,
        month: month,
        amount: amount,
      );
    }
  }

  /// Records a payment against a member's month. Owner only.
  ///
  /// The payment is appended under a key generated from the clock rather than
  /// stored as a list index, so two payments recorded at the same moment cannot
  /// overwrite one another.
  Future<void> addCollectionPayment({
    required String messId,
    required String email,
    required String month,
    required double amount,
    required String date,
  }) async {
    if (amount <= 0) {
      throw const CloudMessage('Enter an amount greater than zero.');
    }

    try {
      final ref = _db
          .collection('$_messes/$messId/collections')
          .doc(collectionDocId(email, month));

      // Create the document if it is missing, then add the payment as a proper
      // nested entry using a FieldPath.
      //
      // The obvious version of this — a 'payments.<key>' string key inside a
      // merged set — silently writes a field literally NAMED "payments.<key>"
      // rather than an entry in the payments map, so the payment saves and the
      // history then reads as empty. A FieldPath is the only way to add one
      // entry to a map without first reading the whole map.
      await ref.set({
        'email': email.trim().toLowerCase(),
        'month': month,
        'amountDue': 0,
      }, SetOptions(merge: true));

      await ref.update({
          FieldPath(['payments', '${DateTime.now().microsecondsSinceEpoch}']): {
            'amount': amount,
            'date': date,
            'recordedBy': _myEmail,
            'at': FieldValue.serverTimestamp(),
          }
        });
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  /// Removes a payment. Owner only.
  Future<void> removeCollectionPayment({
    required String messId,
    required String email,
    required String month,
    required String paymentId,
  }) async {
    try {
      await _db
          .collection('$_messes/$messId/collections')
          .doc(collectionDocId(email, month))
          // A FieldPath for the same reason as the write: a string key of
          // "payments.<id>" would target a field of that name instead of the
          // entry inside the map.
          .update({FieldPath(['payments', paymentId]): FieldValue.delete()});
    } on FirebaseException catch (e) {
      throw CloudMessage(_friendly(e));
    }
  }

  // ---- Cooking turn ----

  /// Sets whose turn it is. Owner only.
  ///
  /// Stores the anchor rather than a list of dates: the schedule is then always
  /// derived from the roster, so it cannot disagree with who is actually in the
  /// mess. Anyone added or removed reshapes the cycle automatically.
  ///
  /// [order] is the preferred cooking order, as member emails.
  Future<void> setTurn({
    required String messId,
    required DateTime anchorDate,
    required String anchorEmail,
    List<String> order = const [],
  }) async {
    final clean = anchorEmail.trim().toLowerCase();
    if (!clean.contains('@')) {
      throw const CloudMessage('Pick who should have the bari today.');
    }

    try {
      await _db.collection(_messes).doc(messId).update({
        'rotation': {
          'anchorDate': _dateKey(anchorDate),
          'anchorEmail': clean,
          'order': order.map((e) => e.trim().toLowerCase()).toList(),
          'manual': true,
          'updatedBy': _myEmail,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } on FirebaseException catch (e) {
      // Only the owner may change the turn. Reported plainly, because the owner
      // action button is the only place this is called from.
      throw CloudMessage(_friendly(e));
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---- Helpers ----

  /// Short, unambiguous code. Ambiguous characters (0/O, 1/I) are left out so
  /// it can be read aloud across a room without mistakes.
  String _generateJoinCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  String _friendly(FirebaseException e) {
    if (e.code == 'permission-denied') {
      // Nearly always means the published rules are older than the app, since
      // the app never asks for anything a member should not have.
      return 'MessApp could not read your mess. This usually means the app '
          'rules need updating in the Firebase console.';
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      return 'Could not reach the server. Check your connection.';
    }
    return e.message ?? 'Something went wrong. Please try again.';
  }
}